#!/usr/bin/env bash
# dependencies.sh: Resolve and install all dependencies for Debezium and Iceberg plugins
# Usage:
#   ./dependencies.sh
#   DEBUG=1 ./dependencies.sh   # extra-verbose
set -euo pipefail

DEBUG="${DEBUG:-0}"
[[ "$DEBUG" == "1" ]] && set -x

# ---- Versions ----
DEBEZIUM_VERSION="${DEBEZIUM_VERSION:-3.1.2.Final}"
ICEBERG_VERSION="${ICEBERG_VERSION:-1.9.2}"
HADOOP_VERSION="${HADOOP_VERSION:-3.3.6}"
HIVE_MS_VERSION="${HIVE_MS_VERSION:-3.1.3}"

# ---- Paths ----
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGINS_DIR="${ROOT_DIR}/kafka/plugins"
DBZ_PLUGIN_DIR="${PLUGINS_DIR}/debezium-connector-postgres"
IC_PLUGIN_DIR="${PLUGINS_DIR}/iceberg-kafka-connect"

STAGE_ROOT="${ROOT_DIR}/target/dependencies"
STAGE_DBZ="${STAGE_ROOT}/debezium-subfolder"
STAGE_IC="${STAGE_ROOT}/iceberg-subfolder"

MDEP="org.apache.maven.plugins:maven-dependency-plugin:3.6.1"

log() { printf "\n=== %s ===\n" "$*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

# ---- Maven flags ----
if [[ "$DEBUG" == "1" ]]; then
  MVN=(mvn -U -e -X -DskipTests)
else
  MVN=(mvn -U -B -q -DskipTests)
fi

# ---- Clean & prep ----
mkdir -p "${DBZ_PLUGIN_DIR}" "${IC_PLUGIN_DIR}" "${STAGE_DBZ}" "${STAGE_IC}"
rm -rf "${STAGE_DBZ:?}/"* "${STAGE_IC:?}/"* "${ROOT_DIR}/target/dependency" || true

log "Java & Maven versions"
(java -version || true) 2>&1
(mvn -version || true) 2>&1

# ---- A) Debezium Postgres plugin ZIP ----
log "A1) Debezium Postgres connector -> ${STAGE_DBZ}"
"${MVN[@]}" "${MDEP}:copy" \
  -Dartifact="io.debezium:debezium-connector-postgres:${DEBEZIUM_VERSION}:zip:plugin" \
  -DoutputDirectory="${STAGE_DBZ}"
DBZ_ZIP="$(ls -1 "${STAGE_DBZ}"/debezium-connector-postgres-*plugin.zip | head -n1 || true)"
[[ -n "${DBZ_ZIP}" ]] || die "Debezium plugin ZIP not found in ${STAGE_DBZ}"

log "A2) Extract Debezium plugin"
if command -v unzip >/dev/null 2>&1; then unzip -q -o -d "${STAGE_DBZ}" "${DBZ_ZIP}"; else ( cd "${STAGE_DBZ}" && jar xf "${DBZ_ZIP}" ); fi

log "A3) Install Debezium jars -> ${DBZ_PLUGIN_DIR}"
find "${STAGE_DBZ}" -type f -name "*.jar" -print0 | xargs -0 -I{} cp -f "{}" "${DBZ_PLUGIN_DIR}/"

# ---- B) Iceberg + HMS + Hadoop (ALL runtime deps + transitives) ----
log "B1) Resolve ALL runtime deps -> ${STAGE_IC}"
"${MVN[@]}" "${MDEP}:copy-dependencies" \
  -DincludeScope=runtime \
  -DexcludeTransitive=false \
  -DoutputDirectory="${STAGE_IC}"

# Optional: print dependency tree
[[ "$DEBUG" == "1" ]] && { log "B1b) dependency:tree (runtime)"; mvn -U -Dscope=runtime dependency:tree || true; }

log "B2) Sanity-check staged jars"
CLASS_S3FILEIO='org/apache/iceberg/aws/s3/S3FileIO.class'
CLASS_SDKEXC='software/amazon/awssdk/core/exception/SdkException.class'
CLASS_S3EXC='software/amazon/awssdk/services/s3/model/S3Exception.class'
CLASS_HMS_NO='org/apache/hadoop/hive/metastore/api/NoSuchObjectException.class'
CLASS_JOBCONF='org/apache/hadoop/mapred/JobConf.class'

# Sanity checks for formats (Parquet, ORC, Avro from avro.jar)
CLASS_PARQUET='org/apache/iceberg/parquet/Parquet.class'
CLASS_ORC='org/apache/iceberg/orc/ORC.class'
CLASS_AVRO='org/apache/avro/Schema.class'  # From avro.jar for Iceberg Avro support

find_one_with() { local c="$1"; shopt -s nullglob; for j in "${STAGE_IC}"/*.jar; do jar tf "$j" | grep -q "$c" && { echo "$j"; return 0; }; done; return 1; }

J_S3="$(find_one_with "$CLASS_S3FILEIO" || true)"
J_SK="$(find_one_with "$CLASS_SDKEXC" || true)"
J_S3E="$(find_one_with "$CLASS_S3EXC" || true)"
J_HN="$(find_one_with "$CLASS_HMS_NO" || true)"
J_JC="$(find_one_with "$CLASS_JOBCONF" || true)"

J_PQ="$(find_one_with "$CLASS_PARQUET" || true)"
J_ORC="$(find_one_with "$CLASS_ORC" || true)"
J_AVRO="$(find_one_with "$CLASS_AVRO" || true)"

# Fallbacks if something is missing
if [[ -z "$J_S3" || -z "$J_SK" || -z "$J_S3E" ]]; then
  echo "Pulling iceberg-aws-bundle explicitly to satisfy S3FileIO + AWS SDK v2…"
  "${MVN[@]}" "${MDEP}:copy" -Dartifact="org.apache.iceberg:iceberg-aws-bundle:${ICEBERG_VERSION}" -DoutputDirectory="${STAGE_IC}" || true
  J_S3="$(find_one_with "$CLASS_S3FILEIO" || true)"
  J_SK="$(find_one_with "$CLASS_SDKEXC" || true)"
  J_S3E="$(find_one_with "$CLASS_S3EXC" || true)"
fi

if [[ -z "$J_HN" ]]; then
  echo "Ensuring Hive Metastore Thrift classes are present…"
  "${MVN[@]}" "${MDEP}:copy" -Dartifact="org.apache.hive:hive-standalone-metastore:${HIVE_MS_VERSION}" -DoutputDirectory="${STAGE_IC}" || true
  "${MVN[@]}" "${MDEP}:copy" -Dartifact="org.apache.hive:hive-metastore:${HIVE_MS_VERSION}" -DoutputDirectory="${STAGE_IC}" || true
  J_HN="$(find_one_with "$CLASS_HMS_NO" || true)"
fi

if [[ -z "$J_JC" ]]; then
  echo "Ensuring Hadoop JobConf is present…"
  "${MVN[@]}" "${MDEP}:copy" -Dartifact="org.apache.hadoop:hadoop-mapreduce-client-core:${HADOOP_VERSION}" -DoutputDirectory="${STAGE_IC}" || true
  "${MVN[@]}" "${MDEP}:copy" -Dartifact="org.apache.hadoop:hadoop-common:${HADOOP_VERSION}" -DoutputDirectory="${STAGE_IC}" || true
  J_JC="$(find_one_with "$CLASS_JOBCONF" || true)"
fi

# Fallbacks for formats
if [[ -z "$J_PQ" ]]; then
  echo "Pulling iceberg-parquet explicitly…"
  "${MVN[@]}" "${MDEP}:copy" -Dartifact="org.apache.iceberg:iceberg-parquet:${ICEBERG_VERSION}" -DoutputDirectory="${STAGE_IC}" || true
  J_PQ="$(find_one_with "$CLASS_PARQUET" || true)"
fi

if [[ -z "$J_ORC" ]]; then
  echo "Pulling iceberg-orc explicitly…"
  "${MVN[@]}" "${MDEP}:copy" -Dartifact="org.apache.iceberg:iceberg-orc:${ICEBERG_VERSION}" -DoutputDirectory="${STAGE_IC}" || true
  J_ORC="$(find_one_with "$CLASS_ORC" || true)"
fi

if [[ -z "$J_AVRO" ]]; then
  echo "Pulling avro explicitly for Iceberg Avro support…"
  "${MVN[@]}" "${MDEP}:copy" -Dartifact="org.apache.avro:avro:1.12.0" -DoutputDirectory="${STAGE_IC}" || true
  J_AVRO="$(find_one_with "$CLASS_AVRO" || true)"
fi

[[ -n "$J_S3"  ]] || die "Missing S3FileIO ($CLASS_S3FILEIO)"
[[ -n "$J_SK"  ]] || die "Missing AWS SDK core ($CLASS_SDKEXC)"
[[ -n "$J_S3E" ]] || die "Missing AWS S3Exception ($CLASS_S3EXC)"
[[ -n "$J_HN"  ]] || die "Missing HiveMS Thrift ($CLASS_HMS_NO)"
[[ -n "$J_JC"  ]] || die "Missing Hadoop JobConf ($CLASS_JOBCONF)"

[[ -n "$J_PQ" ]] || die "Missing Iceberg Parquet ($CLASS_PARQUET)"
[[ -n "$J_ORC" ]] || die "Missing Iceberg ORC ($CLASS_ORC)"
[[ -n "$J_AVRO" ]] || die "Missing Avro for Iceberg ($CLASS_AVRO)"

echo "OK: S3FileIO            => $J_S3"
echo "OK: AWS SdkException    => $J_SK"
echo "OK: AWS S3Exception     => $J_S3E"
echo "OK: HMS NoSuchObject    => $J_HN"
echo "OK: Hadoop JobConf      => $J_JC"

echo "OK: Iceberg Parquet     => $J_PQ"
echo "OK: Iceberg ORC         => $J_ORC"
echo "OK: Avro for Iceberg    => $J_AVRO"

log "B3) Install ALL jars -> ${IC_PLUGIN_DIR}"
find "${IC_PLUGIN_DIR}" -type f -name "*.jar" -delete || true
find "${STAGE_IC}" -type f -name "*.jar" -print0 | xargs -0 -I{} cp -f "{}" "${IC_PLUGIN_DIR}/"

log "Installed plugin dirs:"
echo "  - Debezium -> ${DBZ_PLUGIN_DIR}"
echo "  - Iceberg  -> ${IC_PLUGIN_DIR}"
echo "  (Worker plugin.path must include /opt/kafka/plugins; your file already does.)"
#!/usr/bin/env bash
# dependencies.sh: Resolve and install all dependencies for Debezium and Iceberg plugins using pom.xml
# Usage:
#   ./dependencies.sh
#   DEBUG=1 ./dependencies.sh   # extra-verbose
set -euo pipefail

DEBUG="${DEBUG:-0}"
[[ "$DEBUG" == "1" ]] && set -x

# ---- Versions ----
DEBEZIUM_VERSION="${DEBEZIUM_VERSION:-3.2.0.Final}"
ICEBERG_VERSION="${ICEBERG_VERSION:-1.9.2}"

# ---- Paths ----
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGINS_DIR="${ROOT_DIR}/kafka/plugins"
DBZ_PLUGIN_DIR="${PLUGINS_DIR}/debezium-connector-sqlserver"
IC_PLUGIN_DIR="${PLUGINS_DIR}/iceberg-kafka-connect"
STAGE_ROOT="${ROOT_DIR}/target/dependencies"
STAGE_DBZ="${STAGE_ROOT}/debezium-subfolder"
STAGE_IC="${STAGE_ROOT}/iceberg-subfolder"

MDEP="org.apache.maven.plugins:maven-dependency-plugin:3.6.1"

log() { printf "\n=== %s ===\n" "$*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

# ---- Check Java and Maven ----
log "Checking Java and Maven environment"
if ! command -v java >/dev/null 2>&1; then
  die "Java not found. Please install Java 17 or later."
fi
JAVA_VERSION=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}' | cut -d'.' -f1)
if [[ "$JAVA_VERSION" -lt 17 ]]; then
  die "Java 17 or later required. Found Java $JAVA_VERSION."
fi
if ! command -v mvn >/dev/null 2>&1; then
  die "Maven not found. Please install Maven."
fi
if [[ ! -f "$ROOT_DIR/pom.xml" ]]; then
  die "pom.xml not found in $ROOT_DIR."
fi
log "Java & Maven versions"
java -version 2>&1
mvn -version 2>&1

# ---- Maven flags ----
if [[ "$DEBUG" == "1" ]]; then
  MVN=(mvn -U -e -X -DskipTests)
else
  MVN=(mvn -U -B -q -DskipTests)
fi

# ---- Clean & prep ----
log "Cleaning plugin directories"
rm -rf "${PLUGINS_DIR:?}/"* "${STAGE_DBZ:?}/"* "${STAGE_IC:?}/"* "${ROOT_DIR}/target/dependency" || true
mkdir -p "${DBZ_PLUGIN_DIR}" "${IC_PLUGIN_DIR}" "${STAGE_DBZ}" "${STAGE_IC}"

# ---- A) Debezium SQL Server plugin ZIP ----
log "A1) Debezium SQL Server connector -> ${STAGE_DBZ}"
"${MVN[@]}" "${MDEP}:copy" \
  -Dartifact="io.debezium:debezium-connector-sqlserver:${DEBEZIUM_VERSION}:zip:plugin" \
  -DoutputDirectory="${STAGE_DBZ}"
DBZ_ZIP="$(ls -1 "${STAGE_DBZ}"/debezium-connector-sqlserver-*plugin.zip | head -n1 || true)"
[[ -n "${DBZ_ZIP}" ]] || die "Debezium plugin ZIP not found in ${STAGE_DBZ}"

log "A2) Extract Debezium plugin"
if command -v unzip >/dev/null 2>&1; then
  unzip -q -o -d "${STAGE_DBZ}" "${DBZ_ZIP}"
else
  (cd "${STAGE_DBZ}" && jar xf "${DBZ_ZIP}")
fi

log "A3) Install Debezium jars -> ${DBZ_PLUGIN_DIR}"
find "${STAGE_DBZ}" -type f -name "*.jar" -print0 | xargs -0 -I{} cp -f "{}" "${DBZ_PLUGIN_DIR}/"

# ---- B) Iceberg + dependencies from pom.xml ----
log "B1) Resolve dependencies from pom.xml -> ${STAGE_IC}"
"${MVN[@]}" "${MDEP}:copy-dependencies" \
  -DincludeScope=runtime \
  -DexcludeTransitive=false \
  -DoutputDirectory="${STAGE_IC}" || die "Failed to fetch dependencies from pom.xml"

log "B2) Install jars -> ${IC_PLUGIN_DIR}"
find "${IC_PLUGIN_DIR}" -type f -name "*.jar" -delete || true
find "${STAGE_IC}" -type f -name "*.jar" -print0 | xargs -0 -I{} cp -f "{}" "${IC_PLUGIN_DIR}/"

log "Installed plugin dirs:"
echo "  - Debezium -> ${DBZ_PLUGIN_DIR}"
echo "  - Iceberg  -> ${IC_PLUGIN_DIR}"
echo "  (Worker plugin.path must include /opt/kafka/plugins)"
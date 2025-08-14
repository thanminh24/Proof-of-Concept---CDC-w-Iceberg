#!/usr/bin/env bash
set -euo pipefail

DEBUG="${DEBUG:-0}"
[[ "$DEBUG" == "1" ]] && set -x

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SVC_KAFKA="kafka-standalone"
DELAY_BEFORE_SERVER="${DELAY_BEFORE_SERVER:-10}"
log() { printf "\n=== %s ===\n" "$*"; }

log "C1) docker compose up -d"
docker compose up -d

log "D1) Sleeping ${DELAY_BEFORE_SERVER}s"
sleep "${DELAY_BEFORE_SERVER}"

log "D2) Checking if ${SVC_KAFKA} is running"
if ! docker compose ps --filter "status=running" | grep -q "${SVC_KAFKA}"; then
  echo "ERROR: ${SVC_KAFKA} is not running"
  docker compose logs "${SVC_KAFKA}"
  exit 1
fi

log "D3) Creating schema history topic"
docker compose exec "${SVC_KAFKA}" \
  /opt/kafka/bin/kafka-topics.sh \
  --create \
  --bootstrap-server kafka-standalone:9092 \
  --replication-factor 1 \
  --partitions 1 \
  --topic schemahistory.commerce || echo "Topic schemahistory.commerce already exists or failed to create"

log "E1) Starting Connect standalone"
docker compose exec -d "${SVC_KAFKA}" \
  /opt/kafka/bin/connect-standalone.sh \
  /opt/kafka/config-cdc/connect-standalone.properties \
  /opt/kafka/config-cdc/connect-sqlserver-source.json \
  /opt/kafka/config-cdc/connect-iceberg-sink.json

echo "Tail logs: docker compose logs -f ${SVC_KAFKA}"
echo "Status: curl http://localhost:8083/connectors/dbz-sqlserver-source/status | jq"
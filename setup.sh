#!/usr/bin/env bash
# setup.sh: Launch infrastructure and Connect after dependencies
# Usage:
#   ./setup.sh
#   DEBUG=1 ./setup.sh   # extra-verbose
set -euo pipefail

DEBUG="${DEBUG:-0}"
[[ "$DEBUG" == "1" ]] && set -x

# ---- Paths ----
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- Services & timing ----
SVC_KAFKA="${SVC_KAFKA:-kafka-standalone}"
DELAY_BEFORE_SERVER="${DELAY_BEFORE_SERVER:-10}"
log() { printf "\n=== %s ===\n" "$*"; }

# ---- C) Bring up infra ----
log "C1) docker compose up -d"
docker compose up -d

# ---- D) Delay then start Connect standalone ----
log "D1) Sleeping ${DELAY_BEFORE_SERVER}s before starting Connect…"
sleep "${DELAY_BEFORE_SERVER}"

log "E1) Starting Connect (standalone) with your configs"
docker compose exec -d "${SVC_KAFKA}" \
  /opt/kafka/bin/connect-standalone.sh \
  /opt/kafka/config-cdc/connect-standalone.properties \
  /opt/kafka/config-cdc/connect-sqlserver-source.json \
  /opt/kafka/config-cdc/connect-iceberg-sink.json

echo
echo "Tail logs:"
echo "  docker compose logs -f ${SVC_KAFKA} | sed -n '1,200p'"
echo
echo "Check status:"
echo "  curl -s http://localhost:8083/connectors/dbz-sqlserver-source/status | jq"
echo "  curl -s http://localhost:8083/connectors/iceberg-sink/status | jq"

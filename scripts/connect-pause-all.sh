#!/usr/bin/env bash
# =============================================================================
# Pause/Resume all Kafka Connect connectors
# Usage: ./connect-pause-all.sh pause|resume
# =============================================================================
set -euo pipefail

CONNECT_URL="${FSI_CONNECT_URL:-http://localhost:8083}"
ACTION="${1:?Usage: $0 pause|resume}"

[[ "${ACTION}" =~ ^(pause|resume)$ ]] || { echo "Invalid action. Use: pause or resume"; exit 1; }

echo "=== ${ACTION^^} all connectors at ${CONNECT_URL} ==="

CONNECTORS=$(curl -s "${CONNECT_URL}/connectors" | jq -r '.[]')

for CONNECTOR in ${CONNECTORS}; do
  echo "  ${ACTION}: ${CONNECTOR}"
  curl -s -X PUT "${CONNECT_URL}/connectors/${CONNECTOR}/${ACTION}" > /dev/null
done

echo ""
echo "Current status:"
for CONNECTOR in ${CONNECTORS}; do
  STATUS=$(curl -s "${CONNECT_URL}/connectors/${CONNECTOR}/status" | jq -r '.connector.state')
  echo "  ${CONNECTOR}: ${STATUS}"
done

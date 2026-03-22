#!/usr/bin/env bash
# =============================================================================
# Flip active region in Consul KV — triggers Kafka + SR + Oracle endpoint changes
# Usage: ./consul-flip-region.sh east|west
# =============================================================================
set -euo pipefail

CONSUL_ADDR="${CONSUL_HTTP_ADDR:-http://localhost:8500}"
REGION="${1:?Usage: $0 east|west}"

[[ "${REGION}" =~ ^(east|west)$ ]] || { echo "Invalid region. Use: east or west"; exit 1; }

echo "=== Flipping active region to: ${REGION} ==="

# Update the active-region key
consul kv put fsi/kafka/active-region "${REGION}"

# Verify
CURRENT=$(consul kv get fsi/kafka/active-region)
echo "Active region is now: ${CURRENT}"

# Show what endpoints resolve to
echo ""
echo "Endpoint resolution:"
echo "  kafka.fsi.internal  -> $(dig +short kafka.fsi.internal 2>/dev/null || echo 'DNS not configured')"
echo "  schema.fsi.internal -> $(dig +short schema.fsi.internal 2>/dev/null || echo 'DNS not configured')"
echo "  oracle.fsi.internal -> $(dig +short oracle.fsi.internal 2>/dev/null || echo 'DNS not configured')"

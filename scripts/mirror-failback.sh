#!/usr/bin/env bash
# =============================================================================
# FSI DR Failback — Restore East as primary
# Run after outage ends and East cluster is available
# =============================================================================
set -euo pipefail

PROD_ENV_ID="${FSI_PROD_ENV_ID:?Set FSI_PROD_ENV_ID}"
PROD_CLUSTER_ID="${FSI_PROD_CLUSTER_ID:?Set FSI_PROD_CLUSTER_ID}"
LINK_NAME="${FSI_CLUSTER_LINK_NAME:-cluster_link_bidir_east_west}"

echo "=== FSI DR FAILBACK — Restore East Primary ==="
confluent environment use "${PROD_ENV_ID}"
confluent kafka cluster use "${PROD_CLUSTER_ID}"

# Step 1: truncate-and-restore (East topics become mirrors, copy data from West)
TOPICS=$(confluent kafka topic list -o json | jq -r '.[].name' | grep -v '^_' | tr '\n' ' ')
echo "Topics to restore: ${TOPICS}"
read -p "Proceed with truncate-and-restore? (yes/no): " CONFIRM
[ "${CONFIRM}" = "yes" ] || { echo "Aborted."; exit 1; }

# shellcheck disable=SC2086
confluent kafka mirror truncate-and-restore ${TOPICS} --link "${LINK_NAME}"

echo "Waiting for data sync..."
sleep 30

echo "Verifying mirror status (should be ACTIVE)..."
confluent kafka mirror list --link "${LINK_NAME}"

read -p "Data synced. Proceed with reverse-and-start? (yes/no): " CONFIRM
[ "${CONFIRM}" = "yes" ] || { echo "Aborted."; exit 1; }

# Step 2: reverse-and-start (East becomes R/W, West becomes mirrors)
# shellcheck disable=SC2086
confluent kafka mirror reverse-and-start ${TOPICS} --link "${LINK_NAME}"

echo ""
echo "Verifying final state (should be STOPPED = R/W on East)..."
confluent kafka mirror list --link "${LINK_NAME}"

echo ""
echo "=== Failback complete. Flip Consul to East and restart apps. ==="

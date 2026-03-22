#!/usr/bin/env bash
# =============================================================================
# FSI DR Failover — Promote mirror topics in West DR cluster
# Step 1 of the 6-step failover sequence
# =============================================================================
set -euo pipefail

DR_ENV_ID="${FSI_DR_ENV_ID:?Set FSI_DR_ENV_ID}"
DR_CLUSTER_ID="${FSI_DR_CLUSTER_ID:?Set FSI_DR_CLUSTER_ID}"
LINK_NAME="${FSI_CLUSTER_LINK_NAME:-cluster_link_bidir_east_west}"

echo "=== FSI DR FAILOVER — Mirror Topic Promotion ==="
echo "Environment: ${DR_ENV_ID}"
echo "Cluster:     ${DR_CLUSTER_ID}"
echo "Link:        ${LINK_NAME}"
echo ""

confluent environment use "${DR_ENV_ID}"
confluent kafka cluster use "${DR_CLUSTER_ID}"

# Get all mirror topics on this link
echo "Listing mirror topics..."
MIRROR_TOPICS=$(confluent kafka mirror list --link "${LINK_NAME}" -o json \
  | jq -r '.[] | select(.status == "ACTIVE") | .mirror_topic_name' \
  | tr '\n' ' ')

if [ -z "${MIRROR_TOPICS}" ]; then
  echo "ERROR: No active mirror topics found. Check link status."
  exit 1
fi

echo "Promoting topics: ${MIRROR_TOPICS}"
echo ""
read -p "Proceed with failover? (yes/no): " CONFIRM
[ "${CONFIRM}" = "yes" ] || { echo "Aborted."; exit 1; }

# shellcheck disable=SC2086
confluent kafka mirror failover ${MIRROR_TOPICS} --link "${LINK_NAME}"

echo ""
echo "Verifying promotion..."
confluent kafka mirror list --link "${LINK_NAME}"

echo ""
echo "=== Step 1 complete. Proceed to Consul flip (Step 2). ==="

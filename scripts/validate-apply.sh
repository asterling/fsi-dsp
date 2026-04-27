#!/usr/bin/env bash
# =============================================================================
# Post-Apply Validation -- Verify Confluent Cloud resources after terraform apply
# =============================================================================
# Usage: validate-apply.sh <kafka-rest> <cluster-id> <sr-rest> \
#          <kafka-key> <kafka-secret> <sr-key> <sr-secret> \
#          [--dr-rest <url> --dr-cluster <id> --dr-key <key> --dr-secret <secret>] \
#          --topics <topic1> [topic2] [topic3] ...
#
# Exit codes:
#   0 = all checks passed
#   1 = one or more checks failed
#   2 = usage error
# =============================================================================
set -euo pipefail

# --- Parse arguments ---
KAFKA_REST_ENDPOINT=""
KAFKA_CLUSTER_ID=""
SR_REST_ENDPOINT=""
KAFKA_API_KEY=""
KAFKA_API_SECRET=""
SR_API_KEY=""
SR_API_SECRET=""
DR_KAFKA_REST_ENDPOINT=""
DR_KAFKA_CLUSTER_ID=""
DR_KAFKA_API_KEY=""
DR_KAFKA_API_SECRET=""
TOPICS=()

# Positional args (first 7 required)
if [ $# -lt 7 ]; then
  echo "ERROR: Missing required arguments."
  echo "Usage: validate-apply.sh <kafka-rest> <cluster-id> <sr-rest> <kafka-key> <kafka-secret> <sr-key> <sr-secret> [--dr-rest ...] --topics <topic1> ..."
  exit 2
fi

KAFKA_REST_ENDPOINT="$1"; shift
KAFKA_CLUSTER_ID="$1"; shift
SR_REST_ENDPOINT="$1"; shift
KAFKA_API_KEY="$1"; shift
KAFKA_API_SECRET="$1"; shift
SR_API_KEY="$1"; shift
SR_API_SECRET="$1"; shift

# Named args
while [ $# -gt 0 ]; do
  case "$1" in
    --dr-rest)     DR_KAFKA_REST_ENDPOINT="$2"; shift 2 ;;
    --dr-cluster)  DR_KAFKA_CLUSTER_ID="$2"; shift 2 ;;
    --dr-key)      DR_KAFKA_API_KEY="$2"; shift 2 ;;
    --dr-secret)   DR_KAFKA_API_SECRET="$2"; shift 2 ;;
    --topics)      shift; while [ $# -gt 0 ] && [[ "$1" != --* ]]; do TOPICS+=("$1"); shift; done ;;
    *)             echo "ERROR: Unknown argument: $1"; exit 2 ;;
  esac
done

if [ ${#TOPICS[@]} -eq 0 ]; then
  echo "ERROR: No topics specified. Use --topics <topic1> [topic2] ..."
  exit 2
fi

# --- Counters ---
PASS=0
FAIL=0
SKIP=0

# --- Check function ---
check() {
  local label="$1" url="$2" key="$3" secret="$4"
  local http_code body
  body=$(curl -s -w "\n%{http_code}" -u "${key}:${secret}" "${url}")
  http_code=$(echo "$body" | tail -1)
  if [ "${http_code}" = "200" ]; then
    echo "  PASS: ${label}"
    ((PASS++))
  else
    echo "  FAIL: ${label} (HTTP ${http_code})"
    echo "        Endpoint: ${url}"
    echo "        Action: Verify the resource was created and credentials have access"
    ((FAIL++))
  fi
}

# --- Run checks per topic ---
echo "============================================"
echo " Post-Apply Validation"
echo "============================================"
echo ""

for topic in "${TOPICS[@]}"; do
  echo "--- ${topic} ---"
  subject="${topic}-value"

  # Check 1: Topic exists on primary cluster
  check "Topic exists" \
    "${KAFKA_REST_ENDPOINT}/kafka/v3/clusters/${KAFKA_CLUSTER_ID}/topics/${topic}" \
    "${KAFKA_API_KEY}" "${KAFKA_API_SECRET}"

  # Check 2: Schema registered in Schema Registry
  check "Schema registered (${subject})" \
    "${SR_REST_ENDPOINT}/subjects/${subject}/versions" \
    "${SR_API_KEY}" "${SR_API_SECRET}"

  # Check 3: RBAC applied (implicit -- read access to schema proves RBAC is working)
  check "Schema readable (RBAC implicit)" \
    "${SR_REST_ENDPOINT}/subjects/${subject}/versions/latest" \
    "${SR_API_KEY}" "${SR_API_SECRET}"

  # Check 4: DR mirror (conditional -- skip if DR cluster not configured)
  if [ -n "${DR_KAFKA_REST_ENDPOINT}" ] && [ -n "${DR_KAFKA_CLUSTER_ID}" ]; then
    check "DR mirror exists" \
      "${DR_KAFKA_REST_ENDPOINT}/kafka/v3/clusters/${DR_KAFKA_CLUSTER_ID}/topics/${topic}" \
      "${DR_KAFKA_API_KEY}" "${DR_KAFKA_API_SECRET}"
  else
    echo "  SKIP: DR mirror (DR cluster not configured)"
    ((SKIP++))
  fi
  echo ""
done

# --- Summary ---
echo "============================================"
echo " Summary: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
echo "============================================"

if [ "${FAIL}" -gt 0 ]; then
  echo ""
  echo "RESULT: FAILED -- ${FAIL} check(s) did not pass."
  echo "Review the FAIL lines above for endpoints and remediation actions."
  exit 1
fi

echo ""
echo "RESULT: ALL CHECKS PASSED"
exit 0

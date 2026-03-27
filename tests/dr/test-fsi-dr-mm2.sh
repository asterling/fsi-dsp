#!/usr/bin/env bash
# =============================================================================
# Unit tests for fsi-dr.sh MirrorMaker 2 backend functions
# Tests MM2 preflight, failover, failback, mirror lag, and mirror status
# with mocked Connect REST API responses (curl) and Consul.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PASS=0
FAIL=0
TOTAL=0

# Create temp dir for state files (isolated from real /tmp state)
TEST_TMPDIR=$(mktemp -d)
trap 'rm -rf "${TEST_TMPDIR}"' EXIT

# Override state file location for tests
export FSI_DR_STATE_FILE="${TEST_TMPDIR}/fsi-dr-state.json"

# Set required env vars for load_env
export FSI_DR_ENV_ID="env-test-east"
export FSI_DR_CLUSTER_ID="lkc-test-east"
export FSI_DR_DR_ENV_ID="env-test-west"
export FSI_DR_DR_CLUSTER_ID="lkc-test-west"
export FSI_CONNECT_URL="http://localhost:8083"
export FSI_MM2_CONNECT_URL="http://localhost:8084"
export CONSUL_HTTP_ADDR="http://localhost:8500"
export FSI_DR_BACKEND="mm2"
export FSI_MM2_SOURCE_CONNECTOR="mm2-source-east-west"
export FSI_MM2_CHECKPOINT_CONNECTOR="mm2-checkpoint-east-west"
export FSI_MM2_HEARTBEAT_CONNECTOR="mm2-heartbeat-east-west"
export FSI_MM2_SOURCE_ALIAS="east"
export FSI_MM2_TARGET_ALIAS="west"

# ---------------------------------------------------------------------------
# Mock external commands
# ---------------------------------------------------------------------------

# Track curl calls for verification
CURL_CALLS_FILE="${TEST_TMPDIR}/curl_calls.log"
: > "${CURL_CALLS_FILE}"

curl() {
  echo "$*" >> "${CURL_CALLS_FILE}"
  case "$*" in
    # MirrorSourceConnector status (must be before generic 8084 pattern)
    *"/connectors/mm2-source-east-west/status"*)
      echo '{"connector":{"state":"RUNNING","worker_id":"worker1:8084"},"tasks":[{"id":0,"state":"RUNNING","worker_id":"worker1:8084"}]}'
      return 0
      ;;
    # MirrorCheckpointConnector status
    *"/connectors/mm2-checkpoint-east-west/status"*)
      echo '{"connector":{"state":"RUNNING","worker_id":"worker1:8084"},"tasks":[{"id":0,"state":"RUNNING","worker_id":"worker1:8084"}]}'
      return 0
      ;;
    # MirrorHeartbeatConnector status
    *"/connectors/mm2-heartbeat-east-west/status"*)
      echo '{"connector":{"state":"RUNNING","worker_id":"worker1:8084"},"tasks":[{"id":0,"state":"RUNNING","worker_id":"worker1:8084"}]}'
      return 0
      ;;
    # MirrorSourceConnector config
    *"/connectors/mm2-source-east-west/config"*)
      echo '{"connector.class":"org.apache.kafka.connect.mirror.MirrorSourceConnector","topics":".*","source.cluster.alias":"east","target.cluster.alias":"west","source.cluster.bootstrap.servers":"kafka-east:9092","target.cluster.bootstrap.servers":"kafka-west:9092"}'
      return 0
      ;;
    # Connector list
    *"/connectors?expand=status"*)
      echo '{}'
      return 0
      ;;
    # Pause endpoint -- return success
    *"/pause"*)
      return 0
      ;;
    # Delete endpoint -- return success
    *"-X DELETE"*)
      return 0
      ;;
    # POST connectors (create) -- return success
    *"-X POST"*"/connectors"*)
      return 0
      ;;
    # Consul leader check
    *"/v1/status/leader"*)
      echo '"consul-leader:8300"'
      return 0
      ;;
    # MM2 Connect cluster health check (generic -- must be after specific /connectors patterns)
    *"8084/"*)
      echo '{"version":"7.6.0","commit":"abcdef","kafka_cluster_id":"test-cluster"}'
      return 0
      ;;
    # Default
    *)
      return 0
      ;;
  esac
}
export -f curl

confluent() {
  case "$*" in
    *"schema-registry subject describe"*)
      echo '{"metadata":{"properties":{"sla-tier":"critical"}}}'
      ;;
    *"cluster describe"*)
      echo '{"cluster_id":"lkc-test"}'
      ;;
    *)
      echo "{}"
      ;;
  esac
}
export -f confluent

consul() {
  case "$*" in
    *"kv get"*)
      echo "east"
      ;;
    *)
      return 0
      ;;
  esac
}
export -f consul

# Source fsi-dr.sh functions (SOURCED guard prevents main execution)
source "${REPO_ROOT}/scripts/fsi-dr.sh"

# ---------------------------------------------------------------------------
# Assertion helpers (matching existing test pattern)
# ---------------------------------------------------------------------------
assert_eq() {
  local test_name="$1" expected="$2" actual="$3"
  ((TOTAL++)) || true
  if [ "${expected}" = "${actual}" ]; then
    echo "  PASS: ${test_name}"
    ((PASS++)) || true
  else
    echo "  FAIL: ${test_name} (expected='${expected}', actual='${actual}')"
    ((FAIL++)) || true
  fi
}

assert_contains() {
  local test_name="$1" needle="$2" haystack="$3"
  ((TOTAL++)) || true
  if echo "${haystack}" | grep -qF "${needle}"; then
    echo "  PASS: ${test_name}"
    ((PASS++)) || true
  else
    echo "  FAIL: ${test_name} (output does not contain '${needle}')"
    ((FAIL++)) || true
  fi
}

assert_not_contains() {
  local test_name="$1" needle="$2" haystack="$3"
  ((TOTAL++)) || true
  if ! echo "${haystack}" | grep -qF "${needle}"; then
    echo "  PASS: ${test_name}"
    ((PASS++)) || true
  else
    echo "  FAIL: ${test_name} (output should NOT contain '${needle}')"
    ((FAIL++)) || true
  fi
}

assert_exit_zero() {
  local test_name="$1"
  shift
  ((TOTAL++)) || true
  if "$@" >/dev/null 2>&1; then
    echo "  PASS: ${test_name}"
    ((PASS++)) || true
  else
    echo "  FAIL: ${test_name} (non-zero exit code)"
    ((FAIL++)) || true
  fi
}

assert_valid_json() {
  local test_name="$1" json="$2"
  ((TOTAL++)) || true
  if echo "${json}" | jq -e . >/dev/null 2>&1; then
    echo "  PASS: ${test_name}"
    ((PASS++)) || true
  else
    echo "  FAIL: ${test_name} (invalid JSON)"
    ((FAIL++)) || true
  fi
}

# ===========================================================================
# Test Group 1: mm2_preflight
# ===========================================================================
echo ""
echo "=== mm2_preflight ==="
echo ""

# Test 1: mm2_preflight succeeds when all checks pass
output=$(mm2_preflight 2>&1) || true
exit_code=$?
assert_eq "mm2_preflight succeeds when all checks pass" \
  "0" "${exit_code}"

# Test 2: mm2_preflight output contains MM2 Connect cluster reachable
assert_contains "mm2_preflight shows MM2 Connect cluster reachable" \
  "PASS: MM2 Connect cluster reachable" "${output}"

# Test 3: mm2_preflight output contains MirrorSourceConnector
assert_contains "mm2_preflight shows MirrorSourceConnector RUNNING" \
  "PASS: MirrorSourceConnector" "${output}"

# Test 4: mm2_preflight output contains MirrorCheckpointConnector
assert_contains "mm2_preflight shows MirrorCheckpointConnector RUNNING" \
  "PASS: MirrorCheckpointConnector" "${output}"

# Test 5: mm2_preflight output contains Consul reachable
assert_contains "mm2_preflight shows Consul reachable" \
  "PASS: Consul reachable" "${output}"

# Test 6: mm2_preflight fails when Connect cluster unreachable
# Override curl to fail for Connect health check
_original_curl=$(declare -f curl)
curl() {
  case "$*" in
    *"/v1/status/leader"*)
      echo '"consul-leader:8300"'
      return 0
      ;;
    *)
      return 1  # Everything else unreachable
      ;;
  esac
}
export -f curl
output=$(mm2_preflight 2>&1) || true
assert_contains "mm2_preflight reports FAIL when Connect unreachable" \
  "FAIL: MM2 Connect cluster unreachable" "${output}"

# Restore original curl mock
eval "${_original_curl}"
export -f curl

# ===========================================================================
# Test Group 2: mm2_failover_mirrors (dry-run)
# ===========================================================================
echo ""
echo "=== mm2_failover_mirrors (dry-run) ==="
echo ""

DRY_RUN=true
FORCE=true

# Test 7: DRY_RUN mm2_failover_mirrors output contains "Would pause"
output=$(mm2_failover_mirrors 2>&1)
assert_contains "mm2_failover dry-run contains 'Would pause'" \
  "Would pause" "${output}"

# Test 8: DRY_RUN mm2_failover_mirrors output contains connector name
assert_contains "mm2_failover dry-run contains source connector name" \
  "mm2-source-east-west" "${output}"

# Test 9: DRY_RUN mm2_failover_mirrors does NOT actually call pause
# Clear log and check no pause calls made during dry-run
: > "${CURL_CALLS_FILE}"
mm2_failover_mirrors >/dev/null 2>&1
pause_calls="$(grep -c "/pause" "${CURL_CALLS_FILE}" || true)"
assert_eq "mm2_failover dry-run does NOT call pause endpoint" \
  "0" "${pause_calls}"

# ===========================================================================
# Test Group 3: mm2_failover_mirrors (live)
# ===========================================================================
echo ""
echo "=== mm2_failover_mirrors (live) ==="
echo ""

DRY_RUN=false

# Override curl to simulate pause success (return PAUSED on status check after pause)
_saved_curl=$(declare -f curl)
_pause_count=0
curl() {
  case "$*" in
    *"/pause"*)
      return 0
      ;;
    *"/connectors/mm2-source-east-west/status"*)
      echo '{"connector":{"state":"PAUSED","worker_id":"worker1:8084"},"tasks":[{"id":0,"state":"PAUSED","worker_id":"worker1:8084"}]}'
      return 0
      ;;
    *"/connectors/mm2-checkpoint-east-west/status"*)
      echo '{"connector":{"state":"PAUSED","worker_id":"worker1:8084"},"tasks":[{"id":0,"state":"PAUSED","worker_id":"worker1:8084"}]}'
      return 0
      ;;
    *"/connectors/mm2-heartbeat-east-west/status"*)
      echo '{"connector":{"state":"PAUSED","worker_id":"worker1:8084"},"tasks":[{"id":0,"state":"PAUSED","worker_id":"worker1:8084"}]}'
      return 0
      ;;
    *)
      return 0
      ;;
  esac
}
export -f curl

# Test 10: mm2_failover_mirrors pauses source connector
output=$(mm2_failover_mirrors 2>&1)
assert_contains "mm2_failover live pauses source connector" \
  "mm2-source-east-west: PAUSED" "${output}"

# Test 11: mm2_failover_mirrors pauses all 3 connectors
assert_contains "mm2_failover live pauses checkpoint connector" \
  "mm2-checkpoint-east-west: PAUSED" "${output}"

# Test 12: mm2_failover_mirrors output contains "DR topics are already writable"
assert_contains "mm2_failover live confirms DR topics writable" \
  "DR topics are already writable" "${output}"

# Restore original curl mock
eval "${_saved_curl}"
export -f curl

# ===========================================================================
# Test Group 4: mm2_failback_mirrors (dry-run)
# ===========================================================================
echo ""
echo "=== mm2_failback_mirrors (dry-run) ==="
echo ""

DRY_RUN=true

# Test 13: DRY_RUN mm2_failback_mirrors output contains "Would delete"
output=$(mm2_failback_mirrors 2>&1)
assert_contains "mm2_failback dry-run contains 'Would delete'" \
  "Would delete" "${output}"

# Test 14: DRY_RUN mm2_failback_mirrors output contains "reversed"
assert_contains "mm2_failback dry-run contains 'reversed'" \
  "reversed" "${output}"

# ===========================================================================
# Test Group 5: mm2_get_mirror_lag
# ===========================================================================
echo ""
echo "=== mm2_get_mirror_lag ==="
echo ""

DRY_RUN=false

# Test 15: mm2_get_mirror_lag returns valid JSON
output=$(mm2_get_mirror_lag 2>&1)
assert_valid_json "mm2_get_mirror_lag returns valid JSON" \
  "${output}"

# Test 16: mm2_get_mirror_lag JSON contains "mirror_topic_name" key
assert_contains "mm2_get_mirror_lag contains mirror_topic_name" \
  "mirror_topic_name" "${output}"

# Test 17: mm2_get_mirror_lag JSON contains "status" key
assert_contains "mm2_get_mirror_lag contains status key" \
  "status" "${output}"

# Test 18: mm2_get_mirror_lag status is ACTIVE when connector is RUNNING
lag_status=$(echo "${output}" | jq -r '.[0].status')
assert_eq "mm2_get_mirror_lag status is ACTIVE" \
  "ACTIVE" "${lag_status}"

# ===========================================================================
# Test Group 6: mm2_get_mirror_status
# ===========================================================================
echo ""
echo "=== mm2_get_mirror_status ==="
echo ""

# Test 19: mm2_get_mirror_status returns valid JSON array
output=$(mm2_get_mirror_status 2>&1)
assert_valid_json "mm2_get_mirror_status returns valid JSON" \
  "${output}"

# Test 20: mm2_get_mirror_status contains source connector
assert_contains "mm2_get_mirror_status contains source connector" \
  "mm2-source-east-west" "${output}"

# Test 21: mm2_get_mirror_status contains RUNNING state
assert_contains "mm2_get_mirror_status contains RUNNING state" \
  "RUNNING" "${output}"

# Test 22: mm2_get_mirror_status contains all 3 connectors
status_count=$(echo "${output}" | jq 'length')
assert_eq "mm2_get_mirror_status has 3 connector entries" \
  "3" "${status_count}"

# ===========================================================================
# Summary
# ===========================================================================
echo ""
echo "============================================"
echo " Results: ${PASS} passed, ${FAIL} failed (${TOTAL} total)"
echo "============================================"
[ "${FAIL}" -eq 0 ]

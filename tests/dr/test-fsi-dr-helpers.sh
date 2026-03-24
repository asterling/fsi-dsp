#!/usr/bin/env bash
# =============================================================================
# Unit tests for fsi-dr.sh helper functions
# Tests pure functions: SLA tier thresholds, state file ops, backend dispatch,
# utility functions. No external dependencies (Confluent CLI, Consul, Connect).
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

# Source fsi-dr.sh functions (SOURCED guard prevents main execution)
source "${REPO_ROOT}/scripts/fsi-dr.sh"

# ---------------------------------------------------------------------------
# Assertion helpers
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

assert_exit_code() {
  local test_name="$1" expected_code="$2"
  shift 2
  local actual_code=0
  "$@" >/dev/null 2>&1 || actual_code=$?
  ((TOTAL++)) || true
  if [ "${expected_code}" = "${actual_code}" ]; then
    echo "  PASS: ${test_name}"
    ((PASS++)) || true
  else
    echo "  FAIL: ${test_name} (expected exit ${expected_code}, got ${actual_code})"
    ((FAIL++)) || true
  fi
}

assert_contains() {
  local test_name="$1" expected="$2" actual="$3"
  ((TOTAL++)) || true
  if echo "${actual}" | grep -q "${expected}"; then
    echo "  PASS: ${test_name}"
    ((PASS++)) || true
  else
    echo "  FAIL: ${test_name} (expected to contain '${expected}')"
    ((FAIL++)) || true
  fi
}

assert_file_exists() {
  local test_name="$1" filepath="$2"
  ((TOTAL++)) || true
  if [ -f "${filepath}" ]; then
    echo "  PASS: ${test_name}"
    ((PASS++)) || true
  else
    echo "  FAIL: ${test_name} (file does not exist: ${filepath})"
    ((FAIL++)) || true
  fi
}

assert_file_not_exists() {
  local test_name="$1" filepath="$2"
  ((TOTAL++)) || true
  if [ ! -f "${filepath}" ]; then
    echo "  PASS: ${test_name}"
    ((PASS++)) || true
  else
    echo "  FAIL: ${test_name} (file still exists: ${filepath})"
    ((FAIL++)) || true
  fi
}

# ===========================================================================
# Test Section: SLA Tier Threshold Assessment
# ===========================================================================
echo ""
echo "=== SLA Tier Threshold Assessment ==="
echo ""

# Critical tier: warn=30, alert=60
assert_eq "assess_lag 10 critical -> OK" \
  "OK" "$(assess_lag 10 critical)"

assert_eq "assess_lag 30 critical -> WARN (boundary)" \
  "WARN" "$(assess_lag 30 critical)"

assert_eq "assess_lag 50 critical -> WARN" \
  "WARN" "$(assess_lag 50 critical)"

assert_eq "assess_lag 60 critical -> ALERT (boundary)" \
  "ALERT" "$(assess_lag 60 critical)"

assert_eq "assess_lag 100 critical -> ALERT" \
  "ALERT" "$(assess_lag 100 critical)"

# Standard tier: warn=300, alert=900
assert_eq "assess_lag 299 standard -> OK" \
  "OK" "$(assess_lag 299 standard)"

assert_eq "assess_lag 300 standard -> WARN (boundary)" \
  "WARN" "$(assess_lag 300 standard)"

assert_eq "assess_lag 899 standard -> WARN" \
  "WARN" "$(assess_lag 899 standard)"

assert_eq "assess_lag 900 standard -> ALERT (boundary)" \
  "ALERT" "$(assess_lag 900 standard)"

# Compliance tier: warn=10, alert=30
assert_eq "assess_lag 9 compliance -> OK" \
  "OK" "$(assess_lag 9 compliance)"

assert_eq "assess_lag 10 compliance -> WARN (boundary)" \
  "WARN" "$(assess_lag 10 compliance)"

assert_eq "assess_lag 29 compliance -> WARN" \
  "WARN" "$(assess_lag 29 compliance)"

assert_eq "assess_lag 30 compliance -> ALERT (boundary)" \
  "ALERT" "$(assess_lag 30 compliance)"

# Best-effort tier: warn=3600, alert=14400
assert_eq "assess_lag 3599 best-effort -> WARN" \
  "WARN" "$(assess_lag 3599 best-effort)"

assert_eq "assess_lag 14400 best-effort -> ALERT (boundary)" \
  "ALERT" "$(assess_lag 14400 best-effort)"

# ===========================================================================
# Test Section: Threshold Lookup Functions
# ===========================================================================
echo ""
echo "=== Threshold Lookup Functions ==="
echo ""

assert_eq "get_tier_threshold critical -> 60" \
  "60" "$(get_tier_threshold critical)"

assert_eq "get_tier_threshold standard -> 900" \
  "900" "$(get_tier_threshold standard)"

assert_eq "get_tier_threshold best-effort -> 14400" \
  "14400" "$(get_tier_threshold best-effort)"

assert_eq "get_tier_threshold compliance -> 30" \
  "30" "$(get_tier_threshold compliance)"

assert_eq "get_tier_warn_threshold critical -> 30" \
  "30" "$(get_tier_warn_threshold critical)"

assert_eq "get_tier_warn_threshold compliance -> 10" \
  "10" "$(get_tier_warn_threshold compliance)"

# ===========================================================================
# Test Section: State File Management
# ===========================================================================
echo ""
echo "=== State File Management ==="
echo ""

# Clean up any leftover state
rm -f "${FSI_DR_STATE_FILE}"

# Test init_state
init_state "failover"
assert_file_exists "init_state creates state file" "${FSI_DR_STATE_FILE}"

local_op=$(jq -r '.operation' "${FSI_DR_STATE_FILE}")
assert_eq "init_state sets operation to failover" "failover" "${local_op}"

local_status=$(jq -r '.status' "${FSI_DR_STATE_FILE}")
assert_eq "init_state sets status to in-progress" "in-progress" "${local_status}"

local_backend=$(jq -r '.backend' "${FSI_DR_STATE_FILE}")
assert_eq "init_state sets backend to cluster-linking" "cluster-linking" "${local_backend}"

local_steps_count=$(jq '.steps_completed | length' "${FSI_DR_STATE_FILE}")
assert_eq "init_state has empty steps_completed" "0" "${local_steps_count}"

local_connectors_count=$(jq '.connectors_snapshot | length' "${FSI_DR_STATE_FILE}")
assert_eq "init_state has empty connectors_snapshot" "0" "${local_connectors_count}"

local_topics_count=$(jq '.topics_promoted | length' "${FSI_DR_STATE_FILE}")
assert_eq "init_state has empty topics_promoted" "0" "${local_topics_count}"

local_current_step=$(jq '.current_step' "${FSI_DR_STATE_FILE}")
assert_eq "init_state sets current_step to 0" "0" "${local_current_step}"

# Test record_step
record_step 1 "pause_connectors"
local_step_count=$(jq '.steps_completed | length' "${FSI_DR_STATE_FILE}")
assert_eq "record_step adds to steps_completed (count=1)" "1" "${local_step_count}"

local_current=$(jq '.current_step' "${FSI_DR_STATE_FILE}")
assert_eq "record_step updates current_step to 1" "1" "${local_current}"

local_step_name=$(jq -r '.steps_completed[0].name' "${FSI_DR_STATE_FILE}")
assert_eq "record_step stores step name" "pause_connectors" "${local_step_name}"

# Test second record_step
record_step 2 "promote_mirrors"
local_step_count2=$(jq '.steps_completed | length' "${FSI_DR_STATE_FILE}")
assert_eq "record_step 2 results in 2 entries" "2" "${local_step_count2}"

local_current2=$(jq '.current_step' "${FSI_DR_STATE_FILE}")
assert_eq "record_step 2 updates current_step to 2" "2" "${local_current2}"

# Test read_state returns content
local_state_json=$(read_state)
assert_contains "read_state returns operation field" '"operation"' "${local_state_json}"

# Test cleanup_state
cleanup_state
assert_file_not_exists "cleanup_state removes state file" "${FSI_DR_STATE_FILE}"

# Test read_state on missing file returns empty object
local_empty_state=$(read_state)
assert_eq "read_state on missing file returns {}" "{}" "${local_empty_state}"

# ===========================================================================
# Test Section: Backend Dispatch
# ===========================================================================
echo ""
echo "=== Backend Dispatch ==="
echo ""

# cluster-linking backend should work (already initialized)
assert_exit_code "FSI_DR_BACKEND=cluster-linking init_backend succeeds" \
  0 init_backend

# mm2 backend should fail
assert_exit_code "FSI_DR_BACKEND=mm2 init_backend exits with code 1" \
  1 bash -c 'FSI_DR_BACKEND=mm2; source "'"${REPO_ROOT}/scripts/fsi-dr.sh"'"'

# unknown backend should fail
assert_exit_code "FSI_DR_BACKEND=unknown init_backend exits with code 1" \
  1 bash -c 'FSI_DR_BACKEND=unknown; source "'"${REPO_ROOT}/scripts/fsi-dr.sh"'"'

# ===========================================================================
# Test Section: Connector Snapshot Parsing
# ===========================================================================
echo ""
echo "=== Connector Snapshot Parsing ==="
echo ""

# Initialize state for connector tests
init_state "failover"

# Test record_connectors with mock data
MOCK_CONNECTORS='[{"name":"jdbc-source","state":"RUNNING","tasks":[{"id":0,"state":"RUNNING"}]},{"name":"jdbc-sink","state":"PAUSED","tasks":[{"id":0,"state":"PAUSED"}]},{"name":"s3-sink","state":"FAILED","tasks":[{"id":0,"state":"FAILED"}]}]'
record_connectors "${MOCK_CONNECTORS}"

local_conn_count=$(jq '.connectors_snapshot | length' "${FSI_DR_STATE_FILE}")
assert_eq "snapshot_connectors stores 3 connectors" "3" "${local_conn_count}"

local_running=$(jq -r '.connectors_snapshot[] | select(.state == "RUNNING") | .name' "${FSI_DR_STATE_FILE}")
assert_eq "snapshot tracks RUNNING connector" "jdbc-source" "${local_running}"

local_paused=$(jq -r '.connectors_snapshot[] | select(.state == "PAUSED") | .name' "${FSI_DR_STATE_FILE}")
assert_eq "snapshot tracks PAUSED connector" "jdbc-sink" "${local_paused}"

local_failed=$(jq -r '.connectors_snapshot[] | select(.state == "FAILED") | .name' "${FSI_DR_STATE_FILE}")
assert_eq "snapshot tracks FAILED connector" "s3-sink" "${local_failed}"

# Test get_running_connectors
local_running_list=$(get_running_connectors)
assert_eq "get_running_connectors returns only RUNNING" "jdbc-source" "${local_running_list}"

# Clean up
cleanup_state

# ===========================================================================
# Test Section: Utility Functions
# ===========================================================================
echo ""
echo "=== Utility Functions ==="
echo ""

assert_eq "format_duration 45 -> 45s" \
  "45s" "$(format_duration 45)"

assert_eq "format_duration 125 -> 2m 5s" \
  "2m 5s" "$(format_duration 125)"

assert_eq "format_duration 3661 -> 1h 1m" \
  "1h 1m" "$(format_duration 3661)"

assert_eq "format_duration 0 -> 0s" \
  "0s" "$(format_duration 0)"

assert_eq "format_duration 60 -> 1m 0s" \
  "1m 0s" "$(format_duration 60)"

assert_eq "format_duration 3600 -> 1h 0m" \
  "1h 0m" "$(format_duration 3600)"

# ===========================================================================
# Test Section: Record Topics
# ===========================================================================
echo ""
echo "=== Record Topics ==="
echo ""

init_state "failover"
record_topics "topic-a topic-b topic-c"

local_topic_count=$(jq '.topics_promoted | length' "${FSI_DR_STATE_FILE}")
assert_eq "record_topics stores 3 topics" "3" "${local_topic_count}"

local_first_topic=$(jq -r '.topics_promoted[0]' "${FSI_DR_STATE_FILE}")
assert_eq "record_topics first is topic-a" "topic-a" "${local_first_topic}"

cleanup_state

# ===========================================================================
# Summary
# ===========================================================================
echo ""
echo "============================================"
echo " Results: ${PASS} passed, ${FAIL} failed (${TOTAL} total)"
echo "============================================"
[ "${FAIL}" -eq 0 ]

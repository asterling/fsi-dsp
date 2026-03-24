#!/usr/bin/env bash
# =============================================================================
# FSI DR CLI -- Unified disaster recovery orchestration
# Usage: fsi-dr.sh failover|failback|status [--dry-run] [--force]
#
# Replaces manual 6-step DR process with single-command orchestration.
# Backend-pluggable: cluster-linking (Phase 4), mm2 (Phase 8).
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# SOURCED guard -- allows tests to source functions without executing main
# ---------------------------------------------------------------------------
SOURCED=false
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  SOURCED=true
fi

# ---------------------------------------------------------------------------
# SLA tier threshold constants (ADR-008: DR Tier Classification)
# Implemented as functions for Bash 3.2 compatibility (macOS default).
# The plan specifies associative arrays TIER_WARN_THRESHOLD_SEC and
# TIER_ALERT_THRESHOLD_SEC -- these functions provide the same interface.
# ---------------------------------------------------------------------------

# TIER_WARN_THRESHOLD_SEC -- Warn thresholds per SLA tier (seconds)
#   critical=30, standard=300 (5m), best-effort=3600 (1h), compliance=10
_tier_warn_threshold() {
  case "$1" in
    critical)    echo 30 ;;
    standard)    echo 300 ;;
    best-effort) echo 3600 ;;
    compliance)  echo 10 ;;
    *)           echo 300 ;;  # default to standard
  esac
}

# TIER_ALERT_THRESHOLD_SEC -- Alert thresholds per SLA tier (seconds)
#   critical=60, standard=900 (15m), best-effort=14400 (4h), compliance=30
_tier_alert_threshold() {
  case "$1" in
    critical)    echo 60 ;;
    standard)    echo 900 ;;
    best-effort) echo 14400 ;;
    compliance)  echo 30 ;;
    *)           echo 900 ;;  # default to standard
  esac
}

# ---------------------------------------------------------------------------
# Configuration defaults
# ---------------------------------------------------------------------------
FSI_DR_BACKEND="${FSI_DR_BACKEND:-cluster-linking}"
FSI_DR_STATE_FILE="${FSI_DR_STATE_FILE:-/tmp/fsi-dr-state.json}"

# ---------------------------------------------------------------------------
# Color output helpers
# ---------------------------------------------------------------------------
if command -v tput &>/dev/null && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
  RED='\033[0;31m'
  YELLOW='\033[0;33m'
  GREEN='\033[0;32m'
  NC='\033[0m'
else
  RED=''
  YELLOW=''
  GREEN=''
  NC=''
fi

color_status() {
  local status="$1"
  case "${status}" in
    OK)    printf "${GREEN}%s${NC}" "${status}" ;;
    WARN)  printf "${YELLOW}%s${NC}" "${status}" ;;
    ALERT) printf "${RED}%s${NC}" "${status}" ;;
    *)     printf "%s" "${status}" ;;
  esac
}

# ---------------------------------------------------------------------------
# Pure functions (testable without external deps)
# ---------------------------------------------------------------------------

# assess_lag -- Evaluate mirror lag against SLA tier thresholds
# Args: lag_sec tier
# Returns: "OK", "WARN", or "ALERT"
assess_lag() {
  local lag_sec="$1"
  local tier="$2"
  local warn
  local alert
  warn=$(_tier_warn_threshold "${tier}")
  alert=$(_tier_alert_threshold "${tier}")

  if [ "${lag_sec}" -ge "${alert}" ]; then
    echo "ALERT"
  elif [ "${lag_sec}" -ge "${warn}" ]; then
    echo "WARN"
  else
    echo "OK"
  fi
}

# get_tier_threshold -- Returns the alert threshold in seconds for a tier
get_tier_threshold() {
  local tier="$1"
  _tier_alert_threshold "${tier}"
}

# get_tier_warn_threshold -- Returns the warn threshold in seconds for a tier
get_tier_warn_threshold() {
  local tier="$1"
  _tier_warn_threshold "${tier}"
}

# format_duration -- Converts seconds to human-readable string
# 45 -> "45s", 125 -> "2m 5s", 3661 -> "1h 1m"
format_duration() {
  local total_sec="$1"
  local hours=$((total_sec / 3600))
  local mins=$(( (total_sec % 3600) / 60 ))
  local secs=$((total_sec % 60))

  if [ "${hours}" -gt 0 ]; then
    echo "${hours}h ${mins}m"
  elif [ "${mins}" -gt 0 ]; then
    echo "${mins}m ${secs}s"
  else
    echo "${secs}s"
  fi
}

# ---------------------------------------------------------------------------
# State file functions (atomic writes via mktemp + mv per D-07)
# ---------------------------------------------------------------------------

# init_state -- Create a new state file for a DR operation
# Args: operation ("failover" or "failback")
init_state() {
  local operation="$1"
  local tmp
  tmp=$(mktemp "${FSI_DR_STATE_FILE}.XXXXXX")
  jq -n \
    --arg op "${operation}" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg backend "${FSI_DR_BACKEND}" \
    '{
      operation: $op,
      started: $ts,
      backend: $backend,
      steps_completed: [],
      connectors_snapshot: [],
      topics_promoted: [],
      current_step: 0,
      status: "in-progress"
    }' > "${tmp}" && mv "${tmp}" "${FSI_DR_STATE_FILE}"
}

# record_step -- Record completion of a failover/failback step
# Args: step_num step_name
record_step() {
  local step_num="$1"
  local step_name="$2"
  local tmp
  tmp=$(mktemp "${FSI_DR_STATE_FILE}.XXXXXX")
  jq \
    --arg num "${step_num}" \
    --arg name "${step_name}" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '.steps_completed += [{step: ($num | tonumber), name: $name, completed: $ts}]
     | .current_step = ($num | tonumber)' \
    "${FSI_DR_STATE_FILE}" > "${tmp}" && mv "${tmp}" "${FSI_DR_STATE_FILE}"
}

# record_connectors -- Store connector state snapshot in state file
# Args: json_array (connector states JSON)
record_connectors() {
  local json_array="$1"
  local tmp
  tmp=$(mktemp "${FSI_DR_STATE_FILE}.XXXXXX")
  jq \
    --argjson connectors "${json_array}" \
    '.connectors_snapshot = $connectors' \
    "${FSI_DR_STATE_FILE}" > "${tmp}" && mv "${tmp}" "${FSI_DR_STATE_FILE}"
}

# record_topics -- Store promoted topic names in state file
# Args: space-separated topic names
record_topics() {
  local topics_str="$1"
  local topics_json
  # Convert space-separated string to JSON array
  topics_json=$(echo "${topics_str}" | tr ' ' '\n' | jq -R . | jq -s .)
  local tmp
  tmp=$(mktemp "${FSI_DR_STATE_FILE}.XXXXXX")
  jq \
    --argjson topics "${topics_json}" \
    '.topics_promoted = $topics' \
    "${FSI_DR_STATE_FILE}" > "${tmp}" && mv "${tmp}" "${FSI_DR_STATE_FILE}"
}

# cleanup_state -- Mark operation complete and remove state file
cleanup_state() {
  if [ -f "${FSI_DR_STATE_FILE}" ]; then
    local tmp
    tmp=$(mktemp "${FSI_DR_STATE_FILE}.XXXXXX")
    jq '.status = "completed"' "${FSI_DR_STATE_FILE}" > "${tmp}" && mv "${tmp}" "${FSI_DR_STATE_FILE}"
    rm -f "${FSI_DR_STATE_FILE}"
  fi
}

# read_state -- Read state file contents or return empty object
read_state() {
  if [ -f "${FSI_DR_STATE_FILE}" ]; then
    cat "${FSI_DR_STATE_FILE}"
  else
    echo "{}"
  fi
}

# ---------------------------------------------------------------------------
# Environment loading -- only called by commands, not at source time
# ---------------------------------------------------------------------------
load_env() {
  FSI_DR_ENV_ID="${FSI_DR_ENV_ID:?Set FSI_DR_ENV_ID}"
  FSI_DR_CLUSTER_ID="${FSI_DR_CLUSTER_ID:?Set FSI_DR_CLUSTER_ID}"
  FSI_DR_DR_ENV_ID="${FSI_DR_DR_ENV_ID:?Set FSI_DR_DR_ENV_ID}"
  FSI_DR_DR_CLUSTER_ID="${FSI_DR_DR_CLUSTER_ID:?Set FSI_DR_DR_CLUSTER_ID}"
  FSI_CONNECT_URL="${FSI_CONNECT_URL:-http://localhost:8083}"
  CONSUL_HTTP_ADDR="${CONSUL_HTTP_ADDR:-http://localhost:8500}"
  FSI_CLUSTER_LINK_NAME="${FSI_CLUSTER_LINK_NAME:-cluster_link_bidir_east_west}"
}

# ---------------------------------------------------------------------------
# Connect state tracking (D-08, DR-12)
# ---------------------------------------------------------------------------

# snapshot_connectors -- Capture current state of all connectors
# Returns JSON array: [{name, state, tasks: [{id, state}]}]
snapshot_connectors() {
  local raw_json
  raw_json=$(curl -s "${FSI_CONNECT_URL}/connectors?expand=status")
  local connectors_json
  connectors_json=$(echo "${raw_json}" | jq '[
    to_entries[] | {
      name: .key,
      state: .value.status.connector.state,
      tasks: [.value.status.tasks[]? | {id: .id, state: .state}]
    }
  ]')
  # Store in state file
  record_connectors "${connectors_json}"
  echo "${connectors_json}"
}

# get_running_connectors -- Return names of connectors that were RUNNING
get_running_connectors() {
  local state
  state=$(read_state)
  echo "${state}" | jq -r '.connectors_snapshot[]? | select(.state == "RUNNING") | .name'
}

# pause_connector -- Pause a single connector with polling verification
# Args: connector_name
pause_connector() {
  local name="$1"
  curl -s -X PUT "${FSI_CONNECT_URL}/connectors/${name}/pause" >/dev/null

  # Poll for PAUSED state (up to 30 iterations, 2s sleep)
  local i state
  for i in $(seq 1 30); do
    state=$(curl -s "${FSI_CONNECT_URL}/connectors/${name}/status" \
      | jq -r '.connector.state')
    if [ "${state}" = "PAUSED" ]; then
      echo "  ${name}: PAUSED"
      return 0
    fi
    sleep 2
  done
  echo "  WARNING: ${name} did not reach PAUSED state within timeout"
  return 1
}

# resume_connector -- Resume a single connector with polling verification
# Args: connector_name
resume_connector() {
  local name="$1"
  curl -s -X PUT "${FSI_CONNECT_URL}/connectors/${name}/resume" >/dev/null

  # Poll for RUNNING state (up to 30 iterations, 2s sleep)
  local i state
  for i in $(seq 1 30); do
    state=$(curl -s "${FSI_CONNECT_URL}/connectors/${name}/status" \
      | jq -r '.connector.state')
    if [ "${state}" = "RUNNING" ]; then
      echo "  ${name}: RUNNING"
      return 0
    fi
    sleep 2
  done
  echo "  WARNING: ${name} did not reach RUNNING state within timeout"
  return 1
}

# ---------------------------------------------------------------------------
# Pre-flight checks (D-11)
# ---------------------------------------------------------------------------

# preflight_check -- Run 5 checks before failover/failback
# Returns non-zero if any critical check fails
preflight_check() {
  local pass=0 warn=0 fail=0

  echo "=== Pre-flight Checks ==="
  echo ""

  # Check 1: Production cluster reachable
  if confluent kafka cluster describe "${FSI_DR_CLUSTER_ID}" \
    --environment "${FSI_DR_ENV_ID}" -o json 2>/dev/null | jq -e . >/dev/null 2>&1; then
    echo "  PASS: Production cluster reachable"
    ((pass++))
  else
    # Production unreachable is WARN (expected during DR event)
    echo "  WARN: Production cluster unreachable (expected during DR)"
    ((warn++))
  fi

  # Check 2: DR cluster reachable
  if confluent kafka cluster describe "${FSI_DR_DR_CLUSTER_ID}" \
    --environment "${FSI_DR_DR_ENV_ID}" -o json 2>/dev/null | jq -e . >/dev/null 2>&1; then
    echo "  PASS: DR cluster reachable"
    ((pass++))
  else
    echo "  FAIL: DR cluster unreachable"
    ((fail++))
  fi

  # Check 3: Active mirrors on DR cluster
  local mirror_count
  mirror_count=$(confluent kafka mirror list \
    --link "${FSI_CLUSTER_LINK_NAME}" \
    --cluster "${FSI_DR_DR_CLUSTER_ID}" \
    --environment "${FSI_DR_DR_ENV_ID}" \
    -o json 2>/dev/null | jq 'length' 2>/dev/null || echo "0")
  if [ "${mirror_count}" -gt 0 ]; then
    echo "  PASS: ${mirror_count} active mirrors found"
    ((pass++))
  else
    echo "  FAIL: No active mirrors on DR cluster"
    ((fail++))
  fi

  # Check 4: Connect API reachable
  if curl -sf "${FSI_CONNECT_URL}/" >/dev/null 2>&1; then
    echo "  PASS: Connect API reachable"
    ((pass++))
  else
    echo "  FAIL: Connect API unreachable at ${FSI_CONNECT_URL}"
    ((fail++))
  fi

  # Check 5: Consul reachable
  if curl -sf "${CONSUL_HTTP_ADDR}/v1/status/leader" >/dev/null 2>&1; then
    echo "  PASS: Consul reachable"
    ((pass++))
  else
    echo "  FAIL: Consul unreachable at ${CONSUL_HTTP_ADDR}"
    ((fail++))
  fi

  echo ""
  echo "Pre-flight: ${pass} passed, ${warn} warnings, ${fail} failed"
  [ "${fail}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Mirror lag functions
# ---------------------------------------------------------------------------

# get_mirror_lag_json -- Fetch raw mirror lag data from Confluent CLI
get_mirror_lag_json() {
  confluent kafka mirror list \
    --link "${FSI_CLUSTER_LINK_NAME}" \
    --cluster "${FSI_DR_DR_CLUSTER_ID}" \
    --environment "${FSI_DR_DR_ENV_ID}" \
    -o json 2>/dev/null || echo "[]"
}

# get_topic_sla_tier -- Look up SLA tier for a topic
# Tries schema subject metadata first, falls back to "standard"
# Args: topic_name
get_topic_sla_tier() {
  local topic="$1"
  local tier

  # Try topic config first
  tier=$(confluent kafka topic describe "${topic}" \
    --cluster "${FSI_DR_CLUSTER_ID}" \
    --environment "${FSI_DR_ENV_ID}" \
    -o json 2>/dev/null \
    | jq -r '.configs[]? | select(.name == "confluent.value.schema.validation") // empty' 2>/dev/null || true)

  # Fall back to schema subject metadata (where sla-tier is actually stored)
  if [ -z "${tier}" ] || [ "${tier}" = "null" ]; then
    tier=$(confluent schema-registry subject describe "${topic}-value" \
      -o json 2>/dev/null \
      | jq -r '.metadata.properties["sla-tier"] // "standard"' 2>/dev/null || echo "standard")
  fi

  # Default to "standard" if all lookups fail
  if [ -z "${tier}" ] || [ "${tier}" = "null" ]; then
    tier="standard"
  fi

  echo "${tier}"
}

# ---------------------------------------------------------------------------
# Cluster Linking backend functions (Phase 4)
# ---------------------------------------------------------------------------

# cl_preflight -- Cluster Linking specific pre-flight checks
cl_preflight() {
  preflight_check
}

# cl_failover_mirrors -- Promote mirror topics (stub for Plan 02)
cl_failover_mirrors() {
  echo "Not yet implemented -- see Plan 02"
  return 1
}

# cl_failback_mirrors -- Restore mirrors for failback (stub for Plan 03)
cl_failback_mirrors() {
  echo "Not yet implemented -- see Plan 03"
  return 1
}

# cl_get_mirror_lag -- Get mirror lag data via Cluster Linking
cl_get_mirror_lag() {
  get_mirror_lag_json
}

# cl_get_mirror_status -- Get per-topic mirror status
cl_get_mirror_status() {
  confluent kafka mirror list \
    --link "${FSI_CLUSTER_LINK_NAME}" \
    --cluster "${FSI_DR_DR_CLUSTER_ID}" \
    --environment "${FSI_DR_DR_ENV_ID}" \
    -o json 2>/dev/null || echo "[]"
}

# ---------------------------------------------------------------------------
# Backend dispatch (D-03)
# ---------------------------------------------------------------------------
init_backend() {
  case "${FSI_DR_BACKEND}" in
    cluster-linking)
      backend_preflight()        { cl_preflight "$@"; }
      backend_failover_mirrors() { cl_failover_mirrors "$@"; }
      backend_failback_mirrors() { cl_failback_mirrors "$@"; }
      backend_get_mirror_lag()   { cl_get_mirror_lag "$@"; }
      backend_get_mirror_status(){ cl_get_mirror_status "$@"; }
      ;;
    mm2)
      echo "ERROR: MirrorMaker 2 backend not yet implemented (Phase 8)"
      return 1
      ;;
    *)
      echo "ERROR: Unknown backend: ${FSI_DR_BACKEND}. Supported: cluster-linking"
      return 1
      ;;
  esac
}

# Initialize backend at source time (needed for tests and commands)
init_backend

# ---------------------------------------------------------------------------
# Status command (D-02, D-14)
# ---------------------------------------------------------------------------
cmd_status() {
  echo "=== FSI DR Status ==="
  echo ""

  # Check for in-progress operation
  local state
  state=$(read_state)
  if [ "${state}" != "{}" ]; then
    local operation started current_step steps_count status
    operation=$(echo "${state}" | jq -r '.operation // "unknown"')
    started=$(echo "${state}" | jq -r '.started // "unknown"')
    current_step=$(echo "${state}" | jq -r '.current_step // 0')
    steps_count=$(echo "${state}" | jq '.steps_completed | length')
    status=$(echo "${state}" | jq -r '.status // "unknown"')

    if [ "${status}" = "in-progress" ]; then
      echo "IN-PROGRESS OPERATION:"
      echo "  Operation:  ${operation}"
      echo "  Started:    ${started}"
      echo "  Step:       ${current_step}"
      echo "  Completed:  ${steps_count} steps"
      echo ""

      # Show completed steps
      if [ "${steps_count}" -gt 0 ]; then
        echo "  Steps completed:"
        echo "${state}" | jq -r '.steps_completed[] | "    \(.step). \(.name) (\(.completed))"'
        echo ""
      fi
    fi
  fi

  # Fetch mirror lag data
  echo "Mirror Lag Status:"
  echo ""

  local mirror_json
  mirror_json=$(backend_get_mirror_lag 2>/dev/null || echo "[]")

  if [ "${mirror_json}" = "[]" ] || [ -z "${mirror_json}" ]; then
    echo "  WARNING: Unable to reach cluster -- lag data may be stale"
    echo "  No mirror topic data available."
    return 0
  fi

  # Build table
  local ok_count=0 warn_count=0 alert_count=0
  local table_header
  table_header=$(printf "%-50s %-12s %-10s %-12s %s" "TOPIC" "SLA TIER" "LAG" "THRESHOLD" "STATUS")
  echo "  ${table_header}"
  echo "  $(printf '%0.s-' {1..90})"

  local topics
  topics=$(echo "${mirror_json}" | jq -r '.[].mirror_topic_name // empty' 2>/dev/null || true)

  for topic in ${topics}; do
    local lag_ms lag_sec tier threshold status_text
    lag_ms=$(echo "${mirror_json}" | jq -r ".[] | select(.mirror_topic_name == \"${topic}\") | .partition_mirror_lags[0].lag // 0" 2>/dev/null || echo "0")
    lag_sec=$((lag_ms / 1000))
    tier=$(get_topic_sla_tier "${topic}" 2>/dev/null || echo "standard")
    threshold=$(get_tier_threshold "${tier}")
    status_text=$(assess_lag "${lag_sec}" "${tier}")

    case "${status_text}" in
      OK)    ((ok_count++)) ;;
      WARN)  ((warn_count++)) ;;
      ALERT) ((alert_count++)) ;;
    esac

    printf "  %-50s %-12s %-10s %-12s %s\n" \
      "${topic}" "${tier}" "${lag_sec}s" "${threshold}s" "${status_text}"
  done

  echo ""
  echo "Summary: ${ok_count} topics OK, ${warn_count} WARN, ${alert_count} ALERT"
}

# ---------------------------------------------------------------------------
# Failover/Failback stubs (Plan 02 and 03 will implement these)
# ---------------------------------------------------------------------------
cmd_failover() {
  echo "Not yet implemented -- see Plan 02"
}

cmd_failback() {
  echo "Not yet implemented -- see Plan 03"
}

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
  cat <<'USAGE'
Usage: fsi-dr.sh <command> [flags]

Commands:
  failover   Orchestrate DR failover (6-step sequence)
  failback   Orchestrate DR failback to primary
  status     Show mirror lag and DR operation status

Flags:
  --dry-run  Preview operations without executing
  --force    Skip confirmation prompts (for CI/automation)

Environment Variables:
  FSI_DR_BACKEND           DR backend (default: cluster-linking)
  FSI_DR_ENV_ID            Production environment ID (required)
  FSI_DR_CLUSTER_ID        Production cluster ID (required)
  FSI_DR_DR_ENV_ID         DR environment ID (required)
  FSI_DR_DR_CLUSTER_ID     DR cluster ID (required)
  FSI_CONNECT_URL          Connect REST endpoint (default: http://localhost:8083)
  CONSUL_HTTP_ADDR         Consul address (default: http://localhost:8500)
  FSI_CLUSTER_LINK_NAME    Cluster link name (default: cluster_link_bidir_east_west)
  FSI_DR_STATE_FILE        State file path (default: /tmp/fsi-dr-state.json)
USAGE
}

# ---------------------------------------------------------------------------
# CLI argument parsing
# ---------------------------------------------------------------------------
main() {
  local cmd="${1:-help}"
  shift || true

  # Parse global flags
  DRY_RUN=false
  FORCE=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) DRY_RUN=true; shift ;;
      --force)   FORCE=true; shift ;;
      *)         echo "Unknown flag: $1"; usage; exit 1 ;;
    esac
  done

  case "${cmd}" in
    failover) load_env; cmd_failover ;;
    failback) load_env; cmd_failback ;;
    status)   load_env; cmd_status ;;
    help|-h|--help) usage ;;
    *) echo "Unknown command: ${cmd}"; usage; exit 1 ;;
  esac
}

# Only run main if not being sourced by tests
if [ "${SOURCED}" = false ]; then
  main "$@"
fi

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

# MM2 backend environment variables
# FSI_MM2_CONNECT_URL -- Connect REST API for MM2 dedicated cluster (default: FSI_CONNECT_URL)
# FSI_MM2_SOURCE_CONNECTOR -- MirrorSourceConnector name (default: mm2-source-east-west)
# FSI_MM2_CHECKPOINT_CONNECTOR -- MirrorCheckpointConnector name (default: mm2-checkpoint-east-west)
# FSI_MM2_HEARTBEAT_CONNECTOR -- MirrorHeartbeatConnector name (default: mm2-heartbeat-east-west)
# FSI_MM2_SOURCE_ALIAS -- Source cluster alias (default: east)
# FSI_MM2_TARGET_ALIAS -- Target cluster alias (default: west)
FSI_MM2_CONNECT_URL="${FSI_MM2_CONNECT_URL:-${FSI_CONNECT_URL:-http://localhost:8083}}"
FSI_MM2_SOURCE_CONNECTOR="${FSI_MM2_SOURCE_CONNECTOR:-mm2-source-east-west}"
FSI_MM2_CHECKPOINT_CONNECTOR="${FSI_MM2_CHECKPOINT_CONNECTOR:-mm2-checkpoint-east-west}"
FSI_MM2_HEARTBEAT_CONNECTOR="${FSI_MM2_HEARTBEAT_CONNECTOR:-mm2-heartbeat-east-west}"
FSI_MM2_SOURCE_ALIAS="${FSI_MM2_SOURCE_ALIAS:-east}"
FSI_MM2_TARGET_ALIAS="${FSI_MM2_TARGET_ALIAS:-west}"

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

# update_state -- Update a top-level key in state file
# Args: key value
update_state() {
  local key="$1" value="$2"
  local tmp
  tmp=$(mktemp "${FSI_DR_STATE_FILE}.XXXXXX")
  jq --arg k "${key}" --arg v "${value}" \
    '.[$k] = $v' "${FSI_DR_STATE_FILE}" > "${tmp}" && mv "${tmp}" "${FSI_DR_STATE_FILE}"
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

# cl_failover_mirrors -- Promote mirror topics via Cluster Linking
# Args: space-separated topic names
cl_failover_mirrors() {
  local topics="$1"
  if [ "${DRY_RUN}" = true ]; then
    # shellcheck disable=SC2086
    confluent kafka mirror failover ${topics} \
      --link "${FSI_CLUSTER_LINK_NAME}" \
      --cluster "${FSI_DR_DR_CLUSTER_ID}" \
      --environment "${FSI_DR_DR_ENV_ID}" \
      --dry-run -o json
  else
    # shellcheck disable=SC2086
    confluent kafka mirror failover ${topics} \
      --link "${FSI_CLUSTER_LINK_NAME}" \
      --cluster "${FSI_DR_DR_CLUSTER_ID}" \
      --environment "${FSI_DR_DR_ENV_ID}" \
      -o json
  fi
}

# cl_failback_truncate_and_restore -- Truncate East topics and restore as mirrors from West
# Args: space-separated topic names
cl_failback_truncate_and_restore() {
  local topics="$1"
  if [ "${DRY_RUN}" = true ]; then
    # shellcheck disable=SC2086
    confluent kafka mirror truncate-and-restore ${topics} \
      --link "${FSI_CLUSTER_LINK_NAME}" \
      --cluster "${FSI_DR_CLUSTER_ID}" \
      --environment "${FSI_DR_ENV_ID}" \
      --dry-run -o json
  else
    # shellcheck disable=SC2086
    confluent kafka mirror truncate-and-restore ${topics} \
      --link "${FSI_CLUSTER_LINK_NAME}" \
      --cluster "${FSI_DR_CLUSTER_ID}" \
      --environment "${FSI_DR_ENV_ID}" \
      -o json
  fi
}

# cl_failback_reverse_and_start -- Reverse mirror direction: East becomes R/W, West mirrors
# Args: space-separated topic names
cl_failback_reverse_and_start() {
  local topics="$1"
  if [ "${DRY_RUN}" = true ]; then
    # shellcheck disable=SC2086
    confluent kafka mirror reverse-and-start ${topics} \
      --link "${FSI_CLUSTER_LINK_NAME}" \
      --cluster "${FSI_DR_CLUSTER_ID}" \
      --environment "${FSI_DR_ENV_ID}" \
      --dry-run -o json
  else
    # shellcheck disable=SC2086
    confluent kafka mirror reverse-and-start ${topics} \
      --link "${FSI_CLUSTER_LINK_NAME}" \
      --cluster "${FSI_DR_CLUSTER_ID}" \
      --environment "${FSI_DR_ENV_ID}" \
      -o json
  fi
}

# cl_failback_mirrors -- Wrapper for backend dispatch (calls two-phase functions)
cl_failback_mirrors() {
  local topics="$1"
  cl_failback_truncate_and_restore "${topics}"
  cl_failback_reverse_and_start "${topics}"
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
# MirrorMaker 2 backend functions (Phase 8)
# MM2 uses Connect REST API to manage MM2 connectors on a dedicated
# Connect cluster. DR topics are standard Kafka topics (no mirror
# promotion needed during failover). Per D-06: "stop MM2 connectors +
# flip Consul to DR."
# ---------------------------------------------------------------------------

# mm2_preflight -- MM2-specific pre-flight checks
# Verifies MM2 Connect cluster, connector health, and Consul reachability
mm2_preflight() {
  local mm2_url="${FSI_MM2_CONNECT_URL}"
  local src="${FSI_MM2_SOURCE_CONNECTOR}"
  local chk="${FSI_MM2_CHECKPOINT_CONNECTOR}"
  local pass=0 warn=0 fail=0

  echo "=== Pre-flight Checks (MM2 Backend) ==="
  echo ""

  # Check 1: MM2 Connect cluster reachable
  if curl -sf "${mm2_url}/" >/dev/null 2>&1; then
    echo "  PASS: MM2 Connect cluster reachable"
    ((pass++)) || true
  else
    echo "  FAIL: MM2 Connect cluster unreachable at ${mm2_url}"
    ((fail++)) || true
  fi

  # Check 2: MirrorSourceConnector exists and is RUNNING
  local src_state
  src_state=$(curl -s "${mm2_url}/connectors/${src}/status" 2>/dev/null \
    | jq -r '.connector.state // "UNKNOWN"' 2>/dev/null || echo "UNKNOWN")
  if [ "${src_state}" = "RUNNING" ]; then
    echo "  PASS: MirrorSourceConnector (${src}) is RUNNING"
    ((pass++)) || true
  elif [ "${src_state}" = "PAUSED" ]; then
    echo "  WARN: MirrorSourceConnector (${src}) is PAUSED"
    ((warn++)) || true
  else
    echo "  FAIL: MirrorSourceConnector (${src}) state: ${src_state}"
    ((fail++)) || true
  fi

  # Check 3: MirrorCheckpointConnector exists and is RUNNING
  local chk_state
  chk_state=$(curl -s "${mm2_url}/connectors/${chk}/status" 2>/dev/null \
    | jq -r '.connector.state // "UNKNOWN"' 2>/dev/null || echo "UNKNOWN")
  if [ "${chk_state}" = "RUNNING" ]; then
    echo "  PASS: MirrorCheckpointConnector (${chk}) is RUNNING"
    ((pass++)) || true
  elif [ "${chk_state}" = "PAUSED" ]; then
    echo "  WARN: MirrorCheckpointConnector (${chk}) is PAUSED"
    ((warn++)) || true
  else
    echo "  FAIL: MirrorCheckpointConnector (${chk}) state: ${chk_state}"
    ((fail++)) || true
  fi

  # Check 4: DR cluster Kafka bootstrap reachable (if set)
  if [ -n "${FSI_DR_DR_BOOTSTRAP:-}" ]; then
    if curl -sf "${FSI_DR_DR_BOOTSTRAP}" >/dev/null 2>&1; then
      echo "  PASS: DR cluster bootstrap reachable"
      ((pass++)) || true
    else
      echo "  WARN: DR cluster bootstrap unreachable at ${FSI_DR_DR_BOOTSTRAP}"
      ((warn++)) || true
    fi
  else
    echo "  WARN: DR cluster bootstrap not configured (FSI_DR_DR_BOOTSTRAP)"
    ((warn++)) || true
  fi

  # Check 5: Consul reachable
  if curl -sf "${CONSUL_HTTP_ADDR}/v1/status/leader" >/dev/null 2>&1; then
    echo "  PASS: Consul reachable"
    ((pass++)) || true
  else
    echo "  FAIL: Consul unreachable at ${CONSUL_HTTP_ADDR}"
    ((fail++)) || true
  fi

  echo ""
  echo "Pre-flight: ${pass} passed, ${warn} warnings, ${fail} failed"
  [ "${fail}" -eq 0 ]
}

# mm2_failover_mirrors -- Pause all MM2 connectors (DR topics already writable)
# Per D-06: MM2 failover is simpler than CL -- stop replication, no promotion needed.
# NOTE: Does NOT call flip_consul -- orchestrator handles that via cmd_failover step 3.
mm2_failover_mirrors() {
  local mm2_url="${FSI_MM2_CONNECT_URL}"
  local src="${FSI_MM2_SOURCE_CONNECTOR}"
  local chk="${FSI_MM2_CHECKPOINT_CONNECTOR}"
  local hbt="${FSI_MM2_HEARTBEAT_CONNECTOR}"

  if [ "${DRY_RUN}" = true ]; then
    echo "  [DRY-RUN] Would pause MM2 connectors:"
    echo "    - ${src}"
    echo "    - ${chk}"
    echo "    - ${hbt}"
    echo ""
    echo "  MM2 failover is simpler than Cluster Linking:"
    echo "  DR topics are already writable (no mirror promotion needed)."
    return 0
  fi

  echo "  Pausing MM2 connectors..."
  local paused=0
  for name in "${src}" "${chk}" "${hbt}"; do
    curl -s -X PUT "${mm2_url}/connectors/${name}/pause" >/dev/null 2>&1 || true
    # Poll for PAUSED state (up to 30 iterations, 2s sleep)
    local i state
    for i in $(seq 1 30); do
      state=$(curl -s "${mm2_url}/connectors/${name}/status" 2>/dev/null \
        | jq -r '.connector.state // "UNKNOWN"' 2>/dev/null || echo "UNKNOWN")
      if [ "${state}" = "PAUSED" ]; then
        echo "  ${name}: PAUSED"
        ((paused++)) || true
        break
      fi
      sleep 2
    done
    if [ "${state}" != "PAUSED" ]; then
      echo "  WARNING: ${name} did not reach PAUSED state within timeout"
    fi
  done

  echo "  MM2 connectors paused (${paused}/3). DR topics are already writable (no mirror promotion needed)."
}

# mm2_failback_mirrors -- Reverse MM2 replication direction (DR -> Primary)
# Deletes existing connectors and creates reversed ones with swapped source/target.
mm2_failback_mirrors() {
  local mm2_url="${FSI_MM2_CONNECT_URL}"
  local src="${FSI_MM2_SOURCE_CONNECTOR}"
  local chk="${FSI_MM2_CHECKPOINT_CONNECTOR}"
  local hbt="${FSI_MM2_HEARTBEAT_CONNECTOR}"
  local src_alias="${FSI_MM2_SOURCE_ALIAS}"
  local tgt_alias="${FSI_MM2_TARGET_ALIAS}"

  if [ "${DRY_RUN}" = true ]; then
    echo "  [DRY-RUN] Would reverse MM2 replication direction:"
    echo "    Phase 1 -- Delete existing connectors:"
    echo "      - Would delete: ${src}"
    echo "      - Would delete: ${chk}"
    echo "      - Would delete: ${hbt}"
    echo "    Phase 2 -- Create reversed connectors:"
    echo "      - Would create: mm2-source-${tgt_alias}-${src_alias} (reversed)"
    echo "      - Would create: mm2-checkpoint-${tgt_alias}-${src_alias} (reversed)"
    echo "      - Would create: mm2-heartbeat-${tgt_alias}-${src_alias} (reversed)"
    echo ""
    echo "  Replication direction: ${tgt_alias} -> ${src_alias} (DR -> Primary)"
    return 0
  fi

  # Phase 1: Delete existing MM2 connectors
  echo "  Deleting existing MM2 connectors..."
  for name in "${src}" "${chk}" "${hbt}"; do
    curl -s -X DELETE "${mm2_url}/connectors/${name}" >/dev/null 2>&1 || true
    echo "  Deleted: ${name}"
  done

  # Phase 2: Create reversed connectors with swapped source/target
  local reversed_src="mm2-source-${tgt_alias}-${src_alias}"
  local reversed_chk="mm2-checkpoint-${tgt_alias}-${src_alias}"
  local reversed_hbt="mm2-heartbeat-${tgt_alias}-${src_alias}"

  # Get original source connector config for bootstrap servers
  local original_config
  original_config=$(curl -s "${mm2_url}/connectors/${src}/config" 2>/dev/null || echo "{}")
  local source_bootstrap target_bootstrap
  source_bootstrap=$(echo "${original_config}" | jq -r '.["source.cluster.bootstrap.servers"] // "kafka-east:9092"' 2>/dev/null || echo "kafka-east:9092")
  target_bootstrap=$(echo "${original_config}" | jq -r '.["target.cluster.bootstrap.servers"] // "kafka-west:9092"' 2>/dev/null || echo "kafka-west:9092")

  echo "  Creating reversed MirrorSourceConnector (${reversed_src})..."
  curl -s -X POST "${mm2_url}/connectors" \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"${reversed_src}\",
      \"config\": {
        \"connector.class\": \"org.apache.kafka.connect.mirror.MirrorSourceConnector\",
        \"source.cluster.alias\": \"${tgt_alias}\",
        \"target.cluster.alias\": \"${src_alias}\",
        \"source.cluster.bootstrap.servers\": \"${target_bootstrap}\",
        \"target.cluster.bootstrap.servers\": \"${source_bootstrap}\",
        \"topics\": \".*\",
        \"topics.exclude\": \".*\\\\.internal,.*\\\\.replica,__.*\",
        \"replication.factor\": \"3\",
        \"sync.topic.configs.enabled\": \"true\"
      }
    }" >/dev/null 2>&1 || true

  echo "  Creating reversed MirrorCheckpointConnector (${reversed_chk})..."
  curl -s -X POST "${mm2_url}/connectors" \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"${reversed_chk}\",
      \"config\": {
        \"connector.class\": \"org.apache.kafka.connect.mirror.MirrorCheckpointConnector\",
        \"source.cluster.alias\": \"${tgt_alias}\",
        \"target.cluster.alias\": \"${src_alias}\",
        \"source.cluster.bootstrap.servers\": \"${target_bootstrap}\",
        \"target.cluster.bootstrap.servers\": \"${source_bootstrap}\",
        \"emit.checkpoints.enabled\": \"true\"
      }
    }" >/dev/null 2>&1 || true

  echo "  Creating reversed MirrorHeartbeatConnector (${reversed_hbt})..."
  curl -s -X POST "${mm2_url}/connectors" \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"${reversed_hbt}\",
      \"config\": {
        \"connector.class\": \"org.apache.kafka.connect.mirror.MirrorHeartbeatConnector\",
        \"source.cluster.alias\": \"${tgt_alias}\",
        \"target.cluster.alias\": \"${src_alias}\",
        \"source.cluster.bootstrap.servers\": \"${target_bootstrap}\",
        \"target.cluster.bootstrap.servers\": \"${source_bootstrap}\"
      }
    }" >/dev/null 2>&1 || true

  # Wait for new connectors to reach RUNNING state
  echo "  Waiting for reversed connectors to start..."
  for name in "${reversed_src}" "${reversed_chk}" "${reversed_hbt}"; do
    local i state
    for i in $(seq 1 30); do
      state=$(curl -s "${mm2_url}/connectors/${name}/status" 2>/dev/null \
        | jq -r '.connector.state // "UNKNOWN"' 2>/dev/null || echo "UNKNOWN")
      if [ "${state}" = "RUNNING" ]; then
        echo "  ${name}: RUNNING"
        break
      fi
      sleep 2
    done
    if [ "${state}" != "RUNNING" ]; then
      echo "  WARNING: ${name} did not reach RUNNING state within timeout"
    fi
  done

  echo "  MM2 replication reversed (${tgt_alias} -> ${src_alias}). Monitor lag before cutover."
}

# mm2_get_mirror_lag -- Report per-topic replication lag for MM2
# Queries MirrorSourceConnector status and config via Connect REST API.
# Returns JSON array matching CL format for fsi-dr status compatibility.
# NOTE: Per-topic lag granularity requires Prometheus/JMX; this function
# reports connector-level state with topic list from connector config.
mm2_get_mirror_lag() {
  local mm2_url="${FSI_MM2_CONNECT_URL}"
  local src="${FSI_MM2_SOURCE_CONNECTOR}"

  # Get connector status for task states
  local status_json
  status_json=$(curl -s "${mm2_url}/connectors/${src}/status" 2>/dev/null || echo "{}")
  local connector_state
  connector_state=$(echo "${status_json}" | jq -r '.connector.state // "UNKNOWN"' 2>/dev/null || echo "UNKNOWN")

  # Get replicated topics from connector config
  local config_json
  config_json=$(curl -s "${mm2_url}/connectors/${src}/config" 2>/dev/null || echo "{}")
  local topics_pattern
  topics_pattern=$(echo "${config_json}" | jq -r '.["topics"] // ".*"' 2>/dev/null || echo ".*")
  local src_alias
  src_alias=$(echo "${config_json}" | jq -r '.["source.cluster.alias"] // "east"' 2>/dev/null || echo "east")

  # Build lag entries -- MM2 does not expose per-topic lag via REST API,
  # so we report connector-level status with -1 lag to indicate
  # that per-topic granularity requires Prometheus/JMX metrics
  local lag_status
  case "${connector_state}" in
    RUNNING) lag_status="ACTIVE" ;;
    PAUSED)  lag_status="PAUSED" ;;
    FAILED)  lag_status="FAILED" ;;
    *)       lag_status="UNKNOWN" ;;
  esac

  # Return JSON array compatible with CL format
  # mirror_lag_ms=-1 signals that detailed per-topic lag needs JMX/Prometheus
  jq -n \
    --arg src_alias "${src_alias}" \
    --arg topics "${topics_pattern}" \
    --arg status "${lag_status}" \
    --arg note "MM2 per-topic lag requires Prometheus/JMX. Connector state shown." \
    '[{
      "mirror_topic_name": ($src_alias + ".*"),
      "mirror_lag_ms": -1,
      "status": $status,
      "partition_mirror_lags": [{"partition": 0, "lag": -1}],
      "note": $note
    }]'
}

# mm2_get_mirror_status -- Report MM2 connector states
# Returns JSON array with status of all 3 MM2 connectors.
mm2_get_mirror_status() {
  local mm2_url="${FSI_MM2_CONNECT_URL}"
  local src="${FSI_MM2_SOURCE_CONNECTOR}"
  local chk="${FSI_MM2_CHECKPOINT_CONNECTOR}"
  local hbt="${FSI_MM2_HEARTBEAT_CONNECTOR}"

  local result="["
  local first=true
  for name in "${src}" "${chk}" "${hbt}"; do
    local status_json
    status_json=$(curl -s "${mm2_url}/connectors/${name}/status" 2>/dev/null || echo "{}")
    local state
    state=$(echo "${status_json}" | jq -r '.connector.state // "UNKNOWN"' 2>/dev/null || echo "UNKNOWN")
    local tasks
    tasks=$(echo "${status_json}" | jq -c '[.tasks[]? | {id: .id, state: .state}]' 2>/dev/null || echo "[]")

    if [ "${first}" = true ]; then
      first=false
    else
      result="${result},"
    fi
    result="${result}{\"name\":\"${name}\",\"state\":\"${state}\",\"tasks\":${tasks}}"
  done
  result="${result}]"

  echo "${result}"
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
      backend_preflight()        { mm2_preflight "$@"; }
      backend_failover_mirrors() { mm2_failover_mirrors "$@"; }
      backend_failback_mirrors() { mm2_failback_mirrors "$@"; }
      backend_get_mirror_lag()   { mm2_get_mirror_lag "$@"; }
      backend_get_mirror_status(){ mm2_get_mirror_status "$@"; }
      ;;
    *)
      echo "ERROR: Unknown backend: ${FSI_DR_BACKEND}. Supported: cluster-linking, mm2"
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
# Confirmation and safety functions (D-10, D-06, D-16)
# ---------------------------------------------------------------------------

# confirm_proceed -- Require operator confirmation unless --force
# Args: message (optional)
confirm_proceed() {
  local message="${1:-Proceed?}"
  if [ "${FORCE}" = true ]; then
    echo "[--force] ${message} (auto-confirmed)"
    return 0
  fi
  read -p "${message} (yes/no): " CONFIRM
  [ "${CONFIRM}" = "yes" ] || { echo "Aborted by operator."; exit 1; }
}

# print_rollback_instructions -- Print manual rollback guidance per failed step (D-06)
# Args: failed_step (1-6)
print_rollback_instructions() {
  local failed_step="$1"
  echo ""
  echo "============================================"
  echo " FAILOVER HALTED -- Step ${failed_step} failed"
  echo "============================================"
  echo ""
  echo "Current state saved to: ${FSI_DR_STATE_FILE}"
  echo "Review state: fsi-dr.sh status"
  echo ""
  echo "ROLLBACK GUIDANCE (manual -- review before executing):"
  echo ""
  case "${failed_step}" in
    1)
      echo "  Step 1 (Pause Connectors) failed."
      echo "  Action: Check Connect REST API at ${FSI_CONNECT_URL}"
      echo "  Some connectors may be paused. Resume manually:"
      echo "    curl -s -X PUT ${FSI_CONNECT_URL}/connectors/<name>/resume"
      ;;
    2)
      echo "  Step 2 (Promote Mirrors) failed."
      echo "  Action: Some mirror topics may be promoted, others still mirroring."
      echo "  Check mirror status:"
      echo "    confluent kafka mirror list --link ${FSI_CLUSTER_LINK_NAME} --cluster ${FSI_DR_DR_CLUSTER_ID} --environment ${FSI_DR_DR_ENV_ID}"
      echo "  Partially promoted topics cannot be automatically reverted."
      echo "  Consult DR runbook: docs/dr-runbook.md"
      ;;
    3)
      echo "  Step 3 (Flip Consul) failed."
      echo "  Action: Mirrors are promoted but endpoints still point to East."
      echo "  Manual Consul flip:"
      echo "    consul kv put fsi/kafka/active-region west"
      echo "  Or revert mirrors (requires failback procedure)."
      ;;
    4)
      echo "  Step 4 (Verify Endpoints) failed."
      echo "  Action: Consul flipped but endpoint verification failed."
      echo "  Check DNS resolution:"
      echo "    dig +short kafka.fsi.internal"
      echo "    dig +short schema.fsi.internal"
      echo "  May need to wait for DNS propagation or check Consul health."
      ;;
    5)
      echo "  Step 5 (Resume Connectors) failed."
      echo "  Action: Failover is functionally complete (Kafka is live on DR)."
      echo "  Resume connectors manually:"
      echo "    curl -s -X PUT ${FSI_CONNECT_URL}/connectors/<name>/resume"
      echo "  Check state file for previously-RUNNING connectors."
      ;;
    6)
      echo "  Step 6 (Final Validation) failed."
      echo "  Action: Failover completed but validation found issues."
      echo "  Check cluster health and connectivity manually."
      ;;
  esac
  echo ""
  echo "  Full runbook: docs/dr-runbook.md"
  echo "  State file: cat ${FSI_DR_STATE_FILE} | jq ."
}

# check_mirror_lag_warning -- Warn on per-topic data loss risk (D-16)
check_mirror_lag_warning() {
  local lag_json topics_with_alert=0
  lag_json=$(get_mirror_lag_json 2>/dev/null || echo "[]")

  if [ "${lag_json}" = "[]" ] || [ -z "${lag_json}" ]; then
    echo "  WARNING: Unable to fetch mirror lag data. Proceeding without lag assessment."
    return 0
  fi

  local topic lag_ms lag_sec tier assessment threshold
  for row in $(echo "${lag_json}" | jq -c '.[]'); do
    topic=$(echo "${row}" | jq -r '.mirror_topic_name // .topic_name // "unknown"')
    lag_ms=$(echo "${row}" | jq -r '.mirror_lag_ms // .num_messages_lag // 0')
    lag_sec=$(( lag_ms / 1000 ))
    tier=$(get_topic_sla_tier "${topic}" 2>/dev/null || echo "standard")
    assessment=$(assess_lag "${lag_sec}" "${tier}")

    if [ "${assessment}" = "ALERT" ]; then
      ((topics_with_alert++))
      threshold=$(_tier_alert_threshold "${tier}")
      printf "  ALERT: %-50s tier=%-12s lag=%ss (threshold=%ss)\n" "${topic}" "${tier}" "${lag_sec}" "${threshold}"
    fi
  done

  if [ "${topics_with_alert}" -gt 0 ]; then
    echo ""
    echo "WARNING: ${topics_with_alert} topic(s) exceed RPO alert threshold."
    echo "Proceeding with failover may result in data loss for these topics."
    confirm_proceed "Acknowledge data loss risk and proceed?"
  fi
}

# ---------------------------------------------------------------------------
# Failover step functions (D-05: 6-step sequence)
# ---------------------------------------------------------------------------

# step_1_pause_connectors -- Pause all RUNNING connectors, snapshot state
step_1_pause_connectors() {
  if [ "${DRY_RUN}" = true ]; then
    local connector_json connector_count running_count
    connector_json=$(curl -s "${FSI_CONNECT_URL}/connectors?expand=status" 2>/dev/null || echo "{}")
    connector_count=$(echo "${connector_json}" | jq 'keys | length' 2>/dev/null || echo "0")
    running_count=$(echo "${connector_json}" | jq '[to_entries[] | select(.value.status.connector.state == "RUNNING")] | length' 2>/dev/null || echo "0")
    printf "%-6s %-30s %-40s %-30s\n" "1" "Pause Connectors" "${connector_count} connectors (${running_count} RUNNING)" "All RUNNING -> PAUSED"
    echo ""
    echo "  [DRY-RUN] Would pause ${running_count} connectors"
    return 0
  fi

  local snapshot_json
  snapshot_json=$(snapshot_connectors)
  local running_names
  running_names=$(get_running_connectors)

  if [ -z "${running_names}" ]; then
    echo "  No RUNNING connectors to pause."
    return 0
  fi

  local paused_count=0
  for name in ${running_names}; do
    if pause_connector "${name}"; then
      ((paused_count++))
    fi
  done

  echo "  Paused ${paused_count} connectors."
}

# step_2_promote_mirrors -- Promote mirror topics to writable
step_2_promote_mirrors() {
  local mirror_json topics topic_list topic_count

  mirror_json=$(confluent kafka mirror list \
    --link "${FSI_CLUSTER_LINK_NAME}" \
    --cluster "${FSI_DR_DR_CLUSTER_ID}" \
    --environment "${FSI_DR_DR_ENV_ID}" \
    -o json 2>/dev/null || echo "[]")

  topics=$(echo "${mirror_json}" | jq -r '.[] | select(.status == "ACTIVE" or .mirror_status == "ACTIVE") | .mirror_topic_name' 2>/dev/null || true)
  topic_list=$(echo "${topics}" | tr '\n' ' ' | xargs)
  topic_count=$(echo "${topics}" | grep -c . || true)

  if [ -z "${topic_list}" ] || [ "${topic_count}" -eq 0 ]; then
    echo "  ERROR: No active mirror topics found. Check cluster link status."
    return 1
  fi

  if [ "${DRY_RUN}" = true ]; then
    printf "%-6s %-30s %-40s %-30s\n" "2" "Promote Mirrors" "${topic_count} active mirror topics" "All mirrors -> writable"
    echo ""
    echo "  [DRY-RUN] Would promote ${topic_count} mirror topics:"

    # Show per-topic lag table
    printf "  %-50s %-12s %-10s %-12s %s\n" "TOPIC" "SLA TIER" "LAG" "THRESHOLD" "STATUS"
    printf "  %-50s %-12s %-10s %-12s %s\n" "-----" "--------" "---" "---------" "------"

    for topic in ${topics}; do
      local lag_ms lag_sec tier threshold assessment
      lag_ms=$(echo "${mirror_json}" | jq -r ".[] | select(.mirror_topic_name == \"${topic}\") | .mirror_lag_ms // .num_messages_lag // 0" 2>/dev/null || echo "0")
      lag_sec=$(( lag_ms / 1000 ))
      tier=$(get_topic_sla_tier "${topic}" 2>/dev/null || echo "standard")
      threshold=$(get_tier_threshold "${tier}")
      assessment=$(assess_lag "${lag_sec}" "${tier}")
      printf "  %-50s %-12s %-10s %-12s %s\n" "${topic}" "${tier}" "${lag_sec}s" "${threshold}s" "${assessment}"
    done

    echo ""
    echo "  Confluent CLI dry-run output:"
    cl_failover_mirrors "${topic_list}" || true
    return 0
  fi

  echo "  Promoting ${topic_count} mirror topics..."
  cl_failover_mirrors "${topic_list}"
  record_topics "${topic_list}"
  echo "  Promoted ${topic_count} topics."
}

# step_3_flip_consul -- Flip active region in Consul KV to west
step_3_flip_consul() {
  if [ "${DRY_RUN}" = true ]; then
    local current_region
    current_region=$(consul kv get fsi/kafka/active-region 2>/dev/null || echo "unknown")
    printf "%-6s %-30s %-40s %-30s\n" "3" "Flip Consul" "active-region=${current_region}" "active-region=west"
    echo ""
    echo "  [DRY-RUN] Would flip Consul active-region from '${current_region}' to 'west'"
    return 0
  fi

  consul kv put fsi/kafka/active-region west
  local verified
  verified=$(consul kv get fsi/kafka/active-region)
  if [ "${verified}" = "west" ]; then
    echo "  Consul active-region flipped to: west"
  else
    echo "  ERROR: Consul active-region is '${verified}', expected 'west'"
    return 1
  fi
}

# step_4_verify_endpoints -- Verify DNS resolution after Consul flip
step_4_verify_endpoints() {
  local endpoints=("kafka.fsi.internal" "schema.fsi.internal" "oracle.fsi.internal")

  if [ "${DRY_RUN}" = true ]; then
    local current_ips=""
    for ep in "${endpoints[@]}"; do
      local ip
      ip=$(dig +short "${ep}" 2>/dev/null || echo "unresolvable")
      current_ips="${current_ips} ${ep}=${ip}"
    done
    printf "%-6s %-30s %-40s %-30s\n" "4" "Verify Endpoints" "DNS:${current_ips}" "Resolve to DR (west) IPs"
    echo ""
    echo "  [DRY-RUN] Would verify DNS resolution for: ${endpoints[*]}"
    return 0
  fi

  local all_ok=true
  for ep in "${endpoints[@]}"; do
    local resolved=false
    local i
    for i in $(seq 1 10); do
      local ip
      ip=$(dig +short "${ep}" 2>/dev/null || echo "")
      if [ -n "${ip}" ]; then
        echo "  ${ep} -> ${ip}"
        resolved=true
        break
      fi
      sleep 3
    done
    if [ "${resolved}" = false ]; then
      echo "  WARN: ${ep} did not resolve within timeout"
      all_ok=false
    fi
  done

  if [ "${all_ok}" = false ]; then
    echo "  WARNING: Some endpoints did not resolve. Check DNS propagation."
    return 1
  fi
}

# step_5_resume_connectors -- Resume only previously-RUNNING connectors (D-08)
step_5_resume_connectors() {
  if [ "${DRY_RUN}" = true ]; then
    local connector_json running_count
    connector_json=$(curl -s "${FSI_CONNECT_URL}/connectors?expand=status" 2>/dev/null || echo "{}")
    running_count=$(echo "${connector_json}" | jq '[to_entries[] | select(.value.status.connector.state == "RUNNING")] | length' 2>/dev/null || echo "0")
    printf "%-6s %-30s %-40s %-30s\n" "5" "Resume Connectors" "Connectors paused in Step 1" "Resume RUNNING-only (${running_count})"
    echo ""
    echo "  [DRY-RUN] Would resume ${running_count} connectors (only those that were RUNNING)"
    return 0
  fi

  local running_names
  running_names=$(get_running_connectors)

  if [ -z "${running_names}" ]; then
    echo "  No connectors to resume (none were RUNNING before failover)."
    return 0
  fi

  local resumed_count=0
  for name in ${running_names}; do
    if resume_connector "${name}"; then
      ((resumed_count++))
    fi
  done

  echo "  Resumed ${resumed_count} connectors."
}

# step_6_final_validation -- Verify DR cluster is operational
step_6_final_validation() {
  if [ "${DRY_RUN}" = true ]; then
    printf "%-6s %-30s %-40s %-30s\n" "6" "Final Validation" "DR cluster, mirrors, Connect" "All verified healthy"
    echo ""
    echo "  [DRY-RUN] Would verify: DR cluster writable, mirrors stopped/promoted, Connect running"
    return 0
  fi

  local pass=0 fail=0

  # Verify DR cluster is accessible
  if confluent kafka cluster describe "${FSI_DR_DR_CLUSTER_ID}" \
    --environment "${FSI_DR_DR_ENV_ID}" -o json 2>/dev/null | jq -e . >/dev/null 2>&1; then
    echo "  PASS: DR cluster accessible"
    ((pass++))
  else
    echo "  FAIL: DR cluster not accessible"
    ((fail++))
  fi

  # Check mirror status shows STOPPED (promoted)
  local mirror_status
  mirror_status=$(confluent kafka mirror list \
    --link "${FSI_CLUSTER_LINK_NAME}" \
    --cluster "${FSI_DR_DR_CLUSTER_ID}" \
    --environment "${FSI_DR_DR_ENV_ID}" \
    -o json 2>/dev/null || echo "[]")
  local active_count
  active_count=$(echo "${mirror_status}" | jq '[.[] | select(.status == "ACTIVE" or .mirror_status == "ACTIVE")] | length' 2>/dev/null || echo "0")
  if [ "${active_count}" -eq 0 ]; then
    echo "  PASS: No active mirrors (all promoted)"
    ((pass++))
  else
    echo "  WARN: ${active_count} mirrors still active (may need time to complete)"
    ((pass++))  # Not a hard failure -- promotion may be in progress
  fi

  # Check connector status
  local connector_json running_count
  connector_json=$(curl -s "${FSI_CONNECT_URL}/connectors?expand=status" 2>/dev/null || echo "{}")
  running_count=$(echo "${connector_json}" | jq '[to_entries[] | select(.value.status.connector.state == "RUNNING")] | length' 2>/dev/null || echo "0")
  echo "  INFO: ${running_count} connectors RUNNING"
  ((pass++))

  echo ""
  echo "  Validation: ${pass} passed, ${fail} failed"
  [ "${fail}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Failover command (D-05: 6-step orchestrated failover)
# ---------------------------------------------------------------------------
cmd_failover() {
  echo "============================================"
  echo " FSI DR FAILOVER"
  echo " Backend: ${FSI_DR_BACKEND}"
  if [ "${DRY_RUN}" = true ]; then
    echo " Mode: DRY-RUN (no changes will be made)"
  fi
  echo "============================================"
  echo ""

  # Pre-flight (always runs, per D-11)
  echo "--- Pre-Flight Checks ---"
  if ! preflight_check; then
    echo ""
    echo "ABORT: Pre-flight checks failed. Fix issues above before retrying."
    exit 1
  fi
  echo ""

  # Mirror lag warning (per D-16)
  if [ "${DRY_RUN}" = false ]; then
    check_mirror_lag_warning
  fi

  # Dry-run table header (per D-09)
  if [ "${DRY_RUN}" = true ]; then
    echo "--- Dry-Run Plan ---"
    printf "%-6s %-30s %-40s %-30s\n" "STEP" "ACTION" "CURRENT STATE" "EXPECTED RESULT"
    printf "%-6s %-30s %-40s %-30s\n" "----" "------" "-------------" "---------------"
  fi

  # Confirmation (per D-10)
  if [ "${DRY_RUN}" = false ]; then
    confirm_proceed "Execute failover sequence?"
    init_state "failover"
  fi

  # Execute steps (per D-05)
  local step_funcs=("step_1_pause_connectors" "step_2_promote_mirrors" "step_3_flip_consul" "step_4_verify_endpoints" "step_5_resume_connectors" "step_6_final_validation")
  local step_names=("pause_connectors" "promote_mirrors" "flip_consul" "verify_endpoints" "resume_connectors" "final_validation")

  for i in "${!step_funcs[@]}"; do
    local step_num=$((i + 1))
    local step_func="${step_funcs[$i]}"
    local step_name="${step_names[$i]}"

    echo ""
    echo "--- Step ${step_num}/6: ${step_name} ---"

    if ! ${step_func}; then
      if [ "${DRY_RUN}" = false ]; then
        update_state "status" "failed"
        print_rollback_instructions "${step_num}"
      fi
      exit 1
    fi

    if [ "${DRY_RUN}" = false ]; then
      record_step "${step_num}" "${step_name}"
    fi
  done

  echo ""
  if [ "${DRY_RUN}" = true ]; then
    echo "============================================"
    echo " DRY-RUN COMPLETE -- No changes were made"
    echo "============================================"
  else
    cleanup_state
    echo "============================================"
    echo " FAILOVER COMPLETE"
    echo " Active region: west (DR)"
    echo "============================================"
  fi
}

# ---------------------------------------------------------------------------
# Failback rollback instructions (D-06: guidance only, no auto-rollback)
# ---------------------------------------------------------------------------

# print_failback_rollback_instructions -- Print manual rollback guidance per failed failback step
# Args: failed_step (1-8)
print_failback_rollback_instructions() {
  local failed_step="$1"
  echo ""
  echo "============================================"
  echo " FAILBACK HALTED -- Step ${failed_step} failed"
  echo "============================================"
  echo ""
  echo "Current state saved to: ${FSI_DR_STATE_FILE}"
  echo "Review state: fsi-dr.sh status"
  echo ""
  echo "ROLLBACK GUIDANCE (manual -- review before executing):"
  echo ""
  case "${failed_step}" in
    1)
      echo "  Step 1 (Verify East Cluster) failed."
      echo "  Action: East cluster is not reachable. Cannot failback until East is recovered."
      echo "  Wait for East cluster to come online, then retry failback."
      ;;
    2)
      echo "  Step 2 (Pause Connectors on West) failed."
      echo "  Action: Some connectors may be paused. System is still running on West."
      echo "  Resume paused connectors:"
      echo "    curl -s -X PUT ${FSI_CONNECT_URL}/connectors/<name>/resume"
      ;;
    3)
      echo "  Step 3 (Truncate and Restore) failed."
      echo "  Action: CRITICAL -- truncate-and-restore is destructive."
      echo "  If partially completed, some East topics may be truncated."
      echo "  Check East mirror status:"
      echo "    confluent kafka mirror list --link ${FSI_CLUSTER_LINK_NAME} --cluster ${FSI_DR_CLUSTER_ID} --environment ${FSI_DR_ENV_ID}"
      echo "  Consult DR runbook: docs/dr-runbook.md section 'Failback Recovery'"
      ;;
    4)
      echo "  Step 4 (Wait for Sync) failed."
      echo "  Action: Data is syncing from West to East but not yet complete."
      echo "  Check mirror lag and wait:"
      echo "    fsi-dr.sh status"
      echo "  Retry failback when lag is near zero."
      ;;
    5)
      echo "  Step 5 (Reverse and Start) failed."
      echo "  Action: East has data but is still mirroring. Cannot serve traffic yet."
      echo "  Retry reverse-and-start manually:"
      echo "    confluent kafka mirror reverse-and-start <topics> --link ${FSI_CLUSTER_LINK_NAME} --cluster ${FSI_DR_CLUSTER_ID} --environment ${FSI_DR_ENV_ID}"
      ;;
    6)
      echo "  Step 6 (Flip Consul to East) failed."
      echo "  Action: East is ready but Consul not updated. Manual flip:"
      echo "    consul kv put fsi/kafka/active-region east"
      ;;
    7)
      echo "  Step 7 (Resume Connectors) failed."
      echo "  Action: Failback is functionally complete (Kafka is live on East)."
      echo "  Resume connectors manually."
      ;;
    8)
      echo "  Step 8 (Final Validation) failed."
      echo "  Action: Failback completed but validation found issues."
      echo "  Check East cluster health manually."
      ;;
  esac
  echo ""
  echo "  Full runbook: docs/dr-runbook.md"
  echo "  State file: cat ${FSI_DR_STATE_FILE} | jq ."
}

# ---------------------------------------------------------------------------
# Failback step functions (8-step reverse sequence)
# ---------------------------------------------------------------------------

# fb_step_1_verify_east -- Verify East (production) cluster is reachable
fb_step_1_verify_east() {
  if [ "${DRY_RUN}" = true ]; then
    local cluster_info
    cluster_info=$(confluent kafka cluster describe "${FSI_DR_CLUSTER_ID}" \
      --environment "${FSI_DR_ENV_ID}" -o json 2>/dev/null || echo "{}")
    printf "%-6s %-30s %-40s %-30s\n" "1" "Verify East Cluster" "East=${FSI_DR_CLUSTER_ID}" "Reachable and healthy"
    echo ""
    echo "  [DRY-RUN] East cluster status: $(echo "${cluster_info}" | jq -r '.status // "unknown"' 2>/dev/null || echo "unknown")"
    return 0
  fi

  if confluent kafka cluster describe "${FSI_DR_CLUSTER_ID}" \
    --environment "${FSI_DR_ENV_ID}" -o json 2>/dev/null | jq -e . >/dev/null 2>&1; then
    echo "  PASS: East cluster reachable"
  else
    echo "  FAIL: East cluster not reachable. Cannot failback."
    return 1
  fi
}

# fb_step_2_pause_connectors -- Pause all RUNNING connectors on West
fb_step_2_pause_connectors() {
  if [ "${DRY_RUN}" = true ]; then
    local connector_json connector_count running_count
    connector_json=$(curl -s "${FSI_CONNECT_URL}/connectors?expand=status" 2>/dev/null || echo "{}")
    connector_count=$(echo "${connector_json}" | jq 'keys | length' 2>/dev/null || echo "0")
    running_count=$(echo "${connector_json}" | jq '[to_entries[] | select(.value.status.connector.state == "RUNNING")] | length' 2>/dev/null || echo "0")
    printf "%-6s %-30s %-40s %-30s\n" "2" "Pause Connectors (West)" "${connector_count} connectors (${running_count} RUNNING)" "All RUNNING -> PAUSED"
    echo ""
    echo "  [DRY-RUN] Would pause ${running_count} connectors on West"
    return 0
  fi

  local snapshot_json
  snapshot_json=$(snapshot_connectors)
  local running_names
  running_names=$(get_running_connectors)

  if [ -z "${running_names}" ]; then
    echo "  No RUNNING connectors to pause."
    return 0
  fi

  local paused_count=0
  for name in ${running_names}; do
    if pause_connector "${name}"; then
      ((paused_count++))
    fi
  done

  echo "  Paused ${paused_count} connectors."
}

# fb_step_3_truncate_and_restore -- Truncate East topics and restore as mirrors from West
# DESTRUCTIVE: Extra confirmation gate required
fb_step_3_truncate_and_restore() {
  local topic_list topic_count

  # Get topic list from East cluster (non-internal topics)
  topic_list=$(confluent kafka topic list \
    --cluster "${FSI_DR_CLUSTER_ID}" \
    --environment "${FSI_DR_ENV_ID}" \
    -o json 2>/dev/null | jq -r '.[].name' 2>/dev/null | grep -v '^_' | tr '\n' ' ' | xargs)
  topic_count=$(echo "${topic_list}" | wc -w | tr -d ' ')

  if [ -z "${topic_list}" ] || [ "${topic_count}" -eq 0 ]; then
    echo "  ERROR: No topics found on East cluster."
    return 1
  fi

  if [ "${DRY_RUN}" = true ]; then
    printf "%-6s %-30s %-40s %-30s\n" "3" "Truncate and Restore" "${topic_count} topics on East" "East topics become mirrors"
    echo ""
    echo "  [DRY-RUN] Would truncate-and-restore ${topic_count} East topics (DESTRUCTIVE)"
    echo "  Topics: ${topic_list}"
    echo ""
    echo "  Confluent CLI dry-run output:"
    cl_failback_truncate_and_restore "${topic_list}" || true
    return 0
  fi

  # Extra confirmation gate -- truncate-and-restore is destructive (per mirror-failback.sh pattern)
  confirm_proceed "DESTRUCTIVE: truncate-and-restore will truncate East topics. Proceed?"

  echo "  Truncating and restoring ${topic_count} topics..."
  cl_failback_truncate_and_restore "${topic_list}"
  echo "  Truncate-and-restore complete for ${topic_count} topics."
}

# fb_step_4_wait_for_sync -- Wait for mirror lag to reach near-zero
fb_step_4_wait_for_sync() {
  if [ "${DRY_RUN}" = true ]; then
    printf "%-6s %-30s %-40s %-30s\n" "4" "Wait for Sync" "Mirrors replicating West->East" "Near-zero lag"
    echo ""
    echo "  [DRY-RUN] Would wait for mirror sync (targets near-zero lag)"
    return 0
  fi

  local timeout="${FSI_DR_SYNC_TIMEOUT:-300}"
  local interval=10
  local elapsed=0
  local last_report=0

  echo "  Waiting for mirror sync (timeout: ${timeout}s)..."

  while [ "${elapsed}" -lt "${timeout}" ]; do
    # Check mirror lag on East (now mirroring from West)
    local lag_json
    lag_json=$(confluent kafka mirror list \
      --link "${FSI_CLUSTER_LINK_NAME}" \
      --cluster "${FSI_DR_CLUSTER_ID}" \
      --environment "${FSI_DR_ENV_ID}" \
      -o json 2>/dev/null || echo "[]")

    if [ "${lag_json}" = "[]" ] || [ -z "${lag_json}" ]; then
      echo "  WARNING: Unable to fetch mirror status. Retrying..."
      sleep "${interval}"
      elapsed=$((elapsed + interval))
      continue
    fi

    # Check if all topics have acceptable lag
    local all_synced=true
    local topics
    topics=$(echo "${lag_json}" | jq -r '.[].mirror_topic_name // empty' 2>/dev/null || true)

    for topic in ${topics}; do
      local lag_ms lag_sec tier warn_threshold
      lag_ms=$(echo "${lag_json}" | jq -r ".[] | select(.mirror_topic_name == \"${topic}\") | .mirror_lag_ms // .partition_mirror_lags[0].lag // 0" 2>/dev/null || echo "0")
      lag_sec=$((lag_ms / 1000))
      tier=$(get_topic_sla_tier "${topic}" 2>/dev/null || echo "standard")
      warn_threshold=$(_tier_warn_threshold "${tier}")

      if [ "${lag_sec}" -ge "${warn_threshold}" ]; then
        all_synced=false
        break
      fi
    done

    if [ "${all_synced}" = true ]; then
      echo "  PASS: All mirrors synced (lag within tier thresholds)."
      return 0
    fi

    # Progress report every 30s
    if [ $((elapsed - last_report)) -ge 30 ]; then
      echo "  Sync in progress... (${elapsed}s elapsed)"
      last_report="${elapsed}"
    fi

    sleep "${interval}"
    elapsed=$((elapsed + interval))
  done

  echo "  WARN: Sync timeout reached (${timeout}s). Some topics may still have lag."
  echo "  Check status: fsi-dr.sh status"
  return 1
}

# fb_step_5_reverse_and_start -- Reverse mirror direction: East becomes R/W
fb_step_5_reverse_and_start() {
  local topic_list topic_count

  # Get topic list (same approach as step 3)
  topic_list=$(confluent kafka topic list \
    --cluster "${FSI_DR_CLUSTER_ID}" \
    --environment "${FSI_DR_ENV_ID}" \
    -o json 2>/dev/null | jq -r '.[].name' 2>/dev/null | grep -v '^_' | tr '\n' ' ' | xargs)
  topic_count=$(echo "${topic_list}" | wc -w | tr -d ' ')

  if [ -z "${topic_list}" ] || [ "${topic_count}" -eq 0 ]; then
    echo "  ERROR: No topics found on East cluster."
    return 1
  fi

  if [ "${DRY_RUN}" = true ]; then
    printf "%-6s %-30s %-40s %-30s\n" "5" "Reverse and Start" "${topic_count} mirrored topics" "East -> R/W, West -> mirrors"
    echo ""
    echo "  [DRY-RUN] Would reverse-and-start ${topic_count} topics (East becomes primary)"
    echo ""
    echo "  Confluent CLI dry-run output:"
    cl_failback_reverse_and_start "${topic_list}" || true
    return 0
  fi

  # Second confirmation gate (per mirror-failback.sh two-gate pattern)
  confirm_proceed "Data synced. Proceed with reverse-and-start? (East becomes R/W)"

  echo "  Reversing mirror direction for ${topic_count} topics..."
  cl_failback_reverse_and_start "${topic_list}"
  record_topics "${topic_list}"
  echo "  Reverse-and-start complete. East is now R/W."
}

# fb_step_6_flip_consul -- Flip active region in Consul KV to east
fb_step_6_flip_consul() {
  if [ "${DRY_RUN}" = true ]; then
    local current_region
    current_region=$(consul kv get fsi/kafka/active-region 2>/dev/null || echo "unknown")
    printf "%-6s %-30s %-40s %-30s\n" "6" "Flip Consul to East" "active-region=${current_region}" "active-region=east"
    echo ""
    echo "  [DRY-RUN] Would flip Consul active-region from '${current_region}' to 'east'"
    return 0
  fi

  consul kv put fsi/kafka/active-region east
  local verified
  verified=$(consul kv get fsi/kafka/active-region)
  if [ "${verified}" = "east" ]; then
    echo "  Consul active-region flipped to: east"
  else
    echo "  ERROR: Consul active-region is '${verified}', expected 'east'"
    return 1
  fi
}

# fb_step_7_resume_connectors -- Resume only previously-RUNNING connectors
fb_step_7_resume_connectors() {
  if [ "${DRY_RUN}" = true ]; then
    local connector_json running_count
    connector_json=$(curl -s "${FSI_CONNECT_URL}/connectors?expand=status" 2>/dev/null || echo "{}")
    running_count=$(echo "${connector_json}" | jq '[to_entries[] | select(.value.status.connector.state == "RUNNING")] | length' 2>/dev/null || echo "0")
    printf "%-6s %-30s %-40s %-30s\n" "7" "Resume Connectors" "Connectors paused in Step 2" "Resume RUNNING-only (${running_count})"
    echo ""
    echo "  [DRY-RUN] Would resume ${running_count} connectors (only those that were RUNNING)"
    return 0
  fi

  local running_names
  running_names=$(get_running_connectors)

  if [ -z "${running_names}" ]; then
    echo "  No connectors to resume (none were RUNNING before failback)."
    return 0
  fi

  local resumed_count=0
  for name in ${running_names}; do
    if resume_connector "${name}"; then
      ((resumed_count++))
    fi
  done

  echo "  Resumed ${resumed_count} connectors."
}

# fb_step_8_final_validation -- Verify East cluster is operational after failback
fb_step_8_final_validation() {
  if [ "${DRY_RUN}" = true ]; then
    printf "%-6s %-30s %-40s %-30s\n" "8" "Final Validation" "East cluster, topics R/W, Connect" "All verified healthy"
    echo ""
    echo "  [DRY-RUN] Would verify: East cluster writable, topics R/W (not mirroring), Connect running"
    return 0
  fi

  local pass=0 fail=0

  # Verify East cluster is accessible
  if confluent kafka cluster describe "${FSI_DR_CLUSTER_ID}" \
    --environment "${FSI_DR_ENV_ID}" -o json 2>/dev/null | jq -e . >/dev/null 2>&1; then
    echo "  PASS: East cluster accessible"
    ((pass++))
  else
    echo "  FAIL: East cluster not accessible"
    ((fail++))
  fi

  # Check Consul points to east
  local active_region
  active_region=$(consul kv get fsi/kafka/active-region 2>/dev/null || echo "unknown")
  if [ "${active_region}" = "east" ]; then
    echo "  PASS: Consul active-region is 'east'"
    ((pass++))
  else
    echo "  WARN: Consul active-region is '${active_region}', expected 'east'"
    ((fail++))
  fi

  # Check connector status
  local connector_json running_count
  connector_json=$(curl -s "${FSI_CONNECT_URL}/connectors?expand=status" 2>/dev/null || echo "{}")
  running_count=$(echo "${connector_json}" | jq '[to_entries[] | select(.value.status.connector.state == "RUNNING")] | length' 2>/dev/null || echo "0")
  echo "  INFO: ${running_count} connectors RUNNING"
  ((pass++))

  echo ""
  echo "  Validation: ${pass} passed, ${fail} failed"
  [ "${fail}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Failback command (8-step reverse sequence: restore East as primary)
# ---------------------------------------------------------------------------
cmd_failback() {
  echo "============================================"
  echo " FSI DR FAILBACK -- Restore East Primary"
  echo " Backend: ${FSI_DR_BACKEND}"
  if [ "${DRY_RUN}" = true ]; then
    echo " Mode: DRY-RUN (no changes will be made)"
  fi
  echo "============================================"
  echo ""

  # Pre-flight: East MUST be reachable (it's the failback target)
  echo "--- Pre-Flight Checks ---"
  if ! confluent kafka cluster describe "${FSI_DR_CLUSTER_ID}" \
    --environment "${FSI_DR_ENV_ID}" -o json 2>/dev/null | jq -e . >/dev/null 2>&1; then
    echo "  FAIL: East (production) cluster is not reachable. Cannot failback."
    echo "  Wait for East cluster recovery before retrying."
    exit 1
  fi
  echo "  PASS: East cluster reachable"

  # Check West (current primary) is still reachable
  if ! confluent kafka cluster describe "${FSI_DR_DR_CLUSTER_ID}" \
    --environment "${FSI_DR_DR_ENV_ID}" -o json 2>/dev/null | jq -e . >/dev/null 2>&1; then
    echo "  FAIL: West (current active) cluster is not reachable."
    exit 1
  fi
  echo "  PASS: West cluster reachable"
  echo ""

  # Dry-run table header
  if [ "${DRY_RUN}" = true ]; then
    echo "--- Dry-Run Plan ---"
    printf "%-6s %-30s %-40s %-30s\n" "STEP" "ACTION" "CURRENT STATE" "EXPECTED RESULT"
    printf "%-6s %-30s %-40s %-30s\n" "----" "------" "-------------" "---------------"
  fi

  # Confirmation (per D-10)
  if [ "${DRY_RUN}" = false ]; then
    confirm_proceed "Execute failback sequence? (This will restore East as primary)"
    init_state "failback"
  fi

  # Execute 8 failback steps
  local step_funcs=("fb_step_1_verify_east" "fb_step_2_pause_connectors" "fb_step_3_truncate_and_restore" "fb_step_4_wait_for_sync" "fb_step_5_reverse_and_start" "fb_step_6_flip_consul" "fb_step_7_resume_connectors" "fb_step_8_final_validation")
  local step_names=("verify_east" "pause_connectors" "truncate_and_restore" "wait_for_sync" "reverse_and_start" "flip_consul" "resume_connectors" "final_validation")

  for i in "${!step_funcs[@]}"; do
    local step_num=$((i + 1))
    local step_func="${step_funcs[$i]}"
    local step_name="${step_names[$i]}"

    echo ""
    echo "--- Step ${step_num}/8: ${step_name} ---"

    if ! ${step_func}; then
      if [ "${DRY_RUN}" = false ]; then
        update_state "status" "failed"
        print_failback_rollback_instructions "${step_num}"
      fi
      exit 1
    fi

    if [ "${DRY_RUN}" = false ]; then
      record_step "${step_num}" "${step_name}"
    fi
  done

  echo ""
  if [ "${DRY_RUN}" = true ]; then
    echo "============================================"
    echo " DRY-RUN COMPLETE -- No changes were made"
    echo "============================================"
  else
    cleanup_state
    echo "============================================"
    echo " FAILBACK COMPLETE"
    echo " Active region: east (primary)"
    echo " West cluster: DR passive (mirroring)"
    echo "============================================"
  fi
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

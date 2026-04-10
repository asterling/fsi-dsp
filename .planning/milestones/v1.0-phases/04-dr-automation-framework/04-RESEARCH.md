# Phase 4: DR Automation Framework - Research

**Researched:** 2026-03-23
**Domain:** Bash CLI orchestration, Confluent Cluster Linking DR, Kafka Connect REST API, Consul KV service discovery
**Confidence:** HIGH

## Summary

Phase 4 replaces 6+ manual DR scripts with a unified `fsi-dr.sh` Bash CLI that orchestrates single-command failover/failback with dry-run preview, state validation between steps, rollback guidance on failure, and mirror lag monitoring with SLA-tier-based assessment. The phase delivers the Cluster Linking backend adapter for Confluent Cloud deployments only; MirrorMaker 2 adapter is deferred to Phase 8.

The existing codebase provides four discrete scripts (`mirror-failover.sh`, `mirror-failback.sh`, `consul-flip-region.sh`, `connect-pause-all.sh`) that form the operational core. These scripts already use `confluent` CLI, `consul` CLI, and `curl` for Connect REST API -- all with `set -euo pipefail` strict error handling. The `fsi-dr.sh` CLI will extract logic from these scripts into function-dispatched steps, adding state tracking, pre-flight checks, dry-run mode, and SLA-tier-aware mirror lag assessment.

The Confluent CLI provides built-in `--dry-run` flags on `mirror failover`, `mirror promote`, `mirror truncate-and-restore`, and `mirror reverse-and-start` commands, which directly enables the DR-09 dry-run requirement. Mirror lag is available per-topic via `confluent kafka mirror list --link X -o json` and per-partition via `confluent kafka mirror describe <topic> --link X -o json`. SLA tier thresholds from ADR-008 (critical: alert at 60s, standard: alert at 15m, best-effort: alert at 4h, compliance: alert at 30s) are well-defined and feed directly into the status and pre-flight check implementations.

**Primary recommendation:** Build `scripts/fsi-dr.sh` as a single self-contained Bash script with function dispatch per backend (cluster-linking functions for Phase 4), JSON state file management via `jq`, and the six-step failover sequence from the existing runbook. Create `docs/dr-runbook.md` as a standalone decision-tree reference. Add `tests/` directory with shell-based validation tests for the CLI.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Bash wrapper script (`scripts/fsi-dr.sh`) that orchestrates the existing individual scripts into a unified CLI. Same toolchain as existing DR scripts (confluent CLI + consul + curl).
- **D-02:** Three commands: `fsi-dr failover`, `fsi-dr failback`, `fsi-dr status`. No preflight or drill commands in this phase.
- **D-03:** Pluggable backend via function dispatch -- `FSI_DR_BACKEND=cluster-linking` env var selects backend-specific functions within the same script. Easy to add `mm2` functions in Phase 8 without restructuring.
- **D-04:** Configuration via environment variables following existing pattern (FSI_DR_ENV_ID, FSI_DR_CLUSTER_ID, FSI_CONNECT_URL, CONSUL_HTTP_ADDR, FSI_CLUSTER_LINK_NAME). Operators source a .env file or export vars.
- **D-05:** Six-step failover sequence: (1) Pause connectors, (2) Promote mirrors, (3) Flip Consul, (4) Verify endpoints, (5) Resume connectors, (6) Final validation. Matches existing runbook.
- **D-06:** On step failure: halt immediately, report which step failed and current state, print rollback instructions for operator. No automatic rollback -- too dangerous for production DR.
- **D-07:** State file in `/tmp/fsi-dr-state.json` tracks: timestamp, operation (failover/failback), steps completed, connectors paused (names + prior states), topics promoted. Cleaned up on success. Enables `fsi-dr status` to show in-progress failover state.
- **D-08:** Connect state tracking (DR-12): before pausing, snapshot each connector's current state (RUNNING/PAUSED/FAILED) to state file. After failover, resume only connectors that were RUNNING. Prevents accidentally starting intentionally-paused connectors.
- **D-09:** `fsi-dr failover --dry-run` outputs step-by-step plan with current actual state per step (e.g., "Step 2: Promote 12 mirror topics [lag: 2s avg, 8s max]"). Table format: step number, action, current state, expected result.
- **D-10:** Always require confirmation before executing (prompt: "Proceed? (yes/no)"). `--force` flag skips confirmation for CI/automation use.
- **D-11:** Full pre-flight suite runs automatically before failover starts (even without --dry-run): (1) both clusters reachable, (2) mirrors active on DR cluster, (3) mirror lag within SLA tier thresholds, (4) Connect API reachable, (5) Consul reachable. Fail if any critical check fails; warn on non-critical.
- **D-12:** Separate DR runbook document (`docs/dr-runbook.md`) with decision trees, success/abort criteria per step, rollback guidance. Human-readable for on-call engineers. References fsi-dr commands but stands alone.
- **D-13:** Confluent CLI polling for mirror lag data -- `confluent kafka mirror list --link X -o json` for per-topic mirror status. Same tool already used in existing scripts.
- **D-14:** `fsi-dr status` displays per-topic table: topic name | SLA tier | current lag | threshold | status (OK/WARN/ALERT). Summary line: "12 topics OK, 1 WARN, 0 ALERT".
- **D-15:** SLA tier lookup via Confluent Cloud topic metadata tags (set by topic module). `confluent kafka topic describe X -o json` includes `sla-tier` tag. No external config file needed.
- **D-16:** When mirror lag exceeds SLA tier alert threshold during failover: warn with per-topic data loss estimate but allow operator to proceed. DR is an emergency -- blocking could delay recovery. Print: "WARNING: N topics exceed RPO threshold. Proceed? (yes/no)".

### Claude's Discretion
- State file JSON schema and cleanup strategy
- Exact pre-flight check ordering and error message formatting
- Failback step sequence (reverse of failover with appropriate modifications)
- How `fsi-dr status` handles unreachable clusters gracefully
- Color coding for terminal output (OK/WARN/ALERT)
- Whether existing individual scripts are refactored into fsi-dr.sh or kept as-is alongside it

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| DR-01 | Single-command failover orchestrates all DR steps | Six-step failover sequence (D-05) implemented as `fsi-dr failover` with function dispatch per step. Confluent CLI `mirror failover` handles promotion. Connect REST API handles pause/resume. Consul KV handles endpoint flip. |
| DR-02 | Single-command failback automates reverse replication, mirror re-establishment, cutover | Failback uses `confluent kafka mirror truncate-and-restore` then `reverse-and-start` CLI commands. Consul flip back to east. Connect resume from state file. |
| DR-03 | Pluggable DR backend abstraction provides unified CLI | Function dispatch pattern: `FSI_DR_BACKEND=cluster-linking` selects `cl_*` prefixed functions. Phase 8 adds `mm2_*` functions. Same CLI interface regardless of backend. |
| DR-04 | Cluster Linking adapter handles CC-native failover/failback | Full Confluent CLI command set verified: `mirror failover`, `mirror list`, `mirror describe`, `mirror truncate-and-restore`, `mirror reverse-and-start`. All support `-o json` and `--dry-run`. |
| DR-07 | Mirror lag monitoring with SLA-tier-based alert thresholds | `confluent kafka mirror list --link X -o json` provides per-topic lag. `confluent kafka mirror describe <topic> --link X -o json` provides per-partition lag. ADR-008 defines thresholds: critical 60s, standard 15m, best-effort 4h, compliance 30s. |
| DR-08 | State validation between failover steps verifies preconditions | Pre-flight suite (D-11) validates cluster reachability, mirror status, lag thresholds, Connect API, Consul. State file tracks step completion for resumability. |
| DR-09 | Dry-run mode previews all DR operations without executing | Confluent CLI `--dry-run` flag on failover/promote/truncate-and-restore/reverse-and-start. Connect and Consul steps report current state without modification. |
| DR-10 | Rollback capability reverts partial failover to safe state | On failure: halt, report step + state, print rollback instructions (D-06). State file records what was done for manual or guided rollback. No auto-rollback per user decision. |
| DR-11 | Unified DR runbook with decision trees and rollback guidance | `docs/dr-runbook.md` standalone document. References fsi-dr commands. Decision trees for go/no-go at each step. Success/abort criteria. |
| DR-12 | Connect state tracking records connector states for correct resume | Snapshot connector states (RUNNING/PAUSED/FAILED) to state file before pause (D-08). Resume only previously-RUNNING connectors. Uses Connect REST API `GET /connectors?expand=status`. |
</phase_requirements>

## Standard Stack

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| Bash | 5.x (macOS ships 3.2, but `#!/usr/bin/env bash` works) | Script runtime | All existing scripts are Bash; consistency with codebase |
| jq | 1.6+ | JSON parsing and state file manipulation | Already used in existing scripts (`jq -r`); standard for CLI JSON processing |
| confluent CLI | Current (2.x) | Kafka mirror management, topic describe, cluster operations | Already used in existing DR scripts; provides `--dry-run` and `-o json` on all mirror commands |
| curl | 7.x | Kafka Connect REST API, Consul HTTP API | Already used in existing scripts; standard HTTP client |
| consul CLI | 1.x | Consul KV put/get for region flip | Already used in `consul-flip-region.sh`; provides both CLI and HTTP API |

### Supporting
| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| dig | System | DNS resolution verification after Consul flip | Post-flip endpoint verification (Step 4) |
| column | System | Table formatting for status output | `fsi-dr status` table display |
| tput | System | Terminal color codes for OK/WARN/ALERT | Color-coded status output (if terminal supports it) |
| date | System | ISO timestamps for state file entries | State file timestamp tracking |
| mktemp | System | Atomic temp file for safe JSON writes | State file write pattern |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Bash | Python | More testable, but breaks consistency with existing scripts; adds Python dependency to ops scripts |
| jq | Python json module | Same tradeoff; jq is already established in the codebase |
| /tmp state file | SQLite | Persistent but over-engineered; /tmp is appropriate for ephemeral operation state |

**Installation:** No new packages required. All tools (bash, jq, curl, confluent CLI, consul CLI) are already dependencies of the existing DR scripts.

**Version verification:** Not applicable -- tools are system-level CLIs, not package dependencies.

## Architecture Patterns

### Recommended Project Structure
```
scripts/
  fsi-dr.sh                  # Main unified CLI script
  mirror-failover.sh          # Kept as-is for backward compatibility
  mirror-failback.sh          # Kept as-is for backward compatibility
  consul-flip-region.sh       # Kept as-is for backward compatibility
  connect-pause-all.sh        # Kept as-is for backward compatibility
  validate-apply.sh           # Existing post-apply validation

docs/
  dr-runbook.md               # New: standalone DR runbook with decision trees

tests/
  dr/
    test-fsi-dr-helpers.sh    # Unit tests for pure functions (threshold checks, state file ops)
    test-fsi-dr-dry-run.sh    # Dry-run output validation with mocked CLI responses
```

### Pattern 1: Function Dispatch by Backend
**What:** Environment variable `FSI_DR_BACKEND` selects which set of functions handle mirror operations. Default: `cluster-linking`. Each backend implements a standard set of functions: `backend_preflight`, `backend_failover_mirrors`, `backend_failback_mirrors`, `backend_get_mirror_lag`, `backend_get_mirror_status`.
**When to use:** Always -- this is the pluggable abstraction for DR-03.
**Example:**
```bash
# Function dispatch pattern
FSI_DR_BACKEND="${FSI_DR_BACKEND:-cluster-linking}"

# Source backend-specific functions
case "${FSI_DR_BACKEND}" in
  cluster-linking)
    # Cluster Linking functions defined inline (Phase 4)
    cl_preflight() { ... }
    cl_failover_mirrors() { ... }
    cl_failback_mirrors() { ... }
    cl_get_mirror_lag() { ... }
    cl_get_mirror_status() { ... }

    backend_preflight()        { cl_preflight "$@"; }
    backend_failover_mirrors() { cl_failover_mirrors "$@"; }
    backend_failback_mirrors() { cl_failback_mirrors "$@"; }
    backend_get_mirror_lag()   { cl_get_mirror_lag "$@"; }
    backend_get_mirror_status(){ cl_get_mirror_status "$@"; }
    ;;
  mm2)
    echo "ERROR: MirrorMaker 2 backend not yet implemented (Phase 8)"
    exit 1
    ;;
  *)
    echo "ERROR: Unknown backend: ${FSI_DR_BACKEND}. Supported: cluster-linking"
    exit 1
    ;;
esac
```

### Pattern 2: State File for Operation Tracking
**What:** JSON state file at `/tmp/fsi-dr-state.json` tracks in-progress DR operations. Written atomically via temp file + mv. Cleaned up on successful completion.
**When to use:** Every failover/failback operation writes state; `fsi-dr status` reads it; resume-after-failure reads it.
**Example:**
```bash
STATE_FILE="/tmp/fsi-dr-state.json"

# Initialize state file atomically
init_state() {
  local operation="$1"
  local tmp
  tmp=$(mktemp "${STATE_FILE}.XXXXXX")
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
    }' > "${tmp}" && mv "${tmp}" "${STATE_FILE}"
}

# Record step completion
record_step() {
  local step_num="$1" step_name="$2"
  local tmp
  tmp=$(mktemp "${STATE_FILE}.XXXXXX")
  jq \
    --arg num "${step_num}" \
    --arg name "${step_name}" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '.steps_completed += [{step: ($num | tonumber), name: $name, completed: $ts}]
     | .current_step = ($num | tonumber)' \
    "${STATE_FILE}" > "${tmp}" && mv "${tmp}" "${STATE_FILE}"
}
```

### Pattern 3: Pre-Flight Check Suite
**What:** Series of checks that run before any destructive operation. Each check returns pass/fail/warn. All critical checks must pass; warns are reported but do not block.
**When to use:** Before failover and failback execution (D-11).
**Example:**
```bash
preflight_check() {
  local pass=0 warn=0 fail=0

  # Check 1: Both clusters reachable
  if confluent kafka cluster describe --cluster "${PROD_CLUSTER_ID}" &>/dev/null; then
    echo "  PASS: Production cluster reachable"
    ((pass++))
  else
    echo "  WARN: Production cluster unreachable (expected during DR)"
    ((warn++))
  fi

  if confluent kafka cluster describe --cluster "${DR_CLUSTER_ID}" &>/dev/null; then
    echo "  PASS: DR cluster reachable"
    ((pass++))
  else
    echo "  FAIL: DR cluster unreachable"
    ((fail++))
  fi

  # Check 2: Mirrors active on DR cluster
  local mirror_count
  mirror_count=$(confluent kafka mirror list --link "${LINK_NAME}" \
    --mirror-status active -o json --cluster "${DR_CLUSTER_ID}" \
    | jq 'length')
  if [ "${mirror_count}" -gt 0 ]; then
    echo "  PASS: ${mirror_count} active mirrors found"
    ((pass++))
  else
    echo "  FAIL: No active mirrors on DR cluster"
    ((fail++))
  fi

  # Check 3: Mirror lag within thresholds (uses get_lag_assessment)
  # Check 4: Connect API reachable
  # Check 5: Consul reachable

  echo ""
  echo "Pre-flight: ${pass} passed, ${warn} warnings, ${fail} failed"
  [ "${fail}" -eq 0 ]  # Return non-zero if any critical check failed
}
```

### Pattern 4: Dry-Run Mode
**What:** When `--dry-run` flag is set, each step queries current state and reports what would happen without making changes. Uses Confluent CLI `--dry-run` where available; skips mutation calls for Connect/Consul steps.
**When to use:** `fsi-dr failover --dry-run` (DR-09).
**Example:**
```bash
DRY_RUN=false

# In step execution:
step_promote_mirrors() {
  local topics
  topics=$(confluent kafka mirror list --link "${LINK_NAME}" \
    --mirror-status active -o json --cluster "${DR_CLUSTER_ID}" \
    | jq -r '.[].mirror_topic_name')

  if [ "${DRY_RUN}" = true ]; then
    echo "  [DRY-RUN] Would promote $(echo "${topics}" | wc -w | tr -d ' ') mirror topics"
    # Show per-topic lag assessment
    for topic in ${topics}; do
      local lag tier threshold status
      lag=$(get_topic_lag "${topic}")
      tier=$(get_topic_sla_tier "${topic}")
      threshold=$(get_tier_threshold "${tier}")
      status=$(assess_lag "${lag}" "${threshold}")
      printf "    %-50s %-12s %8s / %8s  %s\n" "${topic}" "${tier}" "${lag}s" "${threshold}s" "${status}"
    done
  else
    # shellcheck disable=SC2086
    confluent kafka mirror failover ${topics} --link "${LINK_NAME}" -o json
  fi
}
```

### Anti-Patterns to Avoid
- **Layered abstractions:** Do not create multiple script files that source each other in a chain. Keep all logic in `fsi-dr.sh` with functions -- single-file simplicity is critical for on-call engineers who need to read and debug during an outage.
- **Auto-rollback on failure:** Per D-06, do NOT implement automatic rollback. Print rollback instructions and let the operator decide. Automatic rollback during a DR event can compound failures.
- **Resume only RUNNING connectors:** Do not blindly `resume` all connectors after failover. Snapshot connector states before pause; only resume those that were RUNNING (D-08). This prevents starting intentionally-paused connectors.
- **Hardcoded thresholds:** SLA tier thresholds must come from ADR-008 definitions, not magic numbers scattered through the script. Define them once as constants.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Mirror topic promotion | Custom API calls to Kafka | `confluent kafka mirror failover` CLI | Handles partition-level promotion, offset management, link state transitions |
| Mirror lag measurement | Custom offset arithmetic | `confluent kafka mirror list -o json` + `mirror describe -o json` | CLI already calculates lag from partition offsets |
| Failback replication reversal | Manual topic recreation | `confluent kafka mirror truncate-and-restore` + `reverse-and-start` | Atomic operations that handle offset truncation and bidirectional link state |
| Connector state management | Direct Kafka Connect internal topics | Connect REST API (`/connectors/{name}/status`, `/pause`, `/resume`) | REST API is the stable interface; internal topics have undocumented schema |
| Service discovery flip | Multi-step DNS updates | `consul kv put fsi/kafka/active-region east\|west` | Single KV update flips three endpoints atomically |
| JSON state file manipulation | sed/awk on JSON | `jq` with `--arg` / `--argjson` and atomic write pattern | jq handles escaping, nested updates, type safety |
| Dry-run validation | Custom API mocking | `confluent kafka mirror failover --dry-run` (built-in) | Confluent CLI validates without executing |

**Key insight:** Every major operation in the failover/failback sequence has a well-tested CLI command or REST API. The value of `fsi-dr.sh` is orchestration and state tracking, not reimplementing any individual operation.

## Common Pitfalls

### Pitfall 1: Non-Atomic State File Writes
**What goes wrong:** Writing JSON directly to the state file can corrupt it if the script is interrupted mid-write (kill signal during DR, operator Ctrl+C).
**Why it happens:** Bash file writes are not atomic; `>` truncates then writes.
**How to avoid:** Always write to a temp file first, then `mv` to the target. `mv` on the same filesystem is atomic. Use `mktemp "${STATE_FILE}.XXXXXX"` to create the temp in the same directory.
**Warning signs:** Corrupted JSON in state file; `jq` parse errors when reading state.

### Pitfall 2: Resuming Intentionally-Paused Connectors
**What goes wrong:** After failover, blindly resuming all connectors starts connectors that were intentionally paused (maintenance, deprecated, failing).
**Why it happens:** The current `connect-pause-all.sh` has no state tracking -- it pauses all and resumes all.
**How to avoid:** Snapshot each connector's state via `GET /connectors?expand=status` before pausing. Store in state file. Resume only connectors whose prior state was `RUNNING` (D-08).
**Warning signs:** Connectors running after failover that weren't running before.

### Pitfall 3: Mirror Lag Exceeds RPO During Failover
**What goes wrong:** Operator triggers failover without checking mirror lag, resulting in data loss beyond RPO targets.
**Why it happens:** Mirror lag is typically seconds but can spike during network issues or high throughput.
**How to avoid:** Pre-flight check assesses lag per SLA tier. If critical topics exceed threshold (60s per ADR-008), warn with per-topic data loss estimate. Allow operator to proceed (DR is an emergency) but make them explicitly acknowledge (D-16).
**Warning signs:** Mirror lag increasing in `fsi-dr status` output; WARN/ALERT status on critical topics.

### Pitfall 4: Confluent CLI Context Leakage
**What goes wrong:** `confluent environment use` and `confluent kafka cluster use` commands set global CLI context, causing subsequent commands to target wrong cluster.
**Why it happens:** The `confluent` CLI uses a global context file (~/.confluent/config.json). If failover targets the DR cluster but a subsequent command forgets to re-set context, it operates on the wrong cluster.
**How to avoid:** Always pass `--environment` and `--cluster` flags explicitly on every command rather than relying on `confluent environment use` / `confluent kafka cluster use`. Alternatively, set context once at script start and verify before each step.
**Warning signs:** Commands returning unexpected results; topic not found errors on correct cluster.

### Pitfall 5: Failback Without Verifying Data Sync
**What goes wrong:** `truncate-and-restore` is executed before verifying that all post-failover data has been replicated back to East, resulting in data loss.
**Why it happens:** Operator is in a hurry to restore normal operations.
**How to avoid:** After failover, before failback, verify mirror lag from West to East is zero (or near zero). The failback pre-flight check must validate this. `truncate-and-restore` is destructive -- it truncates data on the target.
**Warning signs:** Non-zero mirror lag when failback is initiated; `truncate-and-restore --dry-run` showing non-trivial truncation counts.

### Pitfall 6: Consul KV Update Without DNS Propagation Check
**What goes wrong:** Consul KV is updated but applications don't pick up the new endpoints immediately due to DNS caching or Consul DNS TTL.
**Why it happens:** Consul DNS has configurable TTL; some clients cache DNS results.
**How to avoid:** After Consul KV flip, verify endpoint resolution via `dig` or `consul catalog` before proceeding. Add a verification loop with timeout.
**Warning signs:** Applications still connecting to old cluster after Consul flip; DNS returning stale IPs.

### Pitfall 7: Connect REST API Timeout During Pause
**What goes wrong:** Some connectors take time to pause (especially JDBC connectors with long poll intervals). The script moves to the next step before all connectors are actually paused.
**Why it happens:** `PUT /connectors/{name}/pause` returns `202 Accepted` asynchronously. The connector transitions to PAUSED state over time, not immediately.
**How to avoid:** After issuing pause, poll `GET /connectors/{name}/status` until all targeted connectors report `state: PAUSED` or a timeout is reached. Use a configurable timeout (default: 60s).
**Warning signs:** Connector status checks showing RUNNING after pause was issued.

## Code Examples

Verified patterns from official sources:

### Confluent CLI: List Active Mirrors with JSON Output
```bash
# Source: Confluent CLI docs - confluent kafka mirror list
# Returns JSON array of mirror topics with status
confluent kafka mirror list \
  --link "${LINK_NAME}" \
  --mirror-status active \
  --cluster "${DR_CLUSTER_ID}" \
  --environment "${DR_ENV_ID}" \
  -o json
```

### Confluent CLI: Failover Mirror Topics
```bash
# Source: Confluent CLI docs - confluent kafka mirror failover
# Failover = DR emergency (does not wait for lag=0)
# Promote = Planned migration (waits for lag=0, does final sync)
# For DR, always use failover, not promote
confluent kafka mirror failover topic1 topic2 topic3 \
  --link "${LINK_NAME}" \
  --cluster "${DR_CLUSTER_ID}" \
  --environment "${DR_ENV_ID}" \
  -o json
```

### Confluent CLI: Failover Dry-Run
```bash
# Source: Confluent CLI docs - confluent kafka mirror failover --dry-run
# Validates without executing
confluent kafka mirror failover topic1 topic2 \
  --link "${LINK_NAME}" \
  --dry-run \
  -o json
```

### Confluent CLI: Failback Step 1 -- Truncate and Restore
```bash
# Source: Confluent CLI docs - confluent kafka mirror truncate-and-restore
# Makes East topics into mirrors, copies data from West
# DESTRUCTIVE: truncates East topic data first
# Only available on bidirectional links in KRaft mode
confluent kafka mirror truncate-and-restore topic1 topic2 \
  --link "${LINK_NAME}" \
  --cluster "${PROD_CLUSTER_ID}" \
  --environment "${PROD_ENV_ID}" \
  -o json
```

### Confluent CLI: Failback Step 2 -- Reverse and Start
```bash
# Source: Confluent CLI docs - confluent kafka mirror reverse-and-start
# East becomes R/W (normal), West becomes mirror again
confluent kafka mirror reverse-and-start topic1 topic2 \
  --link "${LINK_NAME}" \
  --cluster "${PROD_CLUSTER_ID}" \
  --environment "${PROD_ENV_ID}" \
  -o json
```

### Confluent CLI: Describe Mirror Topic (Per-Partition Lag)
```bash
# Source: Confluent CLI docs - confluent kafka mirror describe
# Shows per-partition lag, last source fetch offset, status time
confluent kafka mirror describe "${TOPIC}" \
  --link "${LINK_NAME}" \
  --cluster "${DR_CLUSTER_ID}" \
  --environment "${DR_ENV_ID}" \
  -o json
```

### Connect REST API: Snapshot Connector States
```bash
# Source: Confluent Platform Connect REST API docs
# Get all connectors with status in a single call
CONNECT_URL="${FSI_CONNECT_URL:-http://localhost:8083}"

# Returns: {"connector-name": {"status": {"connector": {"state": "RUNNING"}, "tasks": [...]}}}
curl -s "${CONNECT_URL}/connectors?expand=status" | jq '{
  connectors: [
    to_entries[] | {
      name: .key,
      state: .value.status.connector.state,
      tasks: [.value.status.tasks[]? | {id: .id, state: .state}]
    }
  ]
}'
```

### Connect REST API: Pause with State Tracking
```bash
# Source: Confluent Platform Connect REST API docs
# Pause a single connector (returns 202 Accepted, async)
curl -s -X PUT "${CONNECT_URL}/connectors/${CONNECTOR_NAME}/pause"

# Verify pause completed
# Poll until state is PAUSED (async operation)
for i in $(seq 1 30); do
  STATE=$(curl -s "${CONNECT_URL}/connectors/${CONNECTOR_NAME}/status" \
    | jq -r '.connector.state')
  if [ "${STATE}" = "PAUSED" ]; then
    echo "  ${CONNECTOR_NAME}: PAUSED"
    break
  fi
  sleep 2
done
```

### Consul KV: Atomic Region Flip
```bash
# Source: HashiCorp Consul KV HTTP API docs
# Single KV update flips Kafka, SR, and Oracle endpoints
consul kv put fsi/kafka/active-region "${TARGET_REGION}"

# Verify via CLI
ACTIVE=$(consul kv get fsi/kafka/active-region)
echo "Active region: ${ACTIVE}"

# Verify via DNS resolution
dig +short kafka.fsi.internal
dig +short schema.fsi.internal
dig +short oracle.fsi.internal
```

### SLA Tier Threshold Constants
```bash
# Source: ADR-008 DR Tier Classification
# Define once, reference everywhere
declare -A TIER_WARN_THRESHOLD_SEC=(
  [critical]=30
  [standard]=300     # 5 minutes
  [best-effort]=3600 # 1 hour
  [compliance]=10
)

declare -A TIER_ALERT_THRESHOLD_SEC=(
  [critical]=60
  [standard]=900     # 15 minutes
  [best-effort]=14400 # 4 hours
  [compliance]=30
)

assess_lag() {
  local lag_sec="$1" tier="$2"
  local warn="${TIER_WARN_THRESHOLD_SEC[$tier]}"
  local alert="${TIER_ALERT_THRESHOLD_SEC[$tier]}"

  if [ "${lag_sec}" -ge "${alert}" ]; then
    echo "ALERT"
  elif [ "${lag_sec}" -ge "${warn}" ]; then
    echo "WARN"
  else
    echo "OK"
  fi
}
```

### Atomic State File Write Pattern
```bash
# Source: Bash best practices for JSON file manipulation
# Write to temp file in same directory, then atomic mv
update_state() {
  local key="$1" value="$2"
  local tmp
  tmp=$(mktemp "${STATE_FILE}.XXXXXX")
  jq --arg k "${key}" --arg v "${value}" \
    '.[$k] = $v' "${STATE_FILE}" > "${tmp}" && mv "${tmp}" "${STATE_FILE}"
}

# For complex updates
update_state_json() {
  local jq_filter="$1"
  shift
  local tmp
  tmp=$(mktemp "${STATE_FILE}.XXXXXX")
  jq "${jq_filter}" "$@" "${STATE_FILE}" > "${tmp}" && mv "${tmp}" "${STATE_FILE}"
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual 6-step runbook | Single `fsi-dr failover` command | This phase | RTO reduction: operator executes one command instead of six scripts in sequence |
| No pre-flight validation | Automated pre-flight suite | This phase | Catches configuration issues before destructive operations begin |
| No state tracking for connectors | Snapshot/restore connector states | This phase | Prevents resuming intentionally-paused connectors |
| `confluent environment use` (global context) | Explicit `--environment` + `--cluster` flags per command | This phase | Eliminates CLI context leakage between clusters |
| Hardcoded lag thresholds | SLA-tier-driven thresholds from ADR-008 | This phase | Tier-appropriate alerting: critical at 60s, standard at 15m |

**Deprecated/outdated:**
- `confluent kafka mirror promote` should NOT be used for DR failover. Use `confluent kafka mirror failover` instead. Promote waits for lag=0 (planned migration); failover acts immediately (emergency DR).

## Open Questions

1. **Mirror lag JSON field names from CLI**
   - What we know: `confluent kafka mirror list -o json` and `confluent kafka mirror describe -o json` return JSON with lag information
   - What's unclear: Exact field names in JSON output (e.g., `mirror_lag_ms` vs `partition_mirror_lag` vs `num_messages_lag`). The official docs do not publish JSON schemas for CLI output.
   - Recommendation: During implementation, run the actual CLI commands against a live or test cluster with `-o json` and inspect the output to determine exact field names. Build a `parse_mirror_lag()` function that can be adjusted if field names differ from expectations.

2. **Topic metadata tag retrieval via CLI**
   - What we know: `confluent kafka topic describe X -o json` should include metadata tags set by the topic module (including `sla-tier`)
   - What's unclear: Whether topic-level tags set via Terraform `confluent_schema` metadata properties appear in `confluent kafka topic describe` output, or only in Schema Registry metadata. Tags may be on the schema subject, not the topic itself.
   - Recommendation: The SLA tier is set in schema metadata (`local.schema_metadata` in `modules/topic/main.tf`). If `confluent kafka topic describe` does not expose `sla-tier`, fall back to `confluent schema-registry subject describe` or use `confluent kafka topic describe` to get the topic name, then look up the corresponding schema subject metadata. Include a `get_topic_sla_tier()` function that encapsulates this lookup.

3. **State file location for non-tmp scenarios**
   - What we know: D-07 specifies `/tmp/fsi-dr-state.json`
   - What's unclear: `/tmp` is cleared on reboot on some systems. If operator reboots during a partial failover, the state file is lost.
   - Recommendation: Use `/tmp` as specified but document this limitation in the runbook. Operators can override via `FSI_DR_STATE_FILE` env var. The state file is primarily for same-session tracking, not cross-reboot persistence.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Bash functions with assertion helpers (no external framework) |
| Config file | None -- self-contained test scripts |
| Quick run command | `bash tests/dr/test-fsi-dr-helpers.sh` |
| Full suite command | `bash tests/dr/test-fsi-dr-helpers.sh && bash tests/dr/test-fsi-dr-dry-run.sh` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| DR-01 | Failover sequence executes 6 steps in order | integration (requires live cluster) | manual-only: requires Confluent Cloud + Consul | N/A |
| DR-03 | Backend dispatch selects correct function set | unit | `bash tests/dr/test-fsi-dr-helpers.sh` | Wave 0 |
| DR-07 | SLA tier threshold assessment returns correct OK/WARN/ALERT | unit | `bash tests/dr/test-fsi-dr-helpers.sh` | Wave 0 |
| DR-08 | State file tracks steps, connectors, topics | unit | `bash tests/dr/test-fsi-dr-helpers.sh` | Wave 0 |
| DR-09 | Dry-run output format correct without state change | unit (mocked) | `bash tests/dr/test-fsi-dr-dry-run.sh` | Wave 0 |
| DR-10 | Rollback instructions printed on step failure | unit (mocked) | `bash tests/dr/test-fsi-dr-helpers.sh` | Wave 0 |
| DR-12 | Connector state snapshot captures RUNNING/PAUSED/FAILED | unit (mocked) | `bash tests/dr/test-fsi-dr-helpers.sh` | Wave 0 |

### Sampling Rate
- **Per task commit:** `bash tests/dr/test-fsi-dr-helpers.sh`
- **Per wave merge:** `bash tests/dr/test-fsi-dr-helpers.sh && bash tests/dr/test-fsi-dr-dry-run.sh`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `tests/dr/test-fsi-dr-helpers.sh` -- unit tests for pure functions (threshold assessment, state file ops, backend dispatch)
- [ ] `tests/dr/test-fsi-dr-dry-run.sh` -- dry-run output validation with mocked CLI responses
- [ ] `tests/dr/` directory -- needs creation

Note: Full end-to-end DR failover testing requires live Confluent Cloud clusters and Consul infrastructure. Unit tests focus on pure functions (threshold math, state file manipulation, output formatting) that can be tested without external dependencies. The runbook (DR-11) serves as the human validation checklist for live-fire DR drills.

## Sources

### Primary (HIGH confidence)
- [Confluent CLI `confluent kafka mirror` command index](https://docs.confluent.io/confluent-cli/current/command-reference/kafka/mirror/index.html) -- all 12 subcommands verified: create, describe, failover, list, pause, promote, resume, reverse-and-pause, reverse-and-start, state-transition-error, truncate-and-restore
- [Confluent CLI `confluent kafka mirror failover`](https://docs.confluent.io/confluent-cli/current/command-reference/kafka/mirror/confluent_kafka_mirror_failover.html) -- `--dry-run`, `--link`, `-o json` flags verified
- [Confluent CLI `confluent kafka mirror list`](https://docs.confluent.io/confluent-cli/current/command-reference/kafka/mirror/confluent_kafka_mirror_list.html) -- `--mirror-status` filter, `-o json` verified
- [Confluent CLI `confluent kafka mirror describe`](https://docs.confluent.io/confluent-cli/current/command-reference/kafka/mirror/confluent_kafka_mirror_describe.html) -- per-partition lag info, `-o json` verified
- [Confluent CLI `confluent kafka mirror truncate-and-restore`](https://docs.confluent.io/confluent-cli/current/command-reference/kafka/mirror/confluent_kafka_mirror_truncate-and-restore.html) -- `--dry-run`, bidirectional link + KRaft requirement verified
- [Confluent CLI `confluent kafka mirror reverse-and-start`](https://docs.confluent.io/confluent-cli/current/command-reference/kafka/mirror/confluent_kafka_mirror_reverse-and-start.html) -- `--dry-run` flag verified
- [Confluent Platform Connect REST API](https://docs.confluent.io/platform/current/connect/references/restapi.html) -- `/connectors?expand=status`, pause/resume endpoints, JSON response format verified
- [Confluent Cloud Cluster Linking Metrics](https://docs.confluent.io/cloud/current/multi-cloud/cluster-linking/metrics-cc.html) -- `io.confluent.kafka.server/cluster_link_mirror_topic_offset_lag` metric
- [HashiCorp Consul KV HTTP API](https://developer.hashicorp.com/consul/api-docs/kv) -- PUT/GET/DELETE with base64 encoding, `?raw` flag
- Existing codebase: `scripts/mirror-failover.sh`, `scripts/mirror-failback.sh`, `scripts/consul-flip-region.sh`, `scripts/connect-pause-all.sh` -- established patterns verified
- ADR-005: Cluster Linking over MRC -- bidirectional link, 6-step failover, RPO characteristics
- ADR-008: DR Tier Classification -- SLA tier thresholds (critical 60s, standard 15m, best-effort 4h, compliance 30s)
- ADR-003: Consul Service Discovery -- single KV flip for atomic endpoint failover

### Secondary (MEDIUM confidence)
- [Confluent Cloud Mirror Topics Management](https://docs.confluent.io/cloud/current/multi-cloud/cluster-linking/mirror-topics-cc.html) -- failover vs promote semantics: failover acts immediately (DR), promote waits for lag=0 (migration)
- [Confluent Cloud DR Failover Guide](https://docs.confluent.io/cloud/current/multi-cloud/cluster-linking/dr-failover.html) -- bidirectional mode recommended for DR links

### Tertiary (LOW confidence)
- Mirror lag JSON output field names -- exact field names not documented in CLI reference; needs live verification during implementation

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all tools are already in use in existing scripts; no new dependencies
- Architecture: HIGH -- function dispatch, state file, pre-flight patterns are well-understood Bash idioms; Confluent CLI commands verified
- Pitfalls: HIGH -- derived from existing script analysis, Confluent docs, and Connect REST API behavior
- Mirror lag JSON fields: LOW -- official docs do not publish CLI JSON schemas; field names assumed from human-readable output

**Research date:** 2026-03-23
**Valid until:** 2026-04-23 (stable -- Confluent CLI commands are versioned and backward-compatible)

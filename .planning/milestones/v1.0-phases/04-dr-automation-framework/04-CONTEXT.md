# Phase 4: DR Automation Framework - Context

**Gathered:** 2026-03-23
**Status:** Ready for planning

<domain>
## Phase Boundary

Replace 6+ manual DR steps with a pluggable `fsi-dr` CLI that orchestrates single-command failover/failback with dry-run preview, state validation between steps, rollback guidance on failure, and mirror lag monitoring with SLA-tier-based assessment. Delivers the Cluster Linking backend adapter for CC deployments. MirrorMaker 2 adapter (CFK/CP) is Phase 8. Observability dashboard integration for mirror lag is Phase 5.

</domain>

<decisions>
## Implementation Decisions

### CLI Design & Invocation
- **D-01:** Bash wrapper script (`scripts/fsi-dr.sh`) that orchestrates the existing individual scripts into a unified CLI. Same toolchain as existing DR scripts (confluent CLI + consul + curl).
- **D-02:** Three commands: `fsi-dr failover`, `fsi-dr failback`, `fsi-dr status`. No preflight or drill commands in this phase.
- **D-03:** Pluggable backend via function dispatch -- `FSI_DR_BACKEND=cluster-linking` env var selects backend-specific functions within the same script. Easy to add `mm2` functions in Phase 8 without restructuring.
- **D-04:** Configuration via environment variables following existing pattern (FSI_DR_ENV_ID, FSI_DR_CLUSTER_ID, FSI_CONNECT_URL, CONSUL_HTTP_ADDR, FSI_CLUSTER_LINK_NAME). Operators source a .env file or export vars.

### Failover Orchestration
- **D-05:** Six-step failover sequence: (1) Pause connectors, (2) Promote mirrors, (3) Flip Consul, (4) Verify endpoints, (5) Resume connectors, (6) Final validation. Matches existing runbook.
- **D-06:** On step failure: halt immediately, report which step failed and current state, print rollback instructions for operator. No automatic rollback -- too dangerous for production DR.
- **D-07:** State file in `/tmp/fsi-dr-state.json` tracks: timestamp, operation (failover/failback), steps completed, connectors paused (names + prior states), topics promoted. Cleaned up on success. Enables `fsi-dr status` to show in-progress failover state.
- **D-08:** Connect state tracking (DR-12): before pausing, snapshot each connector's current state (RUNNING/PAUSED/FAILED) to state file. After failover, resume only connectors that were RUNNING. Prevents accidentally starting intentionally-paused connectors.

### Dry-Run & Safety
- **D-09:** `fsi-dr failover --dry-run` outputs step-by-step plan with current actual state per step (e.g., "Step 2: Promote 12 mirror topics [lag: 2s avg, 8s max]"). Table format: step number, action, current state, expected result.
- **D-10:** Always require confirmation before executing (prompt: "Proceed? (yes/no)"). `--force` flag skips confirmation for CI/automation use.
- **D-11:** Full pre-flight suite runs automatically before failover starts (even without --dry-run): (1) both clusters reachable, (2) mirrors active on DR cluster, (3) mirror lag within SLA tier thresholds, (4) Connect API reachable, (5) Consul reachable. Fail if any critical check fails; warn on non-critical.
- **D-12:** Separate DR runbook document (`docs/dr-runbook.md`) with decision trees, success/abort criteria per step, rollback guidance. Human-readable for on-call engineers. References fsi-dr commands but stands alone.

### Mirror Lag Monitoring
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

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### DR Architecture & Decisions
- `docs/adr/005-cluster-linking-over-mrc.md` -- Cluster Linking as DR backend for CC, RPO characteristics, bidirectional link pattern
- `docs/adr/008-dr-tier-classification.md` -- SLA tier RPO/RTO targets, mirror lag alert thresholds per tier, DR backend selection per deployment model
- `docs/adr/003-consul-service-discovery.md` -- Consul KV for atomic endpoint failover, single key flip for Kafka/SR/Oracle

### Existing DR Scripts (enhancement targets)
- `scripts/mirror-failover.sh` -- Current manual mirror promotion (Step 1 of 6). Uses confluent CLI to list and promote mirrors.
- `scripts/mirror-failback.sh` -- Current manual failback: truncate-and-restore + reverse-and-start. Two confirmation gates.
- `scripts/consul-flip-region.sh` -- Consul KV flip with endpoint verification via dig.
- `scripts/connect-pause-all.sh` -- Pause/resume all connectors via Connect REST API. No state tracking.

### Topic Module (metadata source)
- `modules/topic/main.tf` -- DR mirror topic creation via `confluent_kafka_mirror_topic`. Topic metadata tags including `sla-tier`.
- `modules/topic/variables.tf` -- `sla_tier` variable (critical/standard/best-effort/compliance) and `data_classification` variable.

### Prior Phase Context
- `.planning/phases/01-shared-governance-foundation/01-CONTEXT.md` -- Externalized cluster config, SLA tier as configuration driver
- `.planning/phases/02-cc-multi-cloud-scenarios/02-CONTEXT.md` -- Scenario directory structure, post-apply validation pattern
- `.planning/phases/03-access-control-and-compliance/03-CONTEXT.md` -- SA provisioning, CSFLE, compliance retention

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `scripts/mirror-failover.sh`: Mirror promotion logic using `confluent kafka mirror failover` + `confluent kafka mirror list`. Can be extracted into failover backend function.
- `scripts/mirror-failback.sh`: Failback with truncate-and-restore + reverse-and-start. Two-phase process with confirmation gates.
- `scripts/consul-flip-region.sh`: Consul KV put + DNS verification. Reusable as Consul flip step function.
- `scripts/connect-pause-all.sh`: Connect REST API pause/resume via curl. Needs state tracking enhancement.
- `scripts/validate-apply.sh`: Post-apply validation pattern from Phase 2 -- similar verification pattern usable for post-failover validation.

### Established Patterns
- `set -euo pipefail` strict error handling in all scripts
- Environment variables with `${VAR:?Set VAR}` for required config, `${VAR:-default}` for optional
- `confluent kafka mirror list --link X -o json | jq` for JSON parsing of CLI output
- `curl -s` for Connect REST API calls with `jq` for response parsing
- Interactive confirmation via `read -p "Proceed? (yes/no)"`

### Integration Points
- `scripts/fsi-dr.sh` -- New unified CLI script, orchestrates functions extracted from existing scripts
- `docs/dr-runbook.md` -- New runbook document with decision trees and rollback guidance
- Environment variables -- Extends existing FSI_DR_* and FSI_CONNECT_* patterns
- `/tmp/fsi-dr-state.json` -- New state file for in-progress DR operation tracking

</code_context>

<specifics>
## Specific Ideas

- The CLI should feel like running the existing scripts but automated -- same tools (confluent CLI, consul, curl), same confirmation pattern, just orchestrated.
- State file enables resumability: if operator re-runs after a failure, the CLI can show what already completed.
- Pre-flight checks should give operators confidence before they commit to the failover -- "everything is ready" vs "wait, fix this first".
- Mirror lag warning during failover should quantify potential data loss per topic so the operator can make an informed go/no-go decision.

</specifics>

<deferred>
## Deferred Ideas

None -- discussion stayed within phase scope

</deferred>

---

*Phase: 04-dr-automation-framework*
*Context gathered: 2026-03-23*

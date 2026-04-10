# Phase 4: DR Automation Framework - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md -- this log preserves the alternatives considered.

**Date:** 2026-03-23
**Phase:** 04-dr-automation-framework
**Areas discussed:** CLI design & invocation, Failover orchestration, Dry-run & safety, Mirror lag monitoring

---

## CLI Design & Invocation

### Language Choice

| Option | Description | Selected |
|--------|-------------|----------|
| Bash wrapper | Single bash script orchestrating existing scripts. Lowest effort, same toolchain. | ✓ |
| Python CLI | Click/argparse CLI. Better error handling, JSON parsing. Adds Python dependency. | |
| Go binary | Compiled binary, no runtime deps. Highest effort. | |

**User's choice:** Bash wrapper
**Notes:** Matches existing toolchain (confluent CLI + consul + curl). Operators already know the pattern.

### Command Set

| Option | Description | Selected |
|--------|-------------|----------|
| failover, failback, status | Core three commands. Clean and focused. | ✓ |
| Add preflight command | Plus standalone readiness check. | |
| Add drill command | Plus end-to-end DR test for compliance drills. | |

**User's choice:** failover, failback, status
**Notes:** None

### Backend Abstraction

| Option | Description | Selected |
|--------|-------------|----------|
| Function dispatch | Config value selects backend-specific functions within same script. | ✓ |
| Separate backend scripts | Separate files per backend, dispatcher selects. | |
| You decide | Claude picks. | |

**User's choice:** Function dispatch
**Notes:** Easy to add mm2 functions in Phase 8 without restructuring.

### Location & Config

| Option | Description | Selected |
|--------|-------------|----------|
| scripts/fsi-dr.sh + env vars | Single script, env var configuration. Same pattern as existing scripts. | ✓ |
| scripts/fsi-dr/ directory with config file | Directory with config file (YAML or INI). | |
| You decide | Claude picks. | |

**User's choice:** scripts/fsi-dr.sh + env vars
**Notes:** None

---

## Failover Orchestration

### Step Sequence

| Option | Description | Selected |
|--------|-------------|----------|
| Pause → Promote → Consul → Verify → Resume → Validate | Matches existing runbook. 6-step sequence. | ✓ |
| Promote → Consul → Pause+Resume (simplified) | Skip separate pause, apps error briefly. Faster but riskier. | |
| You decide | Claude determines safest ordering. | |

**User's choice:** Pause → Promote → Consul → Verify → Resume → Validate
**Notes:** Matches existing runbook exactly.

### Failure Handling

| Option | Description | Selected |
|--------|-------------|----------|
| Halt + report + manual rollback | Stop, report state, print rollback instructions. No auto-rollback. | ✓ |
| Halt + automatic rollback | Auto-reverse completed steps on failure. | |
| Halt + offer rollback | Stop, report, prompt operator for rollback decision. | |

**User's choice:** Halt + report + manual rollback
**Notes:** Too dangerous for production DR to auto-rollback.

### State Tracking

| Option | Description | Selected |
|--------|-------------|----------|
| State file in /tmp | JSON state file tracking steps, connectors, topics. Cleaned on success. | ✓ |
| Log-only tracking | Append to log file. Simpler but harder to parse. | |
| No state tracking | Each step independent. Simplest but can't resume. | |

**User's choice:** State file in /tmp
**Notes:** Enables fsi-dr status to show in-progress failover state.

### Connect State Tracking

| Option | Description | Selected |
|--------|-------------|----------|
| Record which were running, resume only those | Snapshot connector states before pause, resume only RUNNING. | ✓ |
| Pause all, resume all | Same as existing script. Might resume intentionally-paused connectors. | |
| Topic-filtered connectors | Only pause connectors referencing failed-over topics. Requires config parsing. | |

**User's choice:** Record which were running, resume only those
**Notes:** Prevents accidentally starting stopped connectors.

---

## Dry-Run & Safety

### Dry-Run Output

| Option | Description | Selected |
|--------|-------------|----------|
| Step-by-step plan with current state | Table: step number, action, current state, expected result. Per-topic lag. | ✓ |
| Minimal pass/fail readiness | Go/no-go check only. | |
| Full JSON report | Machine-readable JSON. Verbose but audit-friendly. | |

**User's choice:** Step-by-step plan with current state
**Notes:** None

### Confirmation Behavior

| Option | Description | Selected |
|--------|-------------|----------|
| Always confirm, --force to skip | Default: prompt. --force for CI/automation. Matches existing pattern. | ✓ |
| No confirmation, --confirm to require | Execute immediately by default. | |
| You decide | Claude picks. | |

**User's choice:** Always confirm, --force to skip
**Notes:** None

### Pre-Flight Checks

| Option | Description | Selected |
|--------|-------------|----------|
| Full pre-flight suite | 5 checks: clusters, mirrors, lag, Connect, Consul. Fail on critical. | ✓ |
| Minimal connectivity only | Just verify clusters and Consul reachable. | |
| You decide | Claude picks. | |

**User's choice:** Full pre-flight suite
**Notes:** None

### DR Runbook

| Option | Description | Selected |
|--------|-------------|----------|
| Separate runbook doc | docs/dr-runbook.md with decision trees, rollback guidance. | ✓ |
| CLI-generated runbook | fsi-dr generates runbook from step definitions. | |
| You decide | Claude picks. | |

**User's choice:** Separate runbook doc
**Notes:** Human-readable for on-call engineers.

---

## Mirror Lag Monitoring

### Lag Data Source

| Option | Description | Selected |
|--------|-------------|----------|
| Confluent CLI polling | confluent kafka mirror list for per-topic mirror status. Same tool as existing scripts. | ✓ |
| CC Metrics API | Query Metrics API for numeric lag values. Requires separate API credentials. | |
| Both sources | CLI for real-time, Metrics API for historical. | |

**User's choice:** Confluent CLI polling
**Notes:** None

### Lag Display

| Option | Description | Selected |
|--------|-------------|----------|
| Per-topic table with SLA assessment | Table: topic, tier, lag, threshold, status. Summary line. | ✓ |
| Aggregate summary only | Worst-case lag per SLA tier. Fewer lines. | |
| You decide | Claude picks. | |

**User's choice:** Per-topic table with SLA assessment
**Notes:** None

### SLA Tier Lookup

| Option | Description | Selected |
|--------|-------------|----------|
| Topic metadata tags | Read sla-tier from CC topic metadata. Set by topic module. No config file. | ✓ |
| Local config file | JSON/YAML mapping topics to tiers. Must stay in sync. | |
| Convention-based inference | Infer tier from topic name. Fragile. | |

**User's choice:** Topic metadata tags
**Notes:** None

### Lag Threshold Gating

| Option | Description | Selected |
|--------|-------------|----------|
| Warn with data loss estimate | Warn per-topic but allow proceed. DR is an emergency. | ✓ |
| Block unless --force | Refuse failover if critical topics exceed threshold. | |
| You decide | Claude picks. | |

**User's choice:** Warn with data loss estimate
**Notes:** Blocking could delay recovery in genuine emergencies.

---

## Claude's Discretion

- State file JSON schema and cleanup strategy
- Exact pre-flight check ordering and error message formatting
- Failback step sequence
- fsi-dr status handling of unreachable clusters
- Color coding for terminal output
- Whether existing scripts are refactored into fsi-dr.sh or kept alongside

## Deferred Ideas

None -- discussion stayed within phase scope

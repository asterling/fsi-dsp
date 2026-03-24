---
phase: 4
slug: dr-automation-framework
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-23
---

# Phase 4 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Bash functions with assertion helpers (no external framework) |
| **Config file** | None — self-contained test scripts |
| **Quick run command** | `bash tests/dr/test-fsi-dr-helpers.sh` |
| **Full suite command** | `bash tests/dr/test-fsi-dr-helpers.sh && bash tests/dr/test-fsi-dr-dry-run.sh` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run `bash tests/dr/test-fsi-dr-helpers.sh`
- **After every plan wave:** Run `bash tests/dr/test-fsi-dr-helpers.sh && bash tests/dr/test-fsi-dr-dry-run.sh`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 5 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 04-01-01 | 01 | 1 | DR-03 | unit | `bash tests/dr/test-fsi-dr-helpers.sh` | ❌ W0 | ⬜ pending |
| 04-01-02 | 01 | 1 | DR-08 | unit | `bash tests/dr/test-fsi-dr-helpers.sh` | ❌ W0 | ⬜ pending |
| 04-01-03 | 01 | 1 | DR-07 | unit | `bash tests/dr/test-fsi-dr-helpers.sh` | ❌ W0 | ⬜ pending |
| 04-02-01 | 02 | 1 | DR-01 | integration | manual-only: requires Confluent Cloud + Consul | N/A | ⬜ pending |
| 04-02-02 | 02 | 1 | DR-10 | unit | `bash tests/dr/test-fsi-dr-helpers.sh` | ❌ W0 | ⬜ pending |
| 04-02-03 | 02 | 1 | DR-12 | unit | `bash tests/dr/test-fsi-dr-helpers.sh` | ❌ W0 | ⬜ pending |
| 04-03-01 | 03 | 2 | DR-09 | unit (mocked) | `bash tests/dr/test-fsi-dr-dry-run.sh` | ❌ W0 | ⬜ pending |
| 04-03-02 | 03 | 2 | DR-04 | unit | `bash tests/dr/test-fsi-dr-helpers.sh` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `tests/dr/` directory — needs creation
- [ ] `tests/dr/test-fsi-dr-helpers.sh` — unit tests for pure functions (threshold assessment, state file ops, backend dispatch, rollback instructions, connector state snapshot)
- [ ] `tests/dr/test-fsi-dr-dry-run.sh` — dry-run output validation with mocked CLI responses

*Note: No external test framework needed — Bash assertion helpers are self-contained.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Full failover sequence (6 steps end-to-end) | DR-01 | Requires live Confluent Cloud clusters + Consul + Connect | Execute `fsi-dr failover` against staging DR environment; verify all 6 steps complete |
| Full failback sequence | DR-02 | Requires live clusters with bidirectional link | Execute `fsi-dr failback` after failover; verify replication re-established |
| Consul endpoint resolution after flip | DR-04 | Requires live Consul cluster with DNS | Run `dig kafka-bootstrap.service.consul` after Consul KV flip; verify new IP |
| DR runbook accuracy | DR-11 | Document review | Walk through `docs/dr-runbook.md` decision trees against live environment |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 5s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending

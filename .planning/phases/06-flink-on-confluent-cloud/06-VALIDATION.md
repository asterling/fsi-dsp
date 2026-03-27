---
phase: 6
slug: flink-on-confluent-cloud
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-26
---

# Phase 6 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | terraform validate + bash verification scripts |
| **Config file** | modules/flink/variables.tf (Terraform validation blocks) |
| **Quick run command** | `terraform -chdir=scenarios/cc-flink validate` |
| **Full suite command** | `terraform -chdir=scenarios/cc-flink validate && python3 ci/scripts/validate-schemas.py && bash ci/scripts/check-overrides.sh` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `terraform -chdir=scenarios/cc-flink validate`
- **After every plan wave:** Run full suite command
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 06-01-01 | 01 | 1 | FLINK-01 | validate | `terraform -chdir=scenarios/cc-flink validate` | ❌ W0 | ⬜ pending |
| 06-01-02 | 01 | 1 | FLINK-04 | validate | `terraform -chdir=scenarios/cc-flink validate` | ❌ W0 | ⬜ pending |
| 06-02-01 | 02 | 2 | FLINK-05 | file-check | `test -f reference/flink-sql/tumbling-window.sql` | ❌ W0 | ⬜ pending |
| 06-02-02 | 02 | 2 | FLINK-06, FLINK-07 | file-check | `test -f reference/flink-sql/stream-table-join.sql && test -f reference/flink-sql/filter-route.sql` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `scenarios/cc-flink/` — Terraform scenario directory (created by Plan 01)
- [ ] `modules/flink/` — Reusable Flink module (created by Plan 01)
- [ ] `reference/flink-sql/` — SQL template directory (created by Plan 02)

*Wave 0 artifacts are created during execution — no pre-existing test infra needed.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Flink compute pool provisions on CC | FLINK-01 | Requires CC account + API keys | `terraform apply` in cc-flink scenario, verify pool in CC console |
| Flink SQL statement executes | FLINK-04 | Requires running Flink pool | Submit reference SQL, verify job RUNNING in CC console |
| Schema Registry auto-discovery | FLINK-05 | Requires running SR + registered schemas | CREATE TABLE on topic with Avro schema, verify columns match schema |
| Flink metrics in dashboards | FLINK-06 | Requires running Flink job + observability provider | Deploy job, wait 5min, check dashboard panels populate |
| DLQ routing on deser failure | FLINK-07 | Requires running Flink + malformed input | Produce bad record, verify appears in .dlq topic |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending

---
phase: 1
slug: shared-governance-foundation
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-21
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Terraform test (1.7+ tftest.hcl) + Python unittest + bash |
| **Config file** | `modules/topic/tests/governance.tftest.hcl` (Wave 0 creates) |
| **Quick run command** | `cd modules/topic && terraform test` |
| **Full suite command** | `cd modules/topic && terraform test && python3 -m pytest tests/ && bash tests/ci-validation.sh` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `cd modules/topic && terraform test`
- **After every plan wave:** Run full suite command
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 01-01-01 | 01 | 1 | IAC-07 | unit | `terraform test -filter=governance` | ❌ W0 | ⬜ pending |
| 01-01-02 | 01 | 1 | IAC-09 | unit | `terraform test -filter=externalized_config` | ❌ W0 | ⬜ pending |
| 01-02-01 | 02 | 1 | SCHEMA-01 | integration | `python3 -m pytest tests/test_schema_validation.py` | ❌ W0 | ⬜ pending |
| 01-02-02 | 02 | 1 | SCHEMA-02 | integration | `python3 -m pytest tests/test_schema_validation.py -k compat` | ❌ W0 | ⬜ pending |
| 01-02-03 | 02 | 1 | SCHEMA-03 | unit | `python3 -m pytest tests/test_schema_validation.py -k namespace` | ❌ W0 | ⬜ pending |
| 01-02-04 | 02 | 1 | SCHEMA-04 | manual | Review docs/schema-guide.md breaking change runbook | N/A | ⬜ pending |
| 01-03-01 | 03 | 2 | GOV-01 | unit | `terraform test -filter=naming` | ❌ W0 | ⬜ pending |
| 01-03-02 | 03 | 2 | GOV-02 | unit | `terraform test -filter=sla_tier` | ❌ W0 | ⬜ pending |
| 01-03-03 | 03 | 2 | GOV-03 | manual | Review ADRs for deployment-model guidance | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `modules/topic/tests/governance.tftest.hcl` — Terraform test file for naming, SLA tier, override validation
- [ ] `tests/test_schema_validation.py` — Python tests for schema compatibility and namespace checks
- [ ] `tests/ci-validation.sh` — Shell script to verify CI pipeline rejects bad PRs

*If none: "Existing infrastructure covers all phase requirements."*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Breaking change runbook clarity | SCHEMA-04 | Documentation review requires human judgment | Read docs/schema-guide.md "Breaking Changes" section, verify 5-step migration flow |
| ADR deployment-model guidance | GOV-03 | Requires domain expertise to validate correctness | Review ADR-006, 007, 008 for CC/CP/CFK/RHEL coverage |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending

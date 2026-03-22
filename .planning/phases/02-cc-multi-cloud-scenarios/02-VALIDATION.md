---
phase: 2
slug: cc-multi-cloud-scenarios
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-22
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash (shell scripts) + terraform validate |
| **Config file** | none — validation via shell scripts and terraform CLI |
| **Quick run command** | `terraform validate` per scenario |
| **Full suite command** | `bash scripts/validate-apply.sh <endpoints>` |
| **Estimated runtime** | ~15 seconds (validate only, no apply) |

---

## Sampling Rate

- **After every task commit:** Run `terraform validate` in affected scenario directory
- **After every plan wave:** Run `terraform validate` across all scenarios + `python3 ci/scripts/validate-schemas.py`
- **Before `/gsd:verify-work`:** Full validation suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 02-01-01 | 01 | 1 | IAC-01 | integration | `terraform validate -chdir=scenarios/cc-azure/` | ❌ W0 | ⬜ pending |
| 02-01-02 | 01 | 1 | IAC-02 | integration | `terraform validate -chdir=scenarios/cc-aws/` | ❌ W0 | ⬜ pending |
| 02-01-03 | 01 | 1 | IAC-02 | integration | `terraform validate -chdir=scenarios/cc-gcp/` | ❌ W0 | ⬜ pending |
| 02-02-01 | 02 | 1 | IAC-06 | script | `bash scripts/validate-apply.sh --dry-run` | ❌ W0 | ⬜ pending |
| 02-02-02 | 02 | 2 | IAC-08 | integration | `terraform validate -chdir=scenarios/cc-aws/ && terraform validate -chdir=scenarios/cc-gcp/` | ❌ W0 | ⬜ pending |
| 02-02-03 | 02 | 2 | IAC-10 | ci | `act -j terraform-plan-aws` (local CI test) | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `scenarios/cc-azure/` — migrated from environments/prod/ with terraform validate passing
- [ ] `scenarios/cc-aws/` — scenario directory created with terraform validate passing
- [ ] `scenarios/cc-gcp/` — scenario directory created with terraform validate passing
- [ ] `scripts/validate-apply.sh` — validation script with --dry-run mode for offline testing

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Post-apply validation against live cluster | IAC-06 | Requires running Confluent Cloud cluster | Run `bash scripts/validate-apply.sh <bootstrap> <sr-url> <api-key> <api-secret>` after `terraform apply` |
| DR mirror creation | IAC-10 | Requires two linked Confluent Cloud clusters | Verify mirror topic appears on DR cluster after apply |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending

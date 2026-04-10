---
phase: 15
slug: mrc-failover-and-dr-drill
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-10
---

# Phase 15 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | molecule (Ansible testing via pytest-testinfra) |
| **Config file** | `ansible/roles/cp_dr_mrc/molecule/default/molecule.yml` |
| **Quick run command** | `cd ansible && molecule test -s default -- roles/cp_dr_mrc` |
| **Full suite command** | `cd ansible && molecule test --all` |
| **Estimated runtime** | ~45 seconds |

---

## Sampling Rate

- **After every task commit:** Run `cd ansible && molecule lint`
- **After every plan wave:** Run `cd ansible && molecule test --all`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 45 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 15-01-01 | 01 | 1 | ADR-05 | unit | `cd ansible && molecule test -s default -- roles/cp_dr_mrc` | ❌ W0 | ⬜ pending |
| 15-01-02 | 01 | 1 | ADR-05 | lint | `cd ansible && ansible-lint roles/cp_dr_mrc/` | ❌ W0 | ⬜ pending |
| 15-02-01 | 02 | 2 | ADR-06 | unit | `cd ansible && molecule test -s default -- playbooks/dr-drill` | ❌ W0 | ⬜ pending |
| 15-02-02 | 02 | 2 | ADR-06 | integration | `cd ansible && ansible-playbook playbooks/dr-drill.yml --check` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `ansible/roles/cp_dr_mrc/molecule/default/molecule.yml` — molecule config for MRC role
- [ ] `ansible/roles/cp_dr_mrc/molecule/default/converge.yml` — converge playbook (check mode)
- [ ] `ansible/roles/cp_dr_mrc/molecule/default/verify.yml` — verify playbook

*Molecule infrastructure follows Phase 13 cp_dr_mm2 and Phase 14 CFK patterns.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Observer promotion succeeds on live cluster | ADR-05 | Requires running CP cluster with MRC topology | Run `ansible-playbook playbooks/dr-drill.yml -e dr_action=failover` against staging |
| Compliance report accepted by audit team | ADR-06 | Regulatory format acceptance is subjective | Review generated report with compliance officer |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 45s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending

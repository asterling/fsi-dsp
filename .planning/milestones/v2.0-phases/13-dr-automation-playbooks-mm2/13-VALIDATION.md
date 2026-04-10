---
phase: 13
slug: dr-automation-playbooks-mm2
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-09
---

# Phase 13 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | pytest 7.x |
| **Config file** | tests/ansible/conftest.py |
| **Quick run command** | `pytest tests/ansible/test_cp_dr_mm2.py -x` |
| **Full suite command** | `pytest tests/ansible/ -x -v` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run `pytest tests/ansible/test_cp_dr_mm2.py -x`
- **After every plan wave:** Run `pytest tests/ansible/ -x -v`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 5 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 13-01-01 | 01 | 1 | ADR-01, ADR-03 | unit | `pytest tests/ansible/test_cp_dr_mm2.py -x` | ❌ W0 | ⬜ pending |
| 13-01-02 | 01 | 1 | ADR-04 | unit | `pytest tests/ansible/test_cp_dr_mm2.py -x` | ❌ W0 | ⬜ pending |
| 13-02-01 | 02 | 2 | ADR-02, ADR-03 | unit | `pytest tests/ansible/test_cp_dr_mm2.py -x` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `tests/ansible/test_cp_dr_mm2.py` — stubs for ADR-01 through ADR-04
- [ ] Shared fixtures in `tests/ansible/conftest.py` — existing, may need DR-specific additions

*Existing test infrastructure covers framework requirements. Only DR-specific test file needed.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Failover sequence against live CP cluster | ADR-01 | Requires running MM2 connectors and Consul | Deploy test cluster, run failover playbook, verify topic writability |
| Failback with data sync validation | ADR-02 | Requires bidirectional replication state | Run failback after failover, verify mirror re-establishment |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 5s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending

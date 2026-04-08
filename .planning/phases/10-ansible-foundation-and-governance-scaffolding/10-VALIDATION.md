---
phase: 10
slug: ansible-foundation-and-governance-scaffolding
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-04-07
---

# Phase 10 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | pytest 8.x (filter plugin unit tests) + ansible-lint 24.x (lint validation) |
| **Config file** | `ansible/.ansible-lint` (created in plan 10-01) |
| **Quick run command** | `python3 -m pytest tests/ansible/ -q` |
| **Full suite command** | `python3 -m pytest tests/ansible/ -v && cd ansible && ansible-lint --offline` |
| **Estimated runtime** | ~10 seconds (excluding first-time ansible-lint pip install which may take up to 60s) |

---

## Sampling Rate

- **After every task commit:** Run `python3 -m pytest tests/ansible/ -q`
- **After every plan wave:** Run `python3 -m pytest tests/ansible/ -v && cd ansible && ansible-lint --offline`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 10 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | Status |
|---------|------|------|-------------|-----------|-------------------|--------|
| 10-01-01 | 01 | 1 | AFOUND-01 | integration | `ansible-galaxy collection install -r ansible/requirements.yml --force -p /tmp/test-collections 2>&1 \| grep confluent.platform` | ⬜ pending |
| 10-01-02 | 01 | 1 | AFOUND-01 | file | `test -f ansible/ansible.cfg` | ⬜ pending |
| 10-01-03 | 01 | 1 | AFOUND-04 | file | `ls ansible/inventories/{dev,staging,prod,dr}/hosts.yml` | ⬜ pending |
| 10-01-04 | 01 | 1 | AFOUND-05 | integration | `pip install ansible-lint --quiet 2>/dev/null && cd ansible && ansible-lint --offline` | ⬜ pending |
| 10-02-01 | 02 | 2 | AFOUND-02 | unit | `python3 -m pytest tests/ansible/test_governance_parity.py -v` | ⬜ pending |
| 10-02-02 | 02 | 2 | AFOUND-03 | unit | `python3 -m pytest tests/ansible/test_fsi_governance_filter.py -v` | ⬜ pending |
| 10-02-03 | 02 | 2 | AFOUND-05 | integration | `pip install ansible-lint --quiet 2>/dev/null && cd ansible && ansible-lint --offline` | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [x] pytest 8.x installed (project already has Python 3.8+ requirement)
- [x] Test files created inline by plan tasks (no separate Wave 0 stubs needed)
- [x] ansible-lint installed via `pip install ansible-lint --quiet` as prerequisite in task actions

Plans create all test files (`tests/ansible/test_governance_parity.py`, `tests/ansible/test_fsi_governance_filter.py`, `tests/ansible/test_requirements.py`) inline within task actions. No separate Wave 0 test scaffold step is required.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Inventory host group patterns documented | AFOUND-04 | Documentation quality is subjective | Review `ansible/inventories/*/hosts.yml` for inline comments explaining each host group |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 10s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending

---
phase: 10
slug: ansible-foundation-and-governance-scaffolding
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-07
---

# Phase 10 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | pytest 8.x (filter plugin unit tests) + ansible-lint 24.x (lint validation) |
| **Config file** | `ansible/.ansible-lint` (created in plan 10-02) |
| **Quick run command** | `python -m pytest ansible/plugins/filter/tests/ -q` |
| **Full suite command** | `python -m pytest ansible/plugins/filter/tests/ -v && cd ansible && ansible-lint` |
| **Estimated runtime** | ~10 seconds |

---

## Sampling Rate

- **After every task commit:** Run `python -m pytest ansible/plugins/filter/tests/ -q`
- **After every plan wave:** Run `python -m pytest ansible/plugins/filter/tests/ -v && cd ansible && ansible-lint`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 10 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 10-01-01 | 01 | 1 | AFOUND-01 | integration | `ansible-galaxy collection install -r ansible/requirements.yml --force -p /tmp/test-collections 2>&1 \| grep confluent.platform` | ❌ W0 | ⬜ pending |
| 10-01-02 | 01 | 1 | AFOUND-01 | file | `test -f ansible/ansible.cfg` | ❌ W0 | ⬜ pending |
| 10-01-03 | 01 | 1 | AFOUND-04 | file | `ls ansible/inventories/{dev,staging,prod,dr}/hosts.yml` | ❌ W0 | ⬜ pending |
| 10-02-01 | 02 | 1 | AFOUND-02 | unit | `python -m pytest ansible/plugins/filter/tests/test_sla_tiers.py -v` | ❌ W0 | ⬜ pending |
| 10-02-02 | 02 | 1 | AFOUND-03 | unit | `python -m pytest ansible/plugins/filter/tests/test_topic_name.py -v` | ❌ W0 | ⬜ pending |
| 10-02-03 | 02 | 1 | AFOUND-05 | integration | `cd ansible && ansible-lint` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `ansible/plugins/filter/tests/test_sla_tiers.py` — unit tests for SLA tier lookups matching Terraform values
- [ ] `ansible/plugins/filter/tests/test_topic_name.py` — unit tests for topic name assembly and validation
- [ ] `ansible/plugins/filter/tests/conftest.py` — shared fixtures with governance constants
- [ ] pytest 8.x installed (project already has Python 3.8+ requirement)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Inventory host group patterns documented | AFOUND-04 | Documentation quality is subjective | Review `ansible/inventories/*/hosts.yml` for inline comments explaining each host group |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 10s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending

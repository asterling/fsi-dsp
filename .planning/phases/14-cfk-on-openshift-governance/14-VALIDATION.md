---
phase: 14
slug: cfk-on-openshift-governance
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-10
---

# Phase 14 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | pytest 7.x |
| **Config file** | tests/ansible/conftest.py |
| **Quick run command** | `pytest tests/ansible/test_cfk_operator.py tests/ansible/test_cfk_topic.py -x -v` |
| **Full suite command** | `pytest tests/ansible/ -x` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run `pytest tests/ansible/test_cfk_operator.py tests/ansible/test_cfk_topic.py -x -v`
- **After every plan wave:** Run `pytest tests/ansible/ -x`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 5 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 14-01-01 | 01 | 1 | ACFK-01, ACFK-02 | unit | `pytest tests/ansible/test_cfk_operator.py -x -v` | ❌ W0 | ⬜ pending |
| 14-02-01 | 02 | 2 | ACFK-03 | unit | `pytest tests/ansible/test_cfk_topic.py -x -v` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `tests/ansible/test_cfk_operator.py` — stubs for ACFK-01, ACFK-02
- [ ] `tests/ansible/test_cfk_topic.py` — stubs for ACFK-03

*Existing test infrastructure (conftest.py, fixtures/) covers shared needs.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| CFK operator deploys on live OpenShift | ACFK-01 | Requires OpenShift cluster | Run playbook against test cluster, verify operator pod running |
| KafkaTopic CRDs applied to running CFK | ACFK-03 | Requires CFK cluster | Apply generated CRDs, verify topics created with correct configs |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 5s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending

---
phase: 12
slug: orchestration-pipeline-observability-and-ci-cd
status: approved
nyquist_compliant: true
wave_0_complete: true
created: 2026-04-09
---

# Phase 12 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | pytest 7.x (existing from Phase 10/11) |
| **Config file** | tests/ansible/conftest.py |
| **Quick run command** | `python3 -m pytest tests/ansible/ -q --tb=short` |
| **Full suite command** | `python3 -m pytest tests/ansible/ -v && ansible-lint ansible/ --offline` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run `python3 -m pytest tests/ansible/ -q --tb=short`
- **After every plan wave:** Run `python3 -m pytest tests/ansible/ -v && ansible-lint ansible/ --offline`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 5 seconds

---

## Wave 0 Note

All plans use inline TDD (`tdd="true"`) where tests are written as the first step of each task's action block (RED phase). This satisfies the Nyquist wave-0 requirement -- test files are created before production code within each task's execution. No separate wave-0 plan is needed.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 12-01-01 | 01 | 1 | APIPE-01 | unit | `python3 -m pytest tests/ansible/test_orchestration.py tests/ansible/test_cp_connect.py -q` | inline TDD | pending |
| 12-01-02 | 01 | 1 | APIPE-02 | unit+lint | `python3 -m pytest tests/ansible/test_cp_connect.py -q` | inline TDD | pending |
| 12-02-01 | 02 | 1 | AOBS-01 | unit | `python3 -m pytest tests/ansible/test_cp_observability.py -q` | inline TDD | pending |
| 12-02-02 | 02 | 1 | AOBS-02 | unit | `python3 -m pytest tests/ansible/test_cp_observability.py -q` | inline TDD | pending |
| 12-03-01 | 03 | 2 | ACI-01 | lint | `yamllint .github/workflows/ansible-*.yml` | inline TDD | pending |
| 12-03-02 | 03 | 2 | ACI-02 | unit | `python3 -m pytest tests/ansible/test_ci_workflows.py -q` | inline TDD | pending |

*Status: pending / green / red / flaky*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| site.yml end-to-end run | APIPE-01 | Requires live CP cluster | Run `ansible-playbook site.yml --check` against inventory |
| Connector RUNNING state verification | APIPE-03 | Requires Kafka Connect | Deploy connector, check `GET /connectors/*/status` |
| Prometheus scrape auto-discovery | AOBS-02 | Requires Prometheus server | Add host to inventory, verify target file regenerated |
| GitHub Actions CI execution | ACI-01 | Requires GitHub Actions runner | Push PR touching ansible/, verify checks run |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or inline TDD (wave-0 satisfied)
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covered by inline TDD pattern in all plans
- [x] No watch-mode flags
- [x] Feedback latency < 5s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved

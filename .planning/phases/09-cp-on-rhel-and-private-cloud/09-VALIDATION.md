---
phase: 09
slug: cp-on-rhel-and-private-cloud
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-27
---

# Phase 09 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash (shellcheck + bats-like assertions) / python3 (schema validation) |
| **Config file** | none — uses existing CI scripts |
| **Quick run command** | `bash tests/dr/test-fsi-dr-mrc.sh` |
| **Full suite command** | `python3 ci/scripts/c4e-precheck.py && bash tests/dr/test-fsi-dr-mrc.sh` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `bash tests/dr/test-fsi-dr-mrc.sh` (when MRC tests exist)
- **After every plan wave:** Run `python3 ci/scripts/c4e-precheck.py && bash tests/dr/test-fsi-dr-mrc.sh`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 09-01-01 | 01 | 1 | IAC-04 | file/lint | `ls scenarios/cp-rhel/ansible/roles/*/tasks/main.yml` | ❌ W0 | ⬜ pending |
| 09-01-02 | 01 | 1 | IAC-04 | file/lint | `shellcheck scenarios/cp-rhel/scripts/*.sh` | ❌ W0 | ⬜ pending |
| 09-02-01 | 02 | 1 | IAC-05, DR-06 | file/lint | `ls scenarios/private-cloud/main.tf` | ❌ W0 | ⬜ pending |
| 09-02-02 | 02 | 1 | DR-06 | unit | `bash tests/dr/test-fsi-dr-mrc.sh` | ❌ W0 | ⬜ pending |
| 09-03-01 | 03 | 2 | FLINK-03 | file/lint | `ls scenarios/cp-rhel/ansible/roles/flink_standalone/tasks/main.yml` | ❌ W0 | ⬜ pending |
| 09-03-02 | 03 | 2 | COMP-03 | file/lint | `ls scenarios/cp-rhel/fips/fips-preflight.sh` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `tests/dr/test-fsi-dr-mrc.sh` — MRC backend test suite (mirrors MM2 test pattern)
- [ ] Ansible role directories created during task execution

*Existing CI infrastructure (c4e-precheck.py, validate-schemas.py) covers schema/topic validation.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Ansible roles deploy on real RHEL host | IAC-04 | Requires target RHEL infrastructure | Deploy to test host, verify systemd services running |
| MRC observer promotion under failure | DR-06 | Requires multi-DC Kafka cluster | Simulate DC failure, verify automatic promotion |
| FIPS mode on RHEL with fips-mode-setup | COMP-03 | Requires FIPS-enabled RHEL host | Boot FIPS RHEL, run preflight, verify Bouncy Castle |

*All phase behaviors with manual-only verification have corresponding automated structural checks.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending

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
| **Full suite command** | `python3 ci/scripts/c4e-precheck.py --scenario-dir scenarios/cp-rhel/ && bash tests/dr/test-fsi-dr-mrc.sh` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `bash tests/dr/test-fsi-dr-mrc.sh` (when MRC tests exist)
- **After every plan wave:** Run `python3 ci/scripts/c4e-precheck.py --scenario-dir scenarios/cp-rhel/ && bash tests/dr/test-fsi-dr-mrc.sh`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 09-01-01 | 01 | 1 | IAC-04 | file/lint | `ls scenarios/cp-rhel/playbooks/deploy-cp.yml scenarios/cp-rhel/inventory/hosts.yml.example scenarios/cp-rhel/topics/corebanking-account-txn.yml` | N/A (scaffold) | pending |
| 09-02-01 | 02 | 1 | IAC-05 | file/lint | `cd scenarios/private-cloud && terraform init -backend=false && terraform validate` | N/A (scaffold) | pending |
| 09-02-02 | 02 | 1 | IAC-05 | unit | `python3 ci/scripts/c4e-precheck.py --scenario-dir scenarios/cp-rhel/ --verbose` | N/A (extends existing) | pending |
| 09-03-01 | 03 | 1 | DR-06 | unit | `bash tests/dr/test-fsi-dr-helpers.sh` | exists | pending |
| 09-03-02 | 03 | 1 | DR-06 | unit | `bash tests/dr/test-fsi-dr-mrc.sh` | W0 (created by 09-03 Task 2) | pending |
| 09-04-01 | 04 | 2 | FLINK-03 | file/lint | `ls scenarios/cp-rhel/roles/flink_standalone/tasks/main.yml scenarios/cp-rhel/roles/flink_standalone/templates/flink-conf.yaml.j2 scenarios/cp-rhel/playbooks/deploy-flink.yml` | N/A (scaffold) | pending |
| 09-04-02 | 04 | 2 | COMP-03 | file/lint | `bash scripts/validate-fips.sh --check` | W0 (created by 09-04 Task 2) | pending |

*Status: pending / green / red / flaky*

---

## Wave 0 Requirements

- [ ] `tests/dr/test-fsi-dr-mrc.sh` — MRC backend test suite (created by Plan 03, Task 2)
- [ ] `scripts/validate-fips.sh` — FIPS validation script (created by Plan 04, Task 2)
- [ ] Ansible role directories created during task execution (Plan 01 and Plan 04)

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

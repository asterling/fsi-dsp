---
phase: 8
slug: cfk-on-openshift
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-27
---

# Phase 8 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | pytest 7.x (Python validators), bash (shell scripts), helm template --validate (Helm) |
| **Config file** | ci/scripts/validate-schemas.py, ci/scripts/check-overrides.sh |
| **Quick run command** | `python ci/scripts/validate-schemas.py && bash ci/scripts/check-overrides.sh` |
| **Full suite command** | `python ci/scripts/validate-schemas.py && bash ci/scripts/check-overrides.sh && helm template scenarios/cfk-openshift/helm/ --validate 2>&1` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `python ci/scripts/validate-schemas.py && bash ci/scripts/check-overrides.sh`
- **After every plan wave:** Run full suite command
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 08-01-01 | 01 | 1 | IAC-03 | integration | `helm template scenarios/cfk-openshift/helm/ --validate` | ❌ W0 | ⬜ pending |
| 08-01-02 | 01 | 1 | IAC-03 | unit | `python ci/scripts/validate-schemas.py` | ✅ | ⬜ pending |
| 08-02-01 | 02 | 1 | DR-05 | unit | `bash scripts/fsi-dr.sh status --backend mm2 --dry-run` | ❌ W0 | ⬜ pending |
| 08-03-01 | 03 | 2 | FLINK-02 | integration | `helm template scenarios/cfk-openshift/helm/flink-operator --validate` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `scenarios/cfk-openshift/helm/` — Helm chart skeleton for CFK operator values
- [ ] CI validator extension for CFK KafkaTopic YAML validation
- [ ] DR CLI mm2 backend stub testability (dry-run mode)

*Existing Python validators and shell scripts cover schema and override validation.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| CFK operator deploys on OCP 4.x | IAC-03 | Requires live OpenShift cluster | Deploy CFK Helm chart to OCP test cluster, verify pods running |
| MM2 replication lag within SLA thresholds | DR-05 | Requires two live Kafka clusters | Run MM2 between East/West, produce messages, check lag via fsi-dr status |
| Flink job reads from CFK SR | FLINK-02 | Requires live Flink + SR | Submit FlinkDeployment, verify job reads Avro from SR |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending

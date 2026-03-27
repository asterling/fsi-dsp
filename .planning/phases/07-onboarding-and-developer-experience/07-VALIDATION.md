---
phase: 7
slug: onboarding-and-developer-experience
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-27
---

# Phase 7 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Shell scripts (roundtrip-test.sh pattern) + Python unittest |
| **Config file** | `reference/integration-test/error-path-tests.sh` |
| **Quick run command** | `bash reference/integration-test/roundtrip-test.sh` |
| **Full suite command** | `bash reference/integration-test/roundtrip-test.sh && bash reference/integration-test/error-path-tests.sh` |
| **Estimated runtime** | ~60 seconds |

---

## Sampling Rate

- **After every task commit:** Run `bash reference/integration-test/roundtrip-test.sh`
- **After every plan wave:** Run full suite command
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 60 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 07-01-01 | 01 | 1 | ONBOARD-01 | integration | `grep -q 'deployment_model' .github/ISSUE_TEMPLATE/new-topic-request.yml` | ❌ W0 | ⬜ pending |
| 07-02-01 | 02 | 1 | ONBOARD-02 | integration | `python ci/scripts/c4e-precheck.py --dry-run` | ❌ W0 | ⬜ pending |
| 07-03-01 | 03 | 1 | ONBOARD-03 | unit | `cd reference/python-producer && python -m pytest tests/` | ❌ W0 | ⬜ pending |
| 07-04-01 | 04 | 2 | ONBOARD-04 | integration | `bash reference/integration-test/error-path-tests.sh` | ❌ W0 | ⬜ pending |
| 07-05-01 | 05 | 2 | ONBOARD-05 | integration | `docker compose --profile flink up -d && docker compose --profile flink ps` | ❌ W0 | ⬜ pending |
| 07-06-01 | 06 | 1 | ONBOARD-06 | unit | `grep -q 'dlq' reference/java-producer/src/main/java/org/fsi/kafka/producer/FsiProducer.java` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `reference/python-producer/tests/test_fsi_producer.py` — stubs for ONBOARD-03
- [ ] `reference/python-consumer/tests/test_fsi_consumer.py` — stubs for ONBOARD-03
- [ ] `reference/integration-test/error-path-tests.sh` — stubs for ONBOARD-04

*Existing roundtrip-test.sh and Docker Compose infrastructure covers base requirements.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| GitHub issue form renders correctly | ONBOARD-01 | GitHub UI rendering | Create draft issue in browser, verify dropdowns appear |
| Flink SQL client interactive session | ONBOARD-05 | Interactive CLI | `docker compose --profile flink exec flink-sql-client sql-client.sh` and run sample query |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending

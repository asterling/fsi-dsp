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
| **Framework** | Shell scripts (roundtrip-test.sh pattern) + Python ast.parse |
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
| 07-01-01 | 01 | 1 | ONBOARD-01, ONBOARD-02 | integration | `python3 -c "import yaml; yaml.safe_load(open('.github/ISSUE_TEMPLATE/new-topic-request.yml'))" && python3 ci/scripts/c4e-precheck.py --help` | ❌ W0 | ⬜ pending |
| 07-01-02 | 01 | 1 | ONBOARD-02 | integration | `grep -c "c4e-precheck" .github/workflows/terraform-scenario.yml` | ❌ W0 | ⬜ pending |
| 07-02-01 | 02 | 1 | ONBOARD-03, ONBOARD-06 | syntax | `python3 -c "import ast; ast.parse(open('reference/python-producer/fsi_producer.py').read()); ast.parse(open('reference/python-producer/fsi_dlq_handler.py').read()); ast.parse(open('reference/python-consumer/fsi_consumer.py').read())"` | ❌ W0 | ⬜ pending |
| 07-02-02 | 02 | 1 | ONBOARD-06 | existence | `test -f reference/java-producer/src/main/java/org/fsi/kafka/producer/FsiDlqHandler.java && test -f reference/dotnet-producer/FsiDlqHandler.cs && grep -q "FsiDlqHandler" reference/java-producer/src/main/java/org/fsi/kafka/producer/FsiProducer.java && grep -q "FsiDlqHandler" reference/dotnet-producer/FsiProducer.cs` | ❌ W0 | ⬜ pending |
| 07-03-01 | 03 | 2 | ONBOARD-04 | syntax | `bash -n reference/integration-test/error-path-tests.sh` | ❌ W0 | ⬜ pending |
| 07-03-02 | 03 | 2 | ONBOARD-05 | existence | `test -f reference/local-dev/flink-sql/Dockerfile && grep -q "flink-jobmanager" reference/local-dev/docker-compose.yml && grep -q "profiles:" reference/local-dev/docker-compose.yml` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] All files are new — no pre-existing test infrastructure needed for this phase
- [ ] Existing `roundtrip-test.sh` and Docker Compose infrastructure covers baseline

*Existing infrastructure covers all phase requirements.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| GitHub issue form renders correctly | ONBOARD-01 | GitHub UI rendering | Create draft issue in browser, verify dropdowns appear |
| Flink SQL client interactive session | ONBOARD-05 | Interactive CLI | `docker exec -it fsi-flink-sql-client /opt/flink/bin/sql-client.sh` and run sample query |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending

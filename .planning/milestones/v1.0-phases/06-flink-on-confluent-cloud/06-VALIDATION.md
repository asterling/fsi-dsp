---
phase: 6
slug: flink-on-confluent-cloud
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-03-26
---

# Phase 6 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | terraform validate + bash verification scripts + python JSON/XML validation |
| **Config file** | modules/flink/variables.tf (Terraform validation blocks) |
| **Quick run command** | `terraform -chdir=scenarios/cc-aws init -backend=false && terraform -chdir=scenarios/cc-aws validate` |
| **Full suite command** | `terraform -chdir=scenarios/cc-aws init -backend=false && terraform -chdir=scenarios/cc-aws validate && python3 ci/scripts/validate-schemas.py && bash ci/scripts/check-overrides.sh` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `terraform -chdir=scenarios/cc-aws init -backend=false && terraform -chdir=scenarios/cc-aws validate`
- **After every plan wave:** Run full suite command
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 06-01-01 | 01 | 1 | FLINK-01 | validate | `terraform -chdir=scenarios/cc-aws init -backend=false && terraform -chdir=scenarios/cc-aws validate` | W0 | pending |
| 06-01-02 | 01 | 1 | FLINK-05 | validate | `terraform -chdir=scenarios/cc-aws init -backend=false && terraform -chdir=scenarios/cc-aws validate` | W0 | pending |
| 06-02-01 | 02 | 1 | FLINK-04 | file-check | `test -f reference/flink-sql/tumbling-window-aggregation.sql && test -f reference/flink-sql/stream-table-join-enrichment.sql && test -f reference/flink-sql/filter-and-route.sql && test -f reference/flink-sql/dlq-pattern.sql` | W0 | pending |
| 06-02-02 | 02 | 1 | FLINK-07 | file-check | `test -f reference/flink-sql/README.md && grep -q 'error-handling.mode' reference/flink-sql/dlq-pattern.sql` | W0 | pending |
| 06-03-01 | 03 | 2 | FLINK-06 | json-validate | `grep -q 'io_confluent_flink' observability/grafana/dashboard-flink-jobs.json && ! grep -q 'Stub' observability/grafana/dashboard-flink-jobs.json && python3 -c "import json; json.load(open('observability/grafana/dashboard-flink-jobs.json'))"` | W0 | pending |
| 06-03-02 | 03 | 2 | FLINK-06 | json-xml-validate | `python3 -c "import json; [json.load(open(f)) for f in ['observability/dynatrace/dashboard.json','observability/datadog/dashboard.json','observability/newrelic/dashboard.json','observability/instana/dashboard.json']]" && python3 -c "import xml.etree.ElementTree as ET; ET.parse('observability/splunk/dashboard.xml')" && grep -q 'CC_FLINK_ENABLED' .env.example` | W0 | pending |

*Status: pending / green / red / flaky*

---

## Wave 0 Requirements

- [ ] `modules/flink/` — Reusable Flink module (created by Plan 01)
- [ ] `scenarios/cc-aws/flink.tf` — Scenario wiring (created by Plan 01)
- [ ] `reference/flink-sql/` — SQL template directory (created by Plan 02)
- [ ] `observability/grafana/dashboard-flink-jobs.json` — Existing stub from Phase 5 (updated by Plan 03)
- [ ] `observability/dynatrace/dashboard.json` — Existing stub from Phase 5 (updated by Plan 03)
- [ ] `observability/datadog/dashboard.json` — Existing stub from Phase 5 (updated by Plan 03)
- [ ] `observability/splunk/dashboard.xml` — Existing stub from Phase 5 (updated by Plan 03)
- [ ] `observability/newrelic/dashboard.json` — Existing stub from Phase 5 (updated by Plan 03)
- [ ] `observability/instana/dashboard.json` — Existing stub from Phase 5 (updated by Plan 03)

*Wave 0 artifacts are created during execution — no pre-existing test infra needed.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Flink compute pool provisions on CC | FLINK-01 | Requires CC account + API keys | `terraform apply` in cc-aws scenario with flink_enabled=true, verify pool in CC console |
| Flink SQL statement executes | FLINK-04 | Requires running Flink pool | Submit reference SQL via Terraform flink_statements, verify job RUNNING in CC console |
| Schema Registry auto-discovery | FLINK-05 | Requires running SR + registered schemas | Query topic with Avro schema in Flink SQL, verify columns match schema fields |
| Flink metrics in dashboards | FLINK-06 | Requires running Flink job + observability provider | Deploy job, wait 5min, check dashboard panels populate |
| DLQ routing on deser failure | FLINK-07 | Requires running Flink + malformed input | Produce bad record, verify appears in .dlq topic |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 15s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending

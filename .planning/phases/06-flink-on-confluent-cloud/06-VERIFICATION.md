---
phase: 06-flink-on-confluent-cloud
verified: 2026-03-27T00:00:00Z
status: passed
score: 5/5 must-haves verified
gaps: []
human_verification:
  - test: "Set flink_enabled = true in a CC scenario and run terraform plan"
    expected: "Terraform produces a plan to create confluent_flink_compute_pool and (if flink_statements provided) confluent_flink_statement resources"
    why_human: "Requires valid Confluent Cloud credentials and a live environment to produce a meaningful plan output"
  - test: "Submit one SQL template (e.g., tumbling-window-aggregation.sql) via the CC console against a real compute pool"
    expected: "Statement executes without error; input topic appears as a Flink table without requiring CREATE TABLE"
    why_human: "SR auto-discovery behavior requires a live CC environment with registered Avro schemas"
  - test: "Import Grafana dashboard-flink-jobs.json into a Grafana instance connected to CC Metrics API via Prometheus scrape"
    expected: "All 5 panels render with live data; CFU Utilization panel shows non-zero value when compute pool is active"
    why_human: "Requires a running CC Metrics API scrape target; cannot verify panel render programmatically"
---

# Phase 6: Flink on Confluent Cloud Verification Report

**Phase Goal:** FSI teams can deploy a CC Flink compute pool via Terraform and use reference SQL templates for common stream processing patterns -- with SR integration and observability
**Verified:** 2026-03-27
**Status:** passed
**Re-verification:** No -- initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Operator can provision a CC Flink compute pool and submit Flink SQL statements via Terraform | VERIFIED | `modules/flink/main.tf` contains `confluent_flink_compute_pool` + `confluent_flink_statement` resources; all 3 CC scenarios wired with `source = "../../modules/flink"`; all 3 pass `terraform validate` |
| 2 | Reference SQL templates exist for tumbling window aggregation, stream-table join enrichment, and filter-and-route patterns | VERIFIED | `reference/flink-sql/` contains 4 SQL files with correct CC Flink syntax: TUMBLE(), FOR SYSTEM_TIME AS OF, EXECUTE STATEMENT SET, ALTER TABLE...SET DLQ properties |
| 3 | Flink auto-discovers Schema Registry subjects for Avro serde in CC deployments | VERIFIED | No `CREATE TABLE` with connector/format properties in any SQL template; all 4 files reference tables by backtick-quoted catalog.database.topic path; module and SQL comments explicitly document FLINK-05 auto-discovery |
| 4 | Flink job metrics (pending records for backpressure, records throughput) appear in observability provider dashboards | VERIFIED | Grafana dashboard has 5 real panels using `io_confluent_flink_*` metrics; all 5 other provider dashboards (Dynatrace, Datadog, Splunk, New Relic, Instana) contain real CC Flink metric queries; no stub/placeholder text remains in any dashboard |
| 5 | Deserialization failures route to `{topic}.dlq` topics via CC Flink error-handling.mode table properties | VERIFIED | `reference/flink-sql/dlq-pattern.sql` contains `ALTER TABLE...SET ('error-handling.mode' = 'log', 'error-handling.log.target' = '...')` with FSI domain example; README documents CC-specific pattern vs Apache Flink side outputs |

**Score:** 5/5 truths verified

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `modules/flink/main.tf` | Flink compute pool and statement Terraform resources | VERIFIED | Contains `resource "confluent_flink_compute_pool" "pool"` and `resource "confluent_flink_statement" "statements"` with `lifecycle { prevent_destroy = true }` on both; required_providers block with `confluentinc/confluent ~> 2.0` |
| `modules/flink/variables.tf` | Module input variables with validation blocks | VERIFIED | `variable "compute_pool_name"` with regex validation; `variable "cloud_provider"` with contains(["AWS","AZURE","GCP"]); `variable "max_cfu"` restricted to [5,10,20,30,40,50]; 14 variables total |
| `modules/flink/outputs.tf` | Module outputs for downstream consumption | VERIFIED | `output "compute_pool_id"`, `output "compute_pool_name"`, `output "compute_pool_resource_name"`, `output "statement_names"` |
| `scenarios/cc-aws/flink.tf` | Flink resources wired to AWS scenario | VERIFIED | `module "flink"` with `cloud_provider = "AWS"`, `count = var.flink_enabled ? 1 : 0`, `source = "../../modules/flink"`, `environment_id = var.cc_environment_id` (no regex) |
| `scenarios/cc-azure/flink.tf` | Flink resources wired to Azure scenario | VERIFIED | `module "flink"` with `cloud_provider = "AZURE"`, same opt-in pattern |
| `scenarios/cc-gcp/flink.tf` | Flink resources wired to GCP scenario | VERIFIED | `module "flink"` with `cloud_provider = "GCP"`, same opt-in pattern |
| `reference/flink-sql/tumbling-window-aggregation.sql` | Tumbling window aggregation SQL template | VERIFIED | Contains `TUMBLE(TABLE ..., DESCRIPTOR($rowtime), INTERVAL '1' MINUTE)`, `GROUP BY window_start, window_end`, corebanking domain example |
| `reference/flink-sql/stream-table-join-enrichment.sql` | Stream-table join enrichment SQL template | VERIFIED | Contains `FOR SYSTEM_TIME AS OF txn.$rowtime AS cust`, `ON txn.account_number = cust.account_number`, fraud/corebanking domain |
| `reference/flink-sql/filter-and-route.sql` | Filter-and-route SQL template | VERIFIED | Contains `EXECUTE STATEMENT SET`, `BEGIN`, `END;`, compliance screening domain with score-based routing |
| `reference/flink-sql/dlq-pattern.sql` | DLQ configuration via table properties | VERIFIED | Contains `'error-handling.mode' = 'log'` and `'error-handling.log.target'`; documents deserialization-only scope |
| `reference/flink-sql/README.md` | Usage guide explaining each template with FSI context | VERIFIED | Has sections: Schema Registry Auto-Discovery, Tumbling Window Aggregation, Stream-Table Join Enrichment, Filter-and-Route, Dead Letter Queue, Submitting via Terraform, Common Pitfalls (6 items) |
| `observability/grafana/dashboard-flink-jobs.json` | Real Flink metrics panels (not stubs) | VERIFIED | 5 panels with real CC Metrics API queries; no "Stub" string; valid JSON; includes CFU Utilization panel; `io_confluent_flink_num_records_out`, `io_confluent_flink_pending_records`, `io_confluent_flink_current_cfu` |
| `observability/grafana/alerts.yaml` | Flink-specific alert rules | VERIFIED | Group `fsi-kafka-flink` with 3 rules: `fsi-flink-pending-records-warn` (>1000), `fsi-flink-pending-records-alert` (>10000), `fsi-flink-throughput-drop` (<1 rec/sec) |
| `observability/metrics-mapping.md` | CC Flink metric names replacing stub placeholders | VERIFIED | Contains `io.confluent.flink/num_records_in`, `io.confluent.flink/num_records_out`, `io.confluent.flink/pending_records`, `io.confluent.flink/current_cfu`, `io.confluent.flink/max_cfu`; no stub warning text |
| `.env.example` | Flink env var section | VERIFIED | Section 14 (FLINK): CC_FLINK_ENABLED, CC_FLINK_COMPUTE_POOL_NAME, CC_FLINK_MAX_CFU, CC_FLINK_REGION, CC_FLINK_REST_ENDPOINT, CC_FLINK_API_KEY (marked SENSITIVE), CC_FLINK_API_SECRET, CC_FLINK_SERVICE_ACCOUNT_ID |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `scenarios/cc-aws/flink.tf` | `modules/flink/main.tf` | module source reference | WIRED | `source = "../../modules/flink"` present; confirmed in cc-azure and cc-gcp as well |
| `modules/flink/main.tf` | `confluent_flink_compute_pool` | Terraform resource | WIRED | `resource "confluent_flink_compute_pool" "pool"` at line 37 |
| `modules/flink/main.tf` | `confluent_flink_statement` | Terraform resource | WIRED | `resource "confluent_flink_statement" "statements"` at line 64 with `for_each = var.flink_statements` |
| `reference/flink-sql/dlq-pattern.sql` | DLQ topic | error-handling.log.target table property | WIRED | `'error-handling.log.target' = 'corebanking.transactions.v1.account-transaction.dlq'` |
| `reference/flink-sql/stream-table-join-enrichment.sql` | temporal join | FOR SYSTEM_TIME AS OF | WIRED | `FOR SYSTEM_TIME AS OF txn.$rowtime AS cust` |
| `observability/grafana/dashboard-flink-jobs.json` | CC Metrics API | PromQL queries using CC metric names | WIRED | 6 occurrences of `io_confluent_flink_*` in panel targets; CFU utilization as `current_cfu / max_cfu * 100` |
| `observability/grafana/alerts.yaml` | Flink pending records metric | PromQL threshold alert | WIRED | `max by (statement_name) (io_confluent_flink_pending_records{resource_type="flink_statement"})` in both pending records alert rules |

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| FLINK-01 | 06-01-PLAN.md | CC Flink compute pool provisioned via Terraform (`confluent_flink_compute_pool`, `confluent_flink_statement`) | SATISFIED | `modules/flink/main.tf` contains both resources; all 3 CC scenarios wired; `terraform validate` passes on AWS, Azure, GCP |
| FLINK-04 | 06-02-PLAN.md | Flink SQL reference templates for tumbling window aggregation, stream-table join enrichment, and filter-and-route patterns | SATISFIED | All 3 templates exist in `reference/flink-sql/` with correct CC Flink SQL syntax and FSI domain examples |
| FLINK-05 | 06-01-PLAN.md | Flink integrates with Schema Registry for Avro serde (CC Flink auto-discovers SR subjects) | SATISFIED | No `CREATE TABLE` with connector/format properties in any SQL template; FLINK-05 documented in module comments and README |
| FLINK-06 | 06-03-PLAN.md | Flink job metrics (checkpoint duration, backpressure, throughput) exported to each provider's dashboard templates | SATISFIED | All 6 provider dashboards contain real `io.confluent.flink/*` metrics; Grafana has 5 panels + 3 alert rules; checkpoint duration replaced by pending_records (backpressure proxy) as noted in plan objective |
| FLINK-07 | 06-02-PLAN.md | Flink dead letter handling routes deserialization failures to `{topic}.dlq` topics via CC Flink error-handling.mode table properties | SATISFIED | `reference/flink-sql/dlq-pattern.sql` implements `ALTER TABLE...SET ('error-handling.mode' = 'log', 'error-handling.log.target' = '...')` with correct FSI naming convention |

**Orphaned requirements check:** REQUIREMENTS.md maps FLINK-02 (Phase 8) and FLINK-03 (Phase 9) to future phases -- these are correctly not claimed by Phase 6 plans. No orphaned requirements for this phase.

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `modules/flink/variables.tf` | 102 | `variable "prevent_destroy"` declared but never referenced in `main.tf` (lifecycle blocks hardcode `prevent_destroy = true`) | Info | Dead variable; no functional impact. The hardcoded value is correct and safe. The variable could be removed or wired to `lifecycle { prevent_destroy = var.prevent_destroy }` in a future cleanup. |

No blockers or warnings found. One info-level finding: the declared `prevent_destroy` variable is unused.

---

### Human Verification Required

#### 1. Terraform Plan Against Live CC Environment

**Test:** Set `flink_enabled = true` in `scenarios/cc-aws/terraform.tfvars` with valid CC credentials and run `terraform plan`.
**Expected:** Plan shows `confluent_flink_compute_pool.pool[0]` to be created with correct cloud/region/max_cfu values; no plan errors.
**Why human:** Requires valid Confluent Cloud API key/secret and a provisioned environment ID.

#### 2. Schema Registry Auto-Discovery Behavior

**Test:** Submit `tumbling-window-aggregation.sql` via the CC console or `modules/flink` Terraform against a real compute pool where `corebanking.transactions.v1.account-transaction` topic exists with a registered Avro schema.
**Expected:** SQL executes without `Table not found` error; topic is auto-discovered as a Flink table without requiring a `CREATE TABLE` statement.
**Why human:** SR auto-discovery is a CC runtime behavior that cannot be verified without a live CC environment and registered schemas.

#### 3. Grafana Dashboard Rendering

**Test:** Import `observability/grafana/dashboard-flink-jobs.json` into a Grafana instance connected to a Prometheus scrape of the CC Metrics API.
**Expected:** All 5 panels render with live data; "CFU Utilization (%)" panel shows a non-zero percentage when a compute pool is active; "Pending Records" gauge reflects backpressure.
**Why human:** Requires a running CC Metrics API Prometheus integration and an active Flink compute pool.

---

### Gaps Summary

No gaps. All 5 observable truths are verified. All 15 required artifacts exist, are substantive, and are wired. All 7 key links confirmed. All 5 FLINK requirements (FLINK-01, FLINK-04, FLINK-05, FLINK-06, FLINK-07) are satisfied.

The one info-level finding (unused `prevent_destroy` variable in `modules/flink/variables.tf`) does not affect goal achievement. The lifecycle protection it was intended to expose is already hardcoded correctly in `main.tf`.

---

_Verified: 2026-03-27_
_Verifier: Claude (gsd-verifier)_

---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: unknown
stopped_at: Phase 8 context gathered
last_updated: "2026-03-27T21:12:37.047Z"
progress:
  total_phases: 9
  completed_phases: 7
  total_plans: 21
  completed_plans: 21
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-21)

**Core value:** Any FSI team can stand up a fully governed, observable, DR-ready Kafka/Flink/SR cluster in their deployment model of choice with a single automation run -- and onboard their first topic in under a day.
**Current focus:** Phase 07 — onboarding-and-developer-experience

## Current Position

Phase: 8
Plan: Not started

## Performance Metrics

**Velocity:**

- Total plans completed: 0
- Average duration: -
- Total execution time: 0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| - | - | - | - |

**Recent Trend:**

- Last 5 plans: -
- Trend: -

*Updated after each plan completion*
| Phase 01 P03 | 2min | 2 tasks | 3 files |
| Phase 01 P02 | 3min | 2 tasks | 4 files |
| Phase 01 P01 | 4min | 2 tasks | 7 files |
| Phase 02 P01 | 4min | 2 tasks | 19 files |
| Phase 02 P02 | 3min | 2 tasks | 10 files |
| Phase 03 P04 | 2min | 2 tasks | 3 files |
| Phase 03 P01 | 3min | 2 tasks | 4 files |
| Phase 03 P02 | 5min | 2 tasks | 11 files |
| Phase 03 P03 | 4min | 2 tasks | 5 files |
| Phase 04 P01 | 5min | 2 tasks | 2 files |
| Phase 04 P02 | 4min | 2 tasks | 2 files |
| Phase 04 P03 | 5min | 2 tasks | 2 files |
| Phase 05 P01 | 7min | 2 tasks | 10 files |
| Phase 05 P03 | 7min | 2 tasks | 11 files |
| Phase 05 P02 | 7min | 2 tasks | 15 files |
| Phase 06 P02 | 2min | 2 tasks | 5 files |
| Phase 06 P01 | 3min | 2 tasks | 9 files |
| Phase 06 P03 | 17min | 2 tasks | 9 files |
| Phase 07 P01 | 3min | 2 tasks | 4 files |
| Phase 07 P02 | 6min | 2 tasks | 11 files |
| Phase 07 P03 | 4min | 2 tasks | 4 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- Roadmap: Governance foundation first to prevent drift across deployment models (research recommendation)
- Roadmap: CC multi-cloud before on-prem (lower risk, extends proven pattern)
- Roadmap: Flink before CFK/CP (CC Flink is managed, proves integration pattern first)
- Roadmap: GOV ADRs in Phase 1 (decisions must be documented before implementation they govern)
- [Phase 01]: OAuth/OAUTHBEARER is primary auth for CC; API keys as fallback for on-prem and Terraform provider (ADR-006)
- [Phase 01]: Topic naming follows {domain}.{application}.{version}.{entity} with dot separators (ADR-007)
- [Phase 01]: DR tier classification maps 4 SLA tiers to RPO/RTO targets with deployment-model-specific backends (ADR-008)
- [Phase 01]: Python stdlib only for schema validation (no pip deps in CI)
- [Phase 01]: SR compatibility check is continue-on-error (graceful degradation)
- [Phase 01]: Override detection excludes modules/ to avoid false positives
- [Phase 01]: Namespace pattern: org.fsi.{domain}.{app}.v{N} (entity is record name)
- [Phase 01]: Used -1 infinite retention for compliance tier instead of calculating 7 years in ms
- [Phase 01]: Renamed reserved variable 'version' to 'schema_version' for Terraform 1.5+ compatibility
- [Phase 01]: Externalized cluster config to auto.tfvars pattern (secrets in terraform.tfvars, metadata in clusters.auto.tfvars)
- [Phase 02]: Scenario directories are fully self-contained with cloud-native backends (azurerm, s3+dynamodb, gcs)
- [Phase 02]: GCS backend uses built-in locking (no DynamoDB equivalent needed for GCP)
- [Phase 02]: Reusable workflow uses mode input (plan/apply) to select job execution path
- [Phase 02]: Post-apply validation conditional on kafka-rest-endpoint input (graceful skip if not configured)
- [Phase 02]: Old CI workflows deprecated with environments/** path (no longer triggers)
- [Phase 03]: Job summary uses always() condition for audit trail even on validation skip/fail
- [Phase 03]: Generic FSI control categories for compliance guide (teams map to OCC/FFIEC/PRA/MAS/APRA)
- [Phase 03]: Relaxed producer_service_accounts validation to allow empty default; cross-variable validation via lifecycle precondition
- [Phase 03]: API keys NOT created in topic module (security: avoids secrets in Terraform state)
- [Phase 03]: Create-or-reference SA pattern uses effective_*_sa_ids locals abstraction for RBAC binding parity
- [Phase 03]: OAuth identity pools use group-based CEL filters for security (not broad audience-only)
- [Phase 03]: Vault reference patterns use commented-out HCL in .example files (not active Terraform)
- [Phase 03]: Cloud-native secret managers documented but not Terraform-ized (per D-07)
- [Phase 03]: CSFLE KEK defaults shared=true for Connect/ksqlDB compatibility (configurable via csfle_shared_kek)
- [Phase 03]: Compliance retention floor at 7 years per FSI regulatory requirements; default -1 infinite for backward compatibility
- [Phase 03]: Confidential topic constraints enforced via lifecycle preconditions (cross-variable validation not possible in TF variable blocks)
- [Phase 04]: Used function-based threshold lookup instead of declare -A associative arrays for Bash 3.2 compatibility (macOS default)
- [Phase 04]: Backend dispatch uses init_backend() called at source time; load_env() deferred to command execution for test compatibility
- [Phase 04]: Rollback instructions print guidance per step but never auto-rollback (D-06: too dangerous for production DR)
- [Phase 04]: All confluent CLI calls use explicit --cluster and --environment flags to avoid global context leakage (Pitfall 4)
- [Phase 04]: DNS endpoint verification retries up to 10 times with 3s sleep for Consul propagation delay
- [Phase 04]: Failback uses two-phase mirror operations (truncate-and-restore then reverse-and-start) matching existing mirror-failback.sh pattern
- [Phase 04]: Two confirmation gates at destructive operations: truncate-and-restore and reverse-and-start, bypassed by --force
- [Phase 04]: Mirror sync wait uses per-tier warn thresholds from ADR-008, with configurable timeout via FSI_DR_SYNC_TIMEOUT
- [Phase 04]: DR runbook is self-contained for on-call use: includes env vars, SLA tiers, decision trees, step procedures, troubleshooting, recovery scenarios
- [Phase 05]: Grafana JSON dashboard model format for native import via UI or API
- [Phase 05]: PromQL queries use confluent_kafka_server_ prefix matching CC Metrics API Prometheus export
- [Phase 05]: Connect Status uses JSON API datasource (REST API polling), not Prometheus
- [Phase 05]: Alert thresholds taken directly from ADR-008/fsi-dr.sh for CLI-dashboard consistency
- [Phase 05]: Per-provider directory pattern: observability/{provider}/ with dashboards + alerts + README
- [Phase 05]: New Relic uses NerdGraph dashboardCreate mutation and alertsNrqlConditionStaticCreate for import
- [Phase 05]: Instana severity model: 5=warning, 10=critical; mirror lag uses ms in conditionValue
- [Phase 05]: .env.example section 11 restructured into 8 sub-sections (11a-11h) covering all 6 providers
- [Phase 05]: Dynatrace uses ext: metric prefix for CC Metrics API ingested metrics with DQL queries
- [Phase 05]: Datadog uses native Confluent Cloud integration tile for metrics ingestion
- [Phase 05]: Splunk uses Simple XML format (not Dashboard Studio) for broadest version compatibility
- [Phase 05]: All 3 providers maintain identical threshold values matching Grafana alerts.yaml and ADR-008
- [Phase 06]: CC Flink SQL templates use auto-discovered tables (no CREATE TABLE with connector/format)
- [Phase 06]: DLQ pattern uses CC-specific error-handling.mode table properties, not Apache Flink side outputs
- [Phase 06]: FSI domain examples span corebanking, fraud, and compliance domains for reference SQL templates
- [Phase 06]: Flink module uses for_each on flink_statements map allowing zero statements (pool-only provisioning)
- [Phase 06]: Flink is opt-in via flink_enabled boolean (default false) using count conditional
- [Phase 06]: max_cfu restricted to [5, 10, 20, 30, 40, 50] with increase-only constraint documented in validation
- [Phase 06]: cc_environment_id passed as dedicated variable, not extracted via regex from cluster ID
- [Phase 06]: CC Metrics API does not expose checkpoint duration -- replaced with pending_records (backpressure proxy) and num_records_out (throughput)
- [Phase 06]: PromQL uses underscore form of CC Flink metrics (io_confluent_flink_num_records_out) since Prometheus scraping replaces dots/slashes
- [Phase 07]: YAML issue form uses generic FSI examples (corebanking, fraud, compliance) -- no client-specific references per D-02
- [Phase 07]: C4E pre-check parses .tf source files via regex, does not require Terraform init or state (Pitfall 7)
- [Phase 07]: C4E pre-check blocks PRs on failure (no continue-on-error) -- human review is final gate, not first check (D-04)
- [Phase 07]: Python uses modern AvroSerializer/AvroDeserializer API (not deprecated AvroProducer/AvroConsumer)
- [Phase 07]: DLQ handler uses separate raw-bytes producer in all 3 languages to avoid serialization coupling
- [Phase 07]: Per-language idiomatic DLQ observability: Java JMX, Python Prometheus, .NET public property
- [Phase 07]: Flink connector version 3.2.0-1.20 chosen over 3.4.0-1.20 for Kafka 3.6/7.6 protocol compatibility
- [Phase 07]: Flink UI mapped to port 8085 (8081 taken by Schema Registry)
- [Phase 07]: RBAC denial test uses ACL authorizer with ANONYMOUS super user + DENY ACL on separate topic
- [Phase 07]: Docker Compose Flink services opt-in via --profile flink (default startup unchanged)

### Pending Todos

None yet.

### Blockers/Concerns

- Phase 6: CC Flink Terraform resources evolving rapidly -- verify GA status before planning
- Phase 8: CFK operator CRD schema for topic management needs investigation
- Phase 9: cp-ansible current state and FIPS 140-2 compatibility need verification
- Phase 9: MRC 2.5-cluster observer promotion needs Confluent engineering validation

## Session Continuity

Last session: 2026-03-27T21:12:37.045Z
Stopped at: Phase 8 context gathered
Resume file: .planning/phases/08-cfk-on-openshift/08-CONTEXT.md

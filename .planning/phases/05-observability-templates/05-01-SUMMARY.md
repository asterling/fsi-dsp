---
phase: 05-observability-templates
plan: 01
subsystem: observability
tags: [grafana, prometheus, promql, alerting, dashboard, jmx, metrics-api, sla-tier]

# Dependency graph
requires:
  - phase: 01-shared-governance-foundation
    provides: "ADR-007 topic naming, ADR-008 DR tier classification, SLA tier thresholds"
  - phase: 04-dr-automation-framework
    provides: "fsi-dr.sh threshold functions, mirror lag monitoring patterns"
provides:
  - "Cross-provider metrics mapping document (observability/metrics-mapping.md)"
  - "5 Grafana dashboard JSON templates (cluster health, consumer lag, connect status, DR readiness, flink jobs stub)"
  - "SLA-tier alert rules for Grafana (alerts.yaml)"
  - "CC Metrics API datasource config (cc-metrics-export.json)"
  - "JMX exporter stub config (jmx-exporter-stub.yaml)"
  - "Grafana import instructions and variable reference (README.md)"
affects: [05-02-dynatrace-datadog, 05-03-splunk-newrelic-instana, 06-flink-runtime, 08-cfk-openshift, 09-cp-rhel]

# Tech tracking
tech-stack:
  added: [grafana-dashboard-json, grafana-alerting-yaml, prometheus-jmx-exporter, cc-metrics-api]
  patterns: [per-provider-template-directory, sla-tier-threshold-driven-alerting, domain-prefix-auto-discovery]

key-files:
  created:
    - observability/metrics-mapping.md
    - observability/grafana/dashboard-cluster-health.json
    - observability/grafana/dashboard-consumer-lag.json
    - observability/grafana/dashboard-connect-status.json
    - observability/grafana/dashboard-dr-readiness.json
    - observability/grafana/dashboard-flink-jobs.json
    - observability/grafana/alerts.yaml
    - observability/grafana/cc-metrics-export.json
    - observability/grafana/jmx-exporter-stub.yaml
    - observability/grafana/README.md
  modified: []

key-decisions:
  - "Grafana JSON dashboard model format for native import via UI or API"
  - "PromQL queries using confluent_kafka_server_ prefix for CC Metrics API Prometheus export"
  - "JSON API datasource for Connect status instead of Prometheus (REST API polling)"
  - "SLA-tier thresholds from ADR-008/fsi-dr.sh used directly in alert rules"
  - "Flink Jobs dashboard included as stub with Phase 6 wiring notice"

patterns-established:
  - "Per-provider directory pattern: observability/{provider}/ with dashboards + alerts + README"
  - "Template variable naming: CLUSTER_ID, DOMAIN_PREFIX, ENVIRONMENT, SLA_TIER across all dashboards"
  - "Dashboard UID pattern: fsi-kafka-{panel-name-kebab}"
  - "Dashboard title pattern: FSI Kafka - {Panel Name}"
  - "SLA-tier alert grouping: separate alert rules per tier with tier-specific thresholds"
  - "Auto-discovery via domain prefix wildcard: topic=~DOMAIN_PREFIX.*"

requirements-completed: [OBS-02, OBS-07, OBS-08, OBS-09, OBS-10]

# Metrics
duration: 7min
completed: 2026-03-26
---

# Phase 5 Plan 1: Grafana Dashboard Templates Summary

**Cross-provider metrics mapping with all 6 providers, plus 5 Grafana dashboard JSONs, SLA-tier alert rules, CC Metrics API datasource, JMX exporter stub, and import README**

## Performance

- **Duration:** 7 min
- **Started:** 2026-03-26T21:00:00Z
- **Completed:** 2026-03-26T21:07:26Z
- **Tasks:** 2
- **Files modified:** 10

## Accomplishments

- Cross-provider metrics mapping document covering CC Metrics API names mapped to Grafana (PromQL), Dynatrace (DQL), Datadog, Splunk (SPL), New Relic (NRQL), and IBM Instana query syntax across all 5 dashboard panels
- 5 Grafana dashboard JSON templates with consistent template variables (CLUSTER_ID, DOMAIN_PREFIX, ENVIRONMENT, SLA_TIER), proper UIDs, and threshold coloring matching UI-SPEC
- SLA-tier-aware alert rules covering mirror lag (4 tiers), consumer lag (4 tiers), Connect task failures, and cluster health (under-replicated partitions, no active controller)
- CC Metrics API Prometheus datasource config and JMX exporter stub for CFK/CP deployments
- README with step-by-step import instructions, complete variable table, and SLA tier threshold reference

## Task Commits

Each task was committed atomically:

1. **Task 1: Create cross-provider metrics mapping and Grafana dashboard templates** - `8293b1b` (feat)
2. **Task 2: Create Grafana alert rules, metrics export configs, and README** - `af9c67d` (feat)

## Files Created/Modified

- `observability/metrics-mapping.md` - Cross-provider metric name to query mapping for all 6 providers
- `observability/grafana/dashboard-cluster-health.json` - Broker connections, URP, request rate, active controller, per-broker partitions
- `observability/grafana/dashboard-consumer-lag.json` - Consumer group lag with domain prefix auto-discovery, per-partition breakdown, SLA-tier thresholds
- `observability/grafana/dashboard-connect-status.json` - Connector state via REST API with auto-discovery, FAILED count, state history
- `observability/grafana/dashboard-dr-readiness.json` - Mirror lag per topic, DR health gauge, per-topic assessment, SLA-tier thresholds from ADR-008
- `observability/grafana/dashboard-flink-jobs.json` - Stub dashboard with Phase 6 wiring notice for jobs, checkpoints, backpressure, throughput
- `observability/grafana/alerts.yaml` - 22 alert rules across 4 groups (mirror lag, consumer lag, connect, cluster health)
- `observability/grafana/cc-metrics-export.json` - Grafana Prometheus datasource pointing to CC Metrics API export endpoint
- `observability/grafana/jmx-exporter-stub.yaml` - JMX exporter config for CFK/CP deployments (port 9101)
- `observability/grafana/README.md` - Import instructions, variable table, threshold reference, metrics export guidance

## Decisions Made

- Used Grafana JSON dashboard model format (importable via UI or `POST /api/dashboards/db`) for maximum portability
- PromQL queries use `confluent_kafka_server_` prefix matching the CC Metrics API Prometheus export endpoint naming
- Connect Status dashboard uses JSON API datasource for REST API polling (not Prometheus) since connector state comes from Connect REST API
- Alert threshold values taken directly from ADR-008 and fsi-dr.sh threshold functions to ensure consistency between CLI and dashboard alerting
- Flink Jobs dashboard included as complete stub with panel structure ready for Phase 6 metric wiring

## Deviations from Plan

None -- plan executed exactly as written.

## Known Stubs

| File | Description | Resolution |
|------|-------------|------------|
| `observability/grafana/dashboard-flink-jobs.json` | All 4 panels show no-data state with stub PromQL queries | Phase 6 wires in actual Flink metrics |
| `observability/grafana/jmx-exporter-stub.yaml` | JMX host placeholder `{{JMX_EXPORTER_HOST}}` not wired to actual endpoint | Phase 8 (CFK) and Phase 9 (CP) wire actual JMX endpoints |

These stubs are intentional per the plan (D-03, D-14) and do not prevent this plan's goals from being achieved.

## Issues Encountered

None.

## User Setup Required

None -- no external service configuration required. Templates contain placeholder variables that teams fill in before import per the README instructions.

## Next Phase Readiness

- Grafana provider is the reference implementation for Plans 02 (Dynatrace + Datadog) and 03 (Splunk + New Relic + Instana)
- `observability/metrics-mapping.md` provides the canonical metric-to-query mapping that all other providers reference
- Template variable naming convention and dashboard structure established as the pattern for all 6 providers
- Alert threshold values verified against ADR-008 and fsi-dr.sh -- subsequent provider plans reuse identical values

---
*Phase: 05-observability-templates*
*Completed: 2026-03-26*

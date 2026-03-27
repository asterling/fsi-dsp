---
phase: 06-flink-on-confluent-cloud
plan: 03
subsystem: observability
tags: [flink, grafana, dynatrace, datadog, splunk, newrelic, instana, cc-metrics-api, promql, dashboards, alerts]

# Dependency graph
requires:
  - phase: 05-observability
    provides: Stub Flink panels in all 6 provider dashboards, alert rule patterns, metrics-mapping.md
  - phase: 06-01
    provides: Flink Terraform module with compute pool and statement resources
  - phase: 06-02
    provides: Flink SQL reference templates and DLQ pattern
provides:
  - Real CC Flink metrics wired into all 6 observability provider dashboards (Grafana, Dynatrace, Datadog, Splunk, New Relic, Instana)
  - Flink alert rules in Grafana (pending records warn/critical, throughput drop)
  - Complete metrics-mapping.md with io.confluent.flink/* metric names and per-provider query syntax
  - Flink configuration section in .env.example (CC_FLINK_ENABLED, CC_FLINK_MAX_CFU, CC_FLINK_API_KEY, etc.)
affects: [08-cfk-openshift, 09-cp-rhel]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - CC Metrics API Flink namespace (io.confluent.flink/*) with underscore form in PromQL
    - Pending records as backpressure proxy (CC Flink has no checkpoint duration metric)
    - CFU utilization percentage gauge pattern (current_cfu / max_cfu * 100)

key-files:
  created: []
  modified:
    - observability/grafana/dashboard-flink-jobs.json
    - observability/grafana/alerts.yaml
    - observability/metrics-mapping.md
    - observability/dynatrace/dashboard.json
    - observability/datadog/dashboard.json
    - observability/splunk/dashboard.xml
    - observability/newrelic/dashboard.json
    - observability/instana/dashboard.json
    - .env.example

key-decisions:
  - "CC Metrics API does not expose checkpoint duration -- replaced with pending_records (backpressure proxy) and num_records_out (throughput)"
  - "PromQL uses underscore form of CC metrics (io_confluent_flink_num_records_out) since dots/slashes are replaced during Prometheus scrape"
  - "CFU utilization calculated as current_cfu / max_cfu * 100 with thresholds at 70% (warn) and 90% (critical)"

patterns-established:
  - "Flink observability: io.confluent.flink/* metrics namespace with resource_type labels (flink_statement, flink_compute_pool)"
  - "Pending records as backpressure indicator with thresholds 1000 (warn) and 10000 (critical)"

requirements-completed: [FLINK-06]

# Metrics
duration: 17min
completed: 2026-03-27
---

# Phase 6 Plan 3: Flink Observability Summary

**Real CC Flink metrics (io.confluent.flink/*) wired into all 6 provider dashboards with 3 Grafana alert rules, complete metrics mapping, and Flink env config**

## Performance

- **Duration:** 17 min
- **Started:** 2026-03-27T12:18:41Z
- **Completed:** 2026-03-27T12:35:59Z
- **Tasks:** 2
- **Files modified:** 9

## Accomplishments
- Replaced all Flink stub panels across 6 observability providers with real CC Metrics API queries using io.confluent.flink/* namespace
- Added 3 Flink alert rules to Grafana: pending records warning (>1000), pending records critical (>10000), throughput drop (<1 rec/sec for 10m)
- Updated metrics-mapping.md from stub Apache Flink metric names to real CC Metrics API metric names with per-provider query syntax for all 6 providers
- Added CFU Utilization panel to Grafana and corresponding widgets in New Relic and Instana
- Added Flink configuration section (section 14) to .env.example with 8 variables

## Task Commits

Each task was committed atomically:

1. **Task 1: Update Grafana Flink dashboard and alerts with real CC metrics** - `1bfe1e1` (feat)
2. **Task 2: Update 5 provider dashboards and .env.example with Flink config** - `10cf526` (feat)

## Files Created/Modified
- `observability/grafana/dashboard-flink-jobs.json` - Replaced 5 stub panels with 5 real CC Metrics API panels (Running Statements, Records Throughput, Pending Records, Records Out Per Statement, CFU Utilization)
- `observability/grafana/alerts.yaml` - Added fsi-kafka-flink alert group with 3 rules (pending records warn/alert, throughput drop)
- `observability/metrics-mapping.md` - Replaced Flink stub section with real io.confluent.flink/* metric names and per-provider queries
- `observability/dynatrace/dashboard.json` - Replaced Flink placeholder MARKDOWN tile with DATA_EXPLORER tiles for Records Throughput and Pending Records
- `observability/datadog/dashboard.json` - Replaced Flink stub note widget with timeseries (Records Throughput) and query_value (Pending Records) widgets
- `observability/splunk/dashboard.xml` - Replaced Flink HTML stub with SPL search panels for Records Throughput and Pending Records
- `observability/newrelic/dashboard.json` - Replaced Flink stub page with real NRQL widgets for throughput, pending records, records out, and CFU utilization
- `observability/instana/dashboard.json` - Replaced 5 Flink stub widgets with 4 real metric widgets (throughput, pending, records out, CFU)
- `.env.example` - Added section 14 (FLINK) with CC_FLINK_ENABLED, CC_FLINK_COMPUTE_POOL_NAME, CC_FLINK_MAX_CFU, CC_FLINK_REGION, CC_FLINK_REST_ENDPOINT, CC_FLINK_API_KEY, CC_FLINK_API_SECRET, CC_FLINK_SERVICE_ACCOUNT_ID

## Decisions Made
- CC Metrics API does not expose checkpoint duration metric -- replaced the Phase 5 "Checkpoint Duration" panel with "Records Throughput" and used pending_records as the backpressure proxy. This provides equivalent operational insight for managed Flink.
- PromQL expressions use underscore form of CC metrics (io_confluent_flink_num_records_out) since Prometheus scraping replaces dots and slashes with underscores
- CFU utilization calculated as current_cfu / max_cfu * 100 with green/yellow/red thresholds at 0/70/90 percent

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required. Flink configuration variables added to .env.example for user reference.

## Next Phase Readiness
- Phase 6 (Flink on Confluent Cloud) is now complete across all 3 plans: Terraform module (06-01), SQL templates and DLQ (06-02), and observability (06-03)
- All 6 observability provider dashboards have real Flink metrics -- no stubs remain in any dashboard file
- Future phases (CFK, CP-RHEL) can follow the same pattern of adding provider-specific Flink metrics for their deployment models

## Self-Check: PASSED

All 9 modified files exist, both task commits verified (1bfe1e1, 10cf526), SUMMARY.md created.

---
*Phase: 06-flink-on-confluent-cloud*
*Completed: 2026-03-27*

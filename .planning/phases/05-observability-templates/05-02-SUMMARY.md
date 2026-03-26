---
phase: 05-observability-templates
plan: 02
subsystem: observability
tags: [dynatrace, datadog, splunk, dashboard, alerts, metrics, sla-tier, kafka, monitoring]

# Dependency graph
requires:
  - phase: 05-01
    provides: "Grafana reference dashboards, alerts.yaml with SLA-tier thresholds, metrics-mapping.md, UI-SPEC color/layout contract"
  - phase: 01
    provides: "ADR-008 DR tier classification with mirror lag thresholds, topic naming convention for auto-discovery"
  - phase: 04
    provides: "fsi-dr.sh threshold functions matching alert thresholds"
provides:
  - "Dynatrace dashboard template (dashboard.json) with 5 tile groups and Dynatrace-native DQL queries"
  - "Dynatrace alert definitions (alerts.json) with 19 custom event rules per SLA tier"
  - "Datadog dashboard template (dashboard.json) with 5 widget groups and template variables"
  - "Datadog monitor definitions (monitors.json) with 11 monitors per SLA tier"
  - "Splunk Simple XML dashboard (dashboard.xml) with 5 row sections and SPL queries"
  - "Splunk saved search alerts (alerts.json) with 19 alert definitions per SLA tier"
  - "CC Metrics API export config for all 3 providers"
  - "JMX exporter stub config for all 3 providers (CFK/CP wiring in Phase 8/9)"
  - "README with provider-specific import instructions for all 3 providers"
affects: [05-03, phase-6, phase-8, phase-9]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Per-provider dashboard template pattern: dashboard + alerts + cc-metrics-export + jmx-stub + README"
    - "SLA-tier threshold parity across all providers via ADR-008 values"
    - "Domain prefix wildcard auto-discovery in provider-native query syntax"
    - "Flink stub panel in all providers for Phase 6 wiring"

key-files:
  created:
    - observability/dynatrace/dashboard.json
    - observability/dynatrace/alerts.json
    - observability/dynatrace/cc-metrics-export.json
    - observability/dynatrace/jmx-exporter-stub.json
    - observability/dynatrace/README.md
    - observability/datadog/dashboard.json
    - observability/datadog/monitors.json
    - observability/datadog/cc-metrics-export.json
    - observability/datadog/jmx-exporter-stub.yaml
    - observability/datadog/README.md
    - observability/splunk/dashboard.xml
    - observability/splunk/alerts.json
    - observability/splunk/cc-metrics-export.conf
    - observability/splunk/jmx-exporter-stub.conf
    - observability/splunk/README.md
  modified: []

key-decisions:
  - "Dynatrace uses ext: metric prefix convention for CC Metrics API ingested metrics"
  - "Datadog uses native Confluent Cloud integration tile for metrics ingestion"
  - "Splunk uses scripted input pattern for CC Metrics API with inputs.conf format"
  - "All 3 providers use identical threshold values matching Grafana Plan 01 and ADR-008"
  - "Splunk dashboard uses Simple XML format for broadest compatibility (not Dashboard Studio)"

patterns-established:
  - "Provider directory pattern: observability/{provider}/ with dashboard + alerts + cc-metrics + jmx-stub + README"
  - "Alert naming convention: {MetricCategory}{SLATier} - {Severity} (e.g., MirrorLagCritical - Warning)"
  - "Domain prefix wildcard auto-discovery works across all providers (DQL prefix(), Datadog tag:*, SPL topic=*)"

requirements-completed: [OBS-01, OBS-03, OBS-04]

# Metrics
duration: 7min
completed: 2026-03-26
---

# Phase 5 Plan 02: Dynatrace, Datadog, and Splunk Dashboard Templates Summary

**Dashboard templates for 3 enterprise observability providers with 5-panel structure, SLA-tier alerting parity across all providers, CC Metrics API export configs, and JMX stubs for CFK/CP**

## Performance

- **Duration:** 7 min
- **Started:** 2026-03-26T21:10:06Z
- **Completed:** 2026-03-26T21:17:43Z
- **Tasks:** 2
- **Files created:** 15

## Accomplishments

- Created Dynatrace, Datadog, and Splunk dashboard templates each covering all 5 panels (Cluster Health, Consumer Lag, Connect Status, DR Readiness, Flink Jobs stub)
- All 3 providers use identical SLA-tier alert thresholds matching Grafana Plan 01 and ADR-008 (mirror lag: critical 30s/60s, standard 300s/900s, best-effort 3600s/14400s, compliance 10s/30s; consumer lag: critical 1K/5K, standard 10K/50K, best-effort 100K/500K, compliance 500/2K)
- CC Metrics API export configuration for all 3 providers targeting api.telemetry.confluent.cloud
- JMX exporter stubs on port 9101 for all 3 providers (wired in Phase 8 CFK and Phase 9 CP)
- Domain prefix wildcard auto-discovery in all 3 providers using provider-native query syntax

## Task Commits

Each task was committed atomically:

1. **Task 1: Create Dynatrace and Datadog dashboard templates with alerts and metrics export** - `dbd8b87` (feat)
2. **Task 2: Create Splunk dashboard template with alerts and metrics export** - `60aa83e` (feat)

## Files Created/Modified

- `observability/dynatrace/dashboard.json` - Dynatrace Dashboard API payload with 5 tile groups and DQL queries
- `observability/dynatrace/alerts.json` - 19 custom event alert definitions (mirror lag, consumer lag, connect, cluster health per SLA tier)
- `observability/dynatrace/cc-metrics-export.json` - ActiveGate config for CC Metrics API ingestion
- `observability/dynatrace/jmx-exporter-stub.json` - Dynatrace JMX plugin config for CFK/CP (stub)
- `observability/dynatrace/README.md` - Import instructions, variable table, SLA tier thresholds
- `observability/datadog/dashboard.json` - Datadog Dashboard API payload with 5 widget groups and template variables
- `observability/datadog/monitors.json` - 11 Datadog monitor definitions matching Grafana threshold parity
- `observability/datadog/cc-metrics-export.json` - Confluent Cloud integration config for Datadog
- `observability/datadog/jmx-exporter-stub.yaml` - Datadog Agent JMX check conf.d for CFK/CP (stub)
- `observability/datadog/README.md` - Import instructions, variable table, SLA tier thresholds
- `observability/splunk/dashboard.xml` - Splunk Simple XML dashboard with 5 row sections and SPL queries
- `observability/splunk/alerts.json` - 19 saved search alert definitions for Splunk REST API import
- `observability/splunk/cc-metrics-export.conf` - Splunk inputs.conf scripted input for CC Metrics API
- `observability/splunk/jmx-exporter-stub.conf` - Splunk JMX add-on config for CFK/CP (stub)
- `observability/splunk/README.md` - Import instructions via Web UI and REST API, variable table

## Decisions Made

- Dynatrace uses `ext:` metric prefix convention for externally ingested CC Metrics API metrics, with DQL queries in data explorer tiles
- Datadog leverages native Confluent Cloud integration tile for zero-config metrics ingestion
- Splunk uses scripted input pattern (`inputs.conf`) for CC Metrics API with `confluent_cloud:metrics` sourcetype
- All 3 providers maintain identical threshold values matching Grafana alerts.yaml (Plan 01) and ADR-008 for cross-provider consistency
- Splunk dashboard uses Simple XML format (not Dashboard Studio) for broadest Splunk version compatibility

## Deviations from Plan

None - plan executed exactly as written.

## Known Stubs

| File | Stub | Reason |
|------|------|--------|
| `observability/dynatrace/dashboard.json` | Flink Jobs markdown tile with placeholder text | Flink deployment in Phase 6 |
| `observability/datadog/dashboard.json` | Flink Jobs note widget with placeholder text | Flink deployment in Phase 6 |
| `observability/splunk/dashboard.xml` | Flink Jobs HTML panel with placeholder text | Flink deployment in Phase 6 |
| `observability/dynatrace/jmx-exporter-stub.json` | JMX plugin config (disabled) | CFK wiring in Phase 8, CP in Phase 9 |
| `observability/datadog/jmx-exporter-stub.yaml` | JMX check config (not deployed) | CFK wiring in Phase 8, CP in Phase 9 |
| `observability/splunk/jmx-exporter-stub.conf` | JMX add-on config (disabled=true) | CFK wiring in Phase 8, CP in Phase 9 |

All stubs are intentional and documented. Each has a clear resolution plan in a future phase. None prevent this plan's goal from being achieved.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required. Templates are self-contained JSON/XML/YAML/conf files that teams import into their provider instance.

## Next Phase Readiness

- 4 of 6 observability providers now complete (Grafana from Plan 01, plus Dynatrace/Datadog/Splunk from this plan)
- Plan 03 delivers New Relic and IBM Instana to complete the full provider set
- All providers maintain threshold parity for consistent alerting across organizations using different platforms

---
*Phase: 05-observability-templates*
*Completed: 2026-03-26*

## Self-Check: PASSED

- All 15 created files verified present on disk
- Both task commits (dbd8b87, 60aa83e) verified in git log

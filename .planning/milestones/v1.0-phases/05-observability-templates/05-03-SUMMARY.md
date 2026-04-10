---
phase: 05-observability-templates
plan: 03
subsystem: observability
tags: [newrelic, instana, nrql, nerdgraph, jmx, metrics-api, sla-tier, dashboard, alerting]

# Dependency graph
requires:
  - phase: 05-01-grafana-dashboard-templates
    provides: "Cross-provider metrics mapping, per-provider directory pattern, SLA-tier threshold values"
  - phase: 01-shared-governance-foundation
    provides: "ADR-007 topic naming, ADR-008 DR tier classification, SLA tier thresholds"
  - phase: 04-dr-automation-framework
    provides: "fsi-dr.sh threshold functions, mirror lag monitoring patterns"
provides:
  - "New Relic NerdGraph 5-page dashboard template (dashboard.json)"
  - "New Relic NRQL alert conditions (alerts.json) -- 20 conditions across mirror lag, consumer lag, connect, cluster health"
  - "New Relic CC Metrics API Flex integration config (cc-metrics-export.json)"
  - "New Relic nri-jmx integration stub (jmx-exporter-stub.yaml)"
  - "New Relic import instructions and variable reference (README.md)"
  - "IBM Instana custom dashboard with 5 widget groups (dashboard.json)"
  - "IBM Instana alert configurations (alerts.json) -- 20 alerts with Instana severity model"
  - "IBM Instana CC Metrics API custom metrics source (cc-metrics-export.json)"
  - "IBM Instana JMX sensor stub (jmx-exporter-stub.yaml)"
  - "IBM Instana import instructions and variable reference (README.md)"
  - "Updated .env.example with all 6 observability provider variables (sections 11a-11h)"
affects: [06-flink-runtime, 08-cfk-openshift, 09-cp-rhel]

# Tech tracking
tech-stack:
  added: [newrelic-nerdgraph-api, newrelic-nrql, newrelic-flex-integration, newrelic-nri-jmx, instana-custom-dashboards-api, instana-alert-configs-api, instana-jmx-sensor]
  patterns: [nerdgraph-dashboard-mutation, nrql-alert-conditions, instana-api-payloads, instana-severity-model, expanded-env-example-provider-sections]

key-files:
  created:
    - observability/newrelic/dashboard.json
    - observability/newrelic/alerts.json
    - observability/newrelic/cc-metrics-export.json
    - observability/newrelic/jmx-exporter-stub.yaml
    - observability/newrelic/README.md
    - observability/instana/dashboard.json
    - observability/instana/alerts.json
    - observability/instana/cc-metrics-export.json
    - observability/instana/jmx-exporter-stub.yaml
    - observability/instana/README.md
  modified:
    - .env.example

key-decisions:
  - "New Relic uses NerdGraph dashboardCreate mutation for dashboard import and alertsNrqlConditionStaticCreate for alert conditions"
  - "Instana uses POST /api/custom-dashboards and POST /api/events/settings/alert-configs for import"
  - "Instana alert severity model: 5=warning, 10=critical (mapped from ADR-008 warn/alert thresholds)"
  - "Instana mirror lag thresholds use millisecond values (x1000) in conditionValue since metric is in ms"
  - ".env.example section 11 expanded from 5 lines to 8 sub-sections covering all 6 providers with CC Metrics API credentials"

patterns-established:
  - "NerdGraph mutation pattern for New Relic dashboard and alert import"
  - "Instana custom dashboard API payload format with widget bounds coordinates"
  - "Instana alert severity model mapping: severity 5 = warning, severity 10 = critical"
  - "Provider-specific env variable grouping pattern in .env.example (11a through 11h)"

requirements-completed: [OBS-05, OBS-06]

# Metrics
duration: 7min
completed: 2026-03-26
---

# Phase 5 Plan 3: New Relic and Instana Dashboard Templates Summary

**New Relic NerdGraph 5-page dashboard and Instana custom dashboard with 20 NRQL/threshold alert conditions each, CC Metrics API configs, JMX stubs, and .env.example expanded to cover all 6 observability providers**

## Performance

- **Duration:** 7 min
- **Started:** 2026-03-26T21:10:10Z
- **Completed:** 2026-03-26T21:17:06Z
- **Tasks:** 2
- **Files modified:** 11

## Accomplishments

- New Relic NerdGraph dashboard template with 5 pages (Cluster Health, Consumer Lag, Connect Status, DR Readiness, Flink Jobs stub) using NRQL queries referencing KafkaBrokerSample, KafkaConsumerSample, KafkaConnectSample, KafkaClusterLinkSample, and ConfluentCloudMetric event types
- IBM Instana custom dashboard template with 5 widget groups, 22 widgets total, using Instana metrics API filter expressions with STARTS_WITH for domain prefix auto-discovery
- 20 alert conditions for each provider covering mirror lag (4 SLA tiers x 2 severities), consumer lag (4 tiers x 2 severities), ConnectTaskFailed, ConnectTaskRestartLoop, and UnderReplicatedPartitions -- all thresholds matching Grafana Plan 01 values
- CC Metrics API export configs (New Relic Flex integration, Instana custom metrics source) and JMX exporter stubs for both providers
- .env.example section 11 expanded from 5 lines to 8 sub-sections (11a-11h) covering all 6 providers with provider-specific variables and CC Metrics API credentials

## Task Commits

Each task was committed atomically:

1. **Task 1: Create New Relic and IBM Instana dashboard templates with alerts and metrics export** - `9b12620` (feat)
2. **Task 2: Update .env.example with New Relic and Instana provider variables** - `cb50a32` (feat)

## Files Created/Modified

- `observability/newrelic/dashboard.json` - NerdGraph dashboardCreate mutation payload with 5 pages, NRQL queries, layout grid coordinates
- `observability/newrelic/alerts.json` - 20 NRQL alert conditions with SLA-tier thresholds matching ADR-008
- `observability/newrelic/cc-metrics-export.json` - New Relic Flex integration config for CC Metrics API
- `observability/newrelic/jmx-exporter-stub.yaml` - nri-jmx integration config for CFK/CP deployments (port 9101)
- `observability/newrelic/README.md` - Import instructions, NerdGraph mutations, template variables, SLA tier thresholds
- `observability/instana/dashboard.json` - Instana custom dashboard API payload with 22 widgets in 5 groups, bounds coordinates
- `observability/instana/alerts.json` - 20 Instana alert configs with severity 5 (warning) and 10 (critical), threshold rules
- `observability/instana/cc-metrics-export.json` - Instana custom metrics source for CC Metrics API with basic auth
- `observability/instana/jmx-exporter-stub.yaml` - Instana JMX sensor config with custom MBean definitions (port 9101)
- `observability/instana/README.md` - Import instructions, curl examples, template variables, SLA tier thresholds
- `.env.example` - Section 11 expanded: 6 provider sub-sections (Dynatrace, Datadog, Splunk, Prometheus/Grafana, New Relic, Instana), common thresholds, CC Metrics API

## Decisions Made

- New Relic uses NerdGraph dashboardCreate mutation (not REST API) for dashboard import, aligning with New Relic One's GraphQL-first approach
- Instana uses POST /api/custom-dashboards for dashboard import and POST /api/events/settings/alert-configs for alert creation
- Instana alert severity model maps to ADR-008: severity=5 for warning thresholds, severity=10 for critical thresholds
- Instana mirror lag conditionValue uses milliseconds (e.g., 30000 for 30s) since the underlying metric is in ms
- .env.example section 11 restructured into sub-sections 11a-11h with per-provider grouping for clarity and all 6 providers represented

## Deviations from Plan

None -- plan executed exactly as written.

## Known Stubs

| File | Description | Resolution |
|------|-------------|------------|
| `observability/newrelic/dashboard.json` (Flink Jobs page) | 4 widgets show stub NRQL queries referencing FlinkMetric event type | Phase 6 wires in actual Flink metrics |
| `observability/newrelic/jmx-exporter-stub.yaml` | JMX host placeholder `{{JMX_EXPORTER_HOST}}` not wired to actual endpoint | Phase 8 (CFK) and Phase 9 (CP) wire actual JMX endpoints |
| `observability/instana/dashboard.json` (Flink Jobs widgets) | 4 widgets show stub metric queries for Flink | Phase 6 wires in actual Flink metrics |
| `observability/instana/jmx-exporter-stub.yaml` | JMX host placeholder `{{JMX_EXPORTER_HOST}}` not wired to actual endpoint | Phase 8 (CFK) and Phase 9 (CP) wire actual JMX endpoints |

These stubs are intentional per the plan (D-03, D-14) and do not prevent this plan's goals from being achieved.

## Issues Encountered

None.

## User Setup Required

None -- no external service configuration required. Templates contain placeholder variables that teams fill in before import per the README instructions.

## Next Phase Readiness

- All 6 observability providers now have complete dashboard templates (Grafana, Dynatrace, Datadog, Splunk, New Relic, Instana)
- .env.example covers all provider-specific configuration variables
- Phase 5 observability-templates is now complete
- Ready for Phase 6 (Flink runtime) to wire Flink metrics into all 6 provider templates

## Self-Check: PASSED

All 11 files verified present on disk. Both task commits (9b12620, cb50a32) verified in git history.

---
*Phase: 05-observability-templates*
*Completed: 2026-03-26*

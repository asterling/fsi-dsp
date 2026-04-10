# Phase 5: Observability Templates - Context

**Gathered:** 2026-03-26
**Status:** Ready for planning

<domain>
## Phase Boundary

Pre-built dashboard templates for 6 observability providers (Dynatrace, Prometheus/Grafana, Datadog, Splunk, New Relic, IBM Instana) covering cluster health, consumer lag, Connect status, DR readiness, and Flink job health. Includes SLA-tier-based alerting with visual thresholds, auto-discovery for new topics by domain prefix, and metrics export configuration per deployment model (CC Metrics API for cloud, JMX exporter stubs for CFK/CP). Does NOT implement the Flink deployment itself (Phase 6) or CFK/CP deployments (Phases 8/9).

</domain>

<decisions>
## Implementation Decisions

### Dashboard Structure
- **D-01:** Unified 5-panel layout across all 6 providers: Cluster Health, Consumer Lag, Connect Status, DR Readiness, Flink Jobs. Consistent experience regardless of provider.
- **D-02:** Domain-level summary with topic drill-down. Top-level shows aggregates by domain prefix (e.g., corebanking.*, fraud.*). Click through to individual topic metrics.
- **D-03:** Flink Jobs panel included as a stub with placeholder metric names. Phase 6 wires in actual Flink metrics. Avoids re-templating all 6 providers later.
- **D-04:** Visual threshold lines and color coding on dashboard panels. Green (OK), yellow (warn), red (alert) derived from ADR-008 SLA-tier thresholds. Thresholds change per SLA tier.

### Template Format & Delivery
- **D-05:** Native import format per provider. JSON for Grafana, JSON/API payload for Dynatrace/Datadog/New Relic/Instana, XML/JSON for Splunk. Teams import using each provider's native mechanism.
- **D-06:** Directory structure: `observability/{provider}/` with subdirectories per provider (dynatrace/, grafana/, datadog/, splunk/, newrelic/, instana/). Each contains dashboard templates + alert rules + README with import instructions.
- **D-07:** Variable placeholders in templates (e.g., `{{DOMAIN_PREFIX}}`, `{{WARN_THRESHOLD}}`) that teams fill in before import. SLA-tier defaults from ADR-008 are pre-filled. README documents each variable.
- **D-08:** Bundled alert rule definitions alongside dashboards in each provider directory. Single import gets both dashboards and alerts.

### Auto-Discovery Rules
- **D-09:** Domain prefix wildcard matching for topic auto-discovery. Dashboards use wildcard queries on topic name prefix (e.g., corebanking.*, fraud.*). New topics matching the prefix appear automatically. Aligns with existing topic naming convention `{domain}.{app}.{version}.{entity}`.
- **D-10:** Auto-discover all Connect connectors via Connect REST API endpoint. New connectors appear automatically. Connect status panel shows RUNNING/PAUSED/FAILED per connector.
- **D-11:** Both primary and mirror topics shown in dashboards with visual distinction (mirror icon or color). DR Readiness panel uses mirror lag between the pair for full visibility.
- **D-12:** Consumer Lag panel grouped by consumer group with topic breakdown. Shows per-partition lag per subscribed topic within each consumer group.

### Metrics Export Strategy
- **D-13:** CC Metrics API export configs for cloud deployments. Configuration examples for each provider to pull from the Confluent Cloud Metrics API. Includes API endpoint, auth, and query templates.
- **D-14:** Stub JMX exporter configs for CFK/CP deployment models. Metric names and panel queries ready. Actual JMX endpoint wiring happens in Phase 8/9.
- **D-15:** Connect metrics sourced via Connect REST API polling (/connectors, /connectors/{name}/status). Works across all deployment models. Already used by fsi-dr CLI.
- **D-16:** Common metrics mapping document (`observability/metrics-mapping.md`) mapping CC metric names to each provider's query syntax. Enables cross-provider parity verification.

### Claude's Discretion
- Exact JSON/template structure per provider's native format
- Grafana panel layout (row arrangement, sizing, variable dropdowns)
- Dynatrace dashboard tile configuration and management zone setup
- Datadog widget types and template variable syntax
- Splunk dashboard XML vs Simple XML vs Dashboard Studio format
- New Relic dashboard widget configuration and NRQL query optimization
- IBM Instana application perspective vs custom dashboard approach
- How placeholder variables are substituted (sed, envsubst, or provider-native templating)
- README structure and import instruction detail level per provider

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### SLA Tier Thresholds (alert threshold source)
- `docs/adr/008-dr-tier-classification.md` -- Mirror lag alert thresholds per SLA tier: critical (warn 30s/alert 60s), standard (warn 5m/alert 15m), best-effort (warn 1h/alert 4h), compliance (warn 10s/alert 30s)
- `docs/adr/002-compatibility-by-tier.md` -- SLA tier enum definition (critical/standard/best-effort/compliance)

### Topic Naming (auto-discovery pattern source)
- `docs/adr/007-topic-naming.md` -- Topic naming convention `{domain}.{application}.{version}.{entity}` with dot separators. Domain prefix is the auto-discovery key.

### Existing Observability Config
- `.env.example` lines 93-97 -- `OBSERVABILITY_PROVIDER` env var pattern, `DYNATRACE_ENVIRONMENT_URL`, `ALERT_CL_LAG_SECONDS`, `ALERT_CONSUMER_LAG_RECORDS`
- `reference/local-dev/docker-compose.yml` lines 35-36 -- JMX port 9101 exposure for local Kafka broker

### DR CLI (mirror lag integration)
- `scripts/fsi-dr.sh` -- `fsi-dr status` already displays per-topic mirror lag with SLA-tier-based assessment. Alert threshold functions (`_tier_alert_threshold`, `_tier_warn_threshold`) provide the same thresholds.

### Topic Module (metadata tags source)
- `modules/topic/main.tf` -- Topic metadata tags including sla-tier, domain, owner, data-classification. Tags available for dashboard filtering.
- `modules/topic/variables.tf` -- `sla_tier` variable definition, `domain` variable with naming regex

### Metrics API Reference
- Confluent Cloud Metrics API: `/kafka/v3/clusters/{cluster_id}/metrics` -- Source for CC deployment metrics (broker throughput, partition count, consumer lag)

### Prior Phase Context
- `.planning/phases/04-dr-automation-framework/04-CONTEXT.md` -- DR CLI design, mirror lag monitoring, pre-flight checks
- `.planning/phases/01-shared-governance-foundation/01-CONTEXT.md` -- Shared module library, SLA tier as configuration driver, externalized cluster config

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `scripts/fsi-dr.sh`: SLA-tier threshold lookup functions (`_tier_alert_threshold`, `_tier_warn_threshold`) -- same thresholds should be used in dashboard alert rules for consistency
- `.env.example`: OBSERVABILITY_PROVIDER pattern already supports dynatrace/datadog/splunk/prometheus -- extend with newrelic/instana
- `modules/topic/main.tf`: Topic metadata tags (sla-tier, domain, owner) set at creation time -- available as dashboard filter dimensions

### Established Patterns
- Environment variable-driven configuration: `OBSERVABILITY_PROVIDER` selects which templates to use
- SLA tier as configuration multiplier: thresholds, retention, partitions all derived from tier -- dashboards follow the same pattern
- Domain prefix in topic naming: `{domain}.{app}.{version}.{entity}` -- natural grouping key for dashboard aggregation
- JMX port 9101 in local dev Docker Compose -- JMX exporter configs should target this port for CFK/CP

### Integration Points
- `observability/` -- New top-level directory with 6 provider subdirectories
- `observability/metrics-mapping.md` -- New cross-provider metrics reference
- `.env.example` -- Add provider-specific variables (DATADOG_API_KEY, SPLUNK_HEC_URL, etc.)
- Each provider directory integrates with its native import mechanism (Grafana API, Dynatrace API, etc.)

</code_context>

<specifics>
## Specific Ideas

- Dashboard panels should use the same SLA-tier thresholds as `fsi-dr status` for consistency -- operators should see the same green/yellow/red assessment in dashboards as in CLI output
- The metrics-mapping.md document serves double duty: cross-provider verification AND onboarding reference for teams extending templates
- Flink Jobs panel stub ensures all 6 providers have the 5-panel structure from day one -- Phase 6 fills in the actual metrics without restructuring

</specifics>

<deferred>
## Deferred Ideas

None -- discussion stayed within phase scope

</deferred>

---

*Phase: 05-observability-templates*
*Context gathered: 2026-03-26*

# Phase 5: Observability Templates - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md -- this log preserves the alternatives considered.

**Date:** 2026-03-26
**Phase:** 05-observability-templates
**Areas discussed:** Dashboard structure, Template format & delivery, Auto-discovery rules, Metrics export strategy

---

## Dashboard Structure

| Option | Description | Selected |
|--------|-------------|----------|
| Unified 5-panel layout | Same 5 panels on every provider: Cluster Health, Consumer Lag, Connect Status, DR Readiness, Flink Jobs | :heavy_check_mark: |
| Provider-native grouping | Leverage each provider's strengths -- panels vary per provider but cover same metrics | |
| You decide | Claude picks the approach | |

**User's choice:** Unified 5-panel layout
**Notes:** Consistency across providers prioritized

---

| Option | Description | Selected |
|--------|-------------|----------|
| Domain-level summary with topic drill-down | Top-level shows aggregates by domain prefix, click through to individual topics | :heavy_check_mark: |
| Flat topic-level only | Every topic gets its own row/panel | |
| Cluster-level only | Aggregate metrics only, no per-topic visibility | |

**User's choice:** Domain-level summary with topic drill-down
**Notes:** None

---

| Option | Description | Selected |
|--------|-------------|----------|
| Stub with placeholder metrics | Include Flink Jobs panel structure now with placeholder metric names, Phase 6 wires actual metrics | :heavy_check_mark: |
| Defer entirely to Phase 6 | Only 4 panels now, Phase 6 adds 5th | |
| Full Flink panel now | Include actual Flink metrics now | |

**User's choice:** Stub with placeholder metrics
**Notes:** Avoids re-templating all 6 providers later

---

| Option | Description | Selected |
|--------|-------------|----------|
| Visual threshold lines + color coding | Panels show warn/alert threshold lines from ADR-008. Green/yellow/red color coding. | :heavy_check_mark: |
| Separate alert rules only | Dashboards show raw metrics, thresholds configured separately | |
| You decide | Claude picks per provider | |

**User's choice:** Visual threshold lines + color coding
**Notes:** None

---

## Template Format & Delivery

| Option | Description | Selected |
|--------|-------------|----------|
| Native import format per provider | JSON for Grafana, JSON/API payload for Dynatrace/Datadog/New Relic/Instana, XML/JSON for Splunk | :heavy_check_mark: |
| Terraform-managed dashboards | Use Terraform providers to deploy dashboards as code | |
| You decide | Claude picks per provider | |

**User's choice:** Native import format per provider
**Notes:** Most natural adoption path

---

| Option | Description | Selected |
|--------|-------------|----------|
| observability/{provider}/ directories | Top-level observability/ with subdirectories per provider | :heavy_check_mark: |
| Per-scenario embedding | Each scenario directory gets own observability/ subdirectory | |
| Flat observability/ directory | Single directory with files named by provider | |

**User's choice:** observability/{provider}/ directories
**Notes:** None

---

| Option | Description | Selected |
|--------|-------------|----------|
| Variable placeholders in templates | Templates use {{DOMAIN_PREFIX}}, {{WARN_THRESHOLD}} etc. SLA-tier defaults pre-filled. | :heavy_check_mark: |
| Separate config file | A thresholds.yaml per provider that teams edit | |
| No customization -- SLA-tier defaults only | Hardcode ADR-008 thresholds | |

**User's choice:** Variable placeholders in templates
**Notes:** README documents each variable

---

| Option | Description | Selected |
|--------|-------------|----------|
| Yes -- bundled alert rules | Each provider directory includes dashboards AND alert rule definitions | :heavy_check_mark: |
| Dashboards only -- alert rules documented | Alert config documented in README with copy-paste examples | |
| You decide | Claude determines per provider | |

**User's choice:** Yes -- bundled alert rules
**Notes:** Single import gets full observability

---

## Auto-Discovery Rules

| Option | Description | Selected |
|--------|-------------|----------|
| Domain prefix wildcard matching | Dashboards use wildcard queries on topic name prefix | :heavy_check_mark: |
| Topic metadata tag filtering | Dashboards filter by metadata tags (sla-tier, domain, owner) | |
| Both -- prefix as primary, tags as secondary | Wildcard prefix for discovery, tags for threshold coloring | |

**User's choice:** Domain prefix wildcard matching
**Notes:** Aligns with existing topic naming convention

---

| Option | Description | Selected |
|--------|-------------|----------|
| Auto-discover all connectors | Dashboard queries Connect REST API for all connectors | :heavy_check_mark: |
| Configured connector list | Teams specify which connectors to monitor in config file | |
| You decide | Claude picks per provider | |

**User's choice:** Auto-discover all connectors
**Notes:** None

---

| Option | Description | Selected |
|--------|-------------|----------|
| Both -- primary and mirror with visual distinction | Show primary and mirror topics with mirror icon/color. DR panel uses lag between pair. | :heavy_check_mark: |
| Primary only -- mirrors in DR panel only | Main dashboards show primary only, mirrors in DR Readiness panel | |
| You decide | Claude determines per panel | |

**User's choice:** Both -- primary and mirror with visual distinction
**Notes:** Full visibility

---

| Option | Description | Selected |
|--------|-------------|----------|
| By consumer group with topic breakdown | Groups by consumer group ID, shows subscribed topics and per-partition lag | :heavy_check_mark: |
| By topic with consumer group breakdown | Groups by topic, shows all consumer groups consuming it | |
| Both views available | Two sub-panels, one per grouping | |

**User's choice:** By consumer group with topic breakdown
**Notes:** Aligns with how operators troubleshoot

---

## Metrics Export Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| CC Metrics API export configs | Configuration examples for each provider to pull from CC Metrics API | :heavy_check_mark: |
| CC Metrics API + client-side JMX | CC Metrics API for broker metrics, JMX for application metrics | |
| You decide | Claude determines per deployment model | |

**User's choice:** CC Metrics API export configs
**Notes:** CC-native approach

---

| Option | Description | Selected |
|--------|-------------|----------|
| Stub JMX exporter configs now | Include JMX exporter config templates for CFK/CP. Actual wiring in Phase 8/9. | :heavy_check_mark: |
| CC-only in Phase 5 | CFK/CP configs created in Phase 8/9 | |
| Full JMX exporter configs now | Complete configs now | |

**User's choice:** Stub JMX exporter configs now
**Notes:** Metric names and panel queries ready for Phase 8/9

---

| Option | Description | Selected |
|--------|-------------|----------|
| Connect REST API polling | Query /connectors and /connectors/{name}/status | :heavy_check_mark: |
| JMX metrics from Connect workers | Export Connect worker JMX metrics | |
| Both REST API + JMX | REST for status, JMX for throughput | |

**User's choice:** Connect REST API polling
**Notes:** Already used by fsi-dr CLI, works across all deployment models

---

| Option | Description | Selected |
|--------|-------------|----------|
| Yes -- metrics-mapping.md reference doc | Single document mapping CC metric names to each provider's query syntax | :heavy_check_mark: |
| No -- each provider is self-documented | Each provider README documents its own metrics | |
| You decide | Claude determines if mapping doc adds value | |

**User's choice:** Yes -- metrics-mapping.md reference doc
**Notes:** Enables cross-provider parity verification

---

## Claude's Discretion

- Exact JSON/template structure per provider's native format
- Grafana panel layout, Dynatrace tile configuration, Datadog widget types
- Splunk dashboard format choice (Simple XML vs Dashboard Studio)
- New Relic NRQL query optimization
- IBM Instana application perspective vs custom dashboard approach
- Placeholder variable substitution mechanism
- README detail level per provider

## Deferred Ideas

None -- discussion stayed within phase scope

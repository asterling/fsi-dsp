# FSI Kafka Platform - Dynatrace Observability

## Overview

This directory contains Dynatrace dashboard templates and alert definitions for the FSI Kafka Platform. The templates provide a complete observability solution covering 5 operational panels and SLA-tier-aware alerting.

**Dashboards:**

| # | Panel | Description |
|---|-------|-------------|
| 1 | Cluster Health | Broker connections, under-replicated partitions, active controller, request rate |
| 2 | Consumer Lag | Consumer group lag (records) with domain prefix auto-discovery, per-partition breakdown |
| 3 | Connect Status | Connector state (RUNNING/PAUSED/FAILED/UNASSIGNED) via Connect REST API |
| 4 | DR Readiness | Mirror lag per topic with SLA-tier threshold visualization |
| 5 | Flink Jobs | Running jobs, checkpoint duration, backpressure, records throughput, pending records, CFU utilization via CC Metrics API |

**Alert rules:** `alerts.json` -- SLA-tier-specific alert definitions for mirror lag, consumer lag, Connect task failures, and cluster health.

**Metrics export:** `cc-metrics-export.json` (Confluent Cloud Metrics API ActiveGate config) and `jmx-exporter-config.json` (JMX plugin for CFK/CP deployments).

## Prerequisites

- Dynatrace SaaS or Managed environment
- ActiveGate configured for CC Metrics API ingestion (for Confluent Cloud deployments)
- Management zone configured for Kafka infrastructure (recommended)
- For Connect Status: ActiveGate extension or HTTP check polling the Connect REST API
- For CFK/CP deployments: Dynatrace OneAgent with JMX plugin (port 9101)

## Import Instructions

### Dashboard

1. **Copy** `dashboard.json` template
2. **Replace placeholder variables** (see Template Variables table below)
3. **Import via Dynatrace API:**
   ```bash
   curl -X POST "https://{your-environment}.live.dynatrace.com/api/config/v1/dashboards" \
     -H "Authorization: Api-Token {your-api-token}" \
     -H "Content-Type: application/json" \
     -d @dashboard.json
   ```
   Or use the Dashboard Settings UI: Settings > Dashboards > Upload
4. **Verify data appears within 5 minutes** after import

### Alert Rules

1. **Copy** `alerts.json` template
2. **Replace** `{{CLUSTER_ID}}` with your Kafka cluster ID
3. **Import each alert** via Dynatrace Settings API v2:
   ```bash
   for alert in $(jq -c '.[]' alerts.json); do
     curl -X POST "https://{your-environment}.live.dynatrace.com/api/v2/settings/objects" \
       -H "Authorization: Api-Token {your-api-token}" \
       -H "Content-Type: application/json" \
       -d "$alert"
   done
   ```
4. **Verify alerts** in Settings > Anomaly detection > Custom events for alerting

### Metrics Export (CC Deployments)

1. Obtain a Cloud API key from Confluent Cloud console
2. Replace `{{CC_METRICS_API_KEY}}` and `{{CC_METRICS_API_SECRET}}` in `cc-metrics-export.json`
3. Configure an ActiveGate extension using the config, or set up a collector script that pushes metrics to the Dynatrace API v2 metrics ingest endpoint
4. Verify metrics appear in Dynatrace under Metrics Explorer with prefix `ext:io.confluent.kafka.server`

## Template Variables

| Variable | Default Value | Description |
|----------|--------------|-------------|
| `{{CLUSTER_ID}}` | (empty -- must fill) | Target Kafka cluster ID (e.g., lkc-xxxxx for CC) |
| `{{DOMAIN_PREFIX}}` | `*` | Topic domain filter pattern (e.g., corebanking, fraud, or * for all) |
| `{{ENVIRONMENT}}` | `prod` | Environment label (prod, staging, dev) |
| `{{MANAGEMENT_ZONE}}` | (empty -- must fill) | Dynatrace management zone name for dashboard filtering |
| `{{MANAGEMENT_ZONE_ID}}` | (empty -- must fill) | Dynatrace management zone ID |
| `{{CONNECT_REST_URL}}` | `http://connect.internal:8083` | Kafka Connect REST API endpoint |
| `{{CC_METRICS_API_KEY}}` | (empty -- must fill) | Confluent Cloud Metrics API key |
| `{{CC_METRICS_API_SECRET}}` | (empty -- must fill) | Confluent Cloud Metrics API secret |
| `{{JMX_EXPORTER_HOST}}` | `localhost` | JMX exporter host for CFK/CP deployments |

## SLA Tier Alert Thresholds

Threshold values from [ADR-008: DR Tier Classification](../../docs/adr/008-dr-tier-classification.md) and `scripts/fsi-dr.sh` threshold functions.

### Mirror Lag Thresholds

| SLA Tier | Warn Threshold | Alert Threshold | DR Priority |
|----------|---------------|-----------------|-------------|
| critical | 30 seconds | 60 seconds | P1 -- immediate failover |
| standard | 5 minutes (300s) | 15 minutes (900s) | P2 -- business hours |
| best-effort | 1 hour (3600s) | 4 hours (14400s) | P3 -- next business day |
| compliance | 10 seconds | 30 seconds | P1 -- immediate failover |

### Consumer Lag Thresholds

| SLA Tier | Warn (records) | Alert (records) |
|----------|---------------|----------------|
| critical | 1,000 | 5,000 |
| standard | 10,000 | 50,000 |
| best-effort | 100,000 | 500,000 |
| compliance | 500 | 2,000 |

### Connect Task Failure Thresholds

| Condition | Threshold | Severity |
|-----------|-----------|----------|
| Any task in FAILED state | >= 1 task | Critical (all tiers) |
| Task restart count | >= 3 restarts in 15 minutes | Warning |

## Dashboard Files

| File | Format | Purpose |
|------|--------|---------|
| `dashboard.json` | Dynatrace Dashboard API JSON | All 5 panels in a single dashboard |
| `alerts.json` | Dynatrace Settings API v2 JSON | SLA-tier alert definitions |
| `cc-metrics-export.json` | ActiveGate config JSON | CC Metrics API ingestion config |
| `jmx-exporter-config.json` | Dynatrace JMX plugin JSON | JMX metric collection for CFK/CP |

## Flink Jobs Panel

The Flink Jobs panel uses `io.confluent.flink/*` metrics from the CC Metrics API to visualize running jobs, checkpoint duration, backpressure, records throughput, pending records, and CFU utilization.

See `observability/metrics-mapping.md` for cross-provider query equivalents.

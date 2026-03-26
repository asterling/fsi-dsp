# FSI Kafka Platform - Datadog Observability

## Overview

This directory contains Datadog dashboard templates and monitor definitions for the FSI Kafka Platform. The templates provide a complete observability solution covering 5 operational panels and SLA-tier-aware alerting.

**Dashboards:**

| # | Panel | Description |
|---|-------|-------------|
| 1 | Cluster Health | Broker connections, under-replicated partitions, active controller, request rate |
| 2 | Consumer Lag | Consumer group lag (records) with domain prefix auto-discovery, per-partition breakdown |
| 3 | Connect Status | Connector state (RUNNING/PAUSED/FAILED/UNASSIGNED) via Connect REST API or integration |
| 4 | DR Readiness | Mirror lag per topic with SLA-tier threshold markers |
| 5 | Flink Jobs | Stub -- placeholder structure for Phase 6 |

**Monitors:** `monitors.json` -- SLA-tier-specific monitor definitions for mirror lag, consumer lag, Connect task failures, and cluster health.

**Metrics export:** `cc-metrics-export.json` (Confluent Cloud integration config) and `jmx-exporter-stub.yaml` (Datadog JMX check for CFK/CP deployments).

## Prerequisites

- Datadog account with API key and Application key
- Confluent Cloud integration enabled (for CC deployments) or Datadog Agent with JMX check (for CFK/CP)
- For Connect Status: Datadog Kafka Connect integration or custom check polling the Connect REST API
- For CFK/CP deployments: Datadog Agent with JMX check configuration (port 9101)

## Import Instructions

### Dashboard

1. **Copy** `dashboard.json` template
2. **Replace placeholder variables** (see Template Variables table below)
3. **Import via Datadog API:**
   ```bash
   curl -X POST "https://api.datadoghq.com/api/v1/dashboard" \
     -H "DD-API-KEY: {your-api-key}" \
     -H "DD-APPLICATION-KEY: {your-app-key}" \
     -H "Content-Type: application/json" \
     -d @dashboard.json
   ```
   Or use the Dashboard UI: Dashboards > New Dashboard > Import Dashboard JSON
4. **Verify data appears within 5 minutes** after import

### Monitors

1. **Copy** `monitors.json` template
2. **Replace** `{{cluster_id}}` with your Kafka cluster ID
3. **Import each monitor** via Datadog API:
   ```bash
   for monitor in $(jq -c '.[]' monitors.json); do
     curl -X POST "https://api.datadoghq.com/api/v1/monitor" \
       -H "DD-API-KEY: {your-api-key}" \
       -H "DD-APPLICATION-KEY: {your-app-key}" \
       -H "Content-Type: application/json" \
       -d "$monitor"
   done
   ```
4. **Verify monitors** in Monitors > Manage Monitors

### Metrics Export (CC Deployments)

1. Go to Datadog Integrations > Confluent Cloud tile
2. Enter your CC API key and secret from `cc-metrics-export.json`
3. Select the Kafka cluster to monitor
4. Verify metrics appear in Metrics Explorer with prefix `confluent_cloud.kafka.server`

## Template Variables

| Variable | Default Value | Description |
|----------|--------------|-------------|
| `$cluster_id` | `*` | Target Kafka cluster ID (e.g., lkc-xxxxx for CC) |
| `$domain_prefix` | `*` | Topic domain filter pattern (e.g., corebanking, fraud, or * for all) |
| `$environment` | `prod` | Environment label (prod, staging, dev) |
| `$sla_tier` | `*` | SLA tier filter (critical, standard, best-effort, compliance) |
| `{{CC_METRICS_API_KEY}}` | (empty -- must fill) | Confluent Cloud Metrics API key |
| `{{CC_METRICS_API_SECRET}}` | (empty -- must fill) | Confluent Cloud Metrics API secret |
| `{{CONNECT_REST_URL}}` | `http://connect.internal:8083` | Kafka Connect REST API endpoint |
| `{{JMX_EXPORTER_HOST}}` | `localhost` | JMX exporter host for CFK/CP deployments |
| `{{CLUSTER_ID}}` | (empty -- must fill) | Cluster ID for metrics export and JMX config |
| `{{ENVIRONMENT}}` | `prod` | Environment tag for JMX config |

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
| `dashboard.json` | Datadog Dashboard API JSON | All 5 panel groups in a single dashboard |
| `monitors.json` | Datadog Monitor API JSON | SLA-tier monitor definitions |
| `cc-metrics-export.json` | Integration config JSON | Confluent Cloud integration setup |
| `jmx-exporter-stub.yaml` | Datadog Agent conf.d YAML | JMX check for CFK/CP (stub) |

## Flink Jobs Panel

The Flink Jobs panel is a **stub** with placeholder text. Flink metrics will be available after Phase 6 deployment. The panel structure is in place so Phase 6 only needs to add widget definitions without restructuring the dashboard.

Metrics to be wired in Phase 6:
- `flink_jobmanager_job_uptime` -- Job uptime
- `flink_taskmanager_job_task_checkpointAlignmentTime` -- Checkpoint alignment time
- `flink_taskmanager_job_task_backPressuredTimeMsPerSecond` -- Backpressure
- `flink_taskmanager_job_task_numRecordsOutPerSecond` -- Output throughput

See `observability/metrics-mapping.md` for cross-provider query equivalents.

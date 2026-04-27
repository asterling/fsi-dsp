# FSI Kafka Platform - Grafana Observability

## Overview

This directory contains Grafana dashboard templates and alert rules for the FSI Kafka Platform. The templates provide a complete observability solution covering 5 operational panels and SLA-tier-aware alerting.

**Dashboards:**

| # | Dashboard | File | Description |
|---|-----------|------|-------------|
| 1 | Cluster Health | `dashboard-cluster-health.json` | Broker connections, under-replicated partitions, request rate, active controller, per-broker partition count |
| 2 | Consumer Lag | `dashboard-consumer-lag.json` | Consumer group lag (records) with domain prefix auto-discovery, per-partition breakdown, SLA-tier thresholds |
| 3 | Connect Status | `dashboard-connect-status.json` | Connector state (RUNNING/PAUSED/FAILED/UNASSIGNED), task health, auto-discovery via Connect REST API |
| 4 | DR Readiness | `dashboard-dr-readiness.json` | Mirror lag per topic, cluster link health, failover readiness assessment with SLA-tier thresholds |
| 5 | Flink Jobs | `dashboard-flink-jobs.json` | Running jobs, checkpoint duration, backpressure, records throughput, pending records, CFU utilization via CC Metrics API |

**Alert rules:** `alerts.yaml` -- SLA-tier-specific alert rules for mirror lag, consumer lag, Connect task failures, and cluster health.

**Metrics export:** `cc-metrics-export.json` (Confluent Cloud Metrics API datasource) and `jmx-exporter-config.yaml` (JMX exporter for CFK/CP deployments).

## Prerequisites

- Grafana 9.x or later
- Prometheus datasource configured (pointing to CC Metrics API export endpoint or JMX exporter)
- For Connect Status dashboard: [JSON API datasource plugin](https://grafana.com/grafana/plugins/marcusolsson-json-datasource/) (or Infinity plugin)
- For CC deployments: Confluent Cloud Metrics API key (see Metrics Export section)
- For CFK/CP deployments: JMX exporter agent on Kafka brokers (port 9101)
- Connect REST API access for connector monitoring

## Import Instructions

1. **Copy the template file** you want to import (e.g., `dashboard-cluster-health.json`)
2. **Replace placeholder variables** (see Template Variables table below)
3. **Import using Grafana's native mechanism:**
   - **UI:** Dashboards > Import > Upload JSON file
   - **API:** `POST /api/dashboards/db` with the JSON payload
4. **Verify data appears within 5 minutes** after import

For alert rules:

1. Copy `alerts.yaml` to `/etc/grafana/provisioning/alerting/` on your Grafana server
2. Replace `${DS_PROMETHEUS}` with your actual datasource UID
3. Restart Grafana or reload provisioning: `POST /api/admin/provisioning/alerting/reload`
4. Verify alert rules appear in Alerting > Alert rules > FSI Kafka folder

## Template Variables

| Variable | Default Value | Description |
|----------|--------------|-------------|
| `{{CLUSTER_ID}}` | (empty -- must fill) | Target Kafka cluster ID (e.g., lkc-xxxxx for CC, or cluster name for CFK/CP) |
| `{{DOMAIN_PREFIX}}` | `*` | Topic domain filter pattern (e.g., corebanking, fraud, or * for all domains). Used for auto-discovery via wildcard matching on topic name. |
| `{{ENVIRONMENT}}` | `prod` | Environment label (prod, staging, dev) |
| `{{CONNECT_REST_URL}}` | `http://connect.internal:8083` | Kafka Connect REST API endpoint for connector auto-discovery |
| `{{CC_METRICS_API_KEY}}` | (empty -- must fill) | Confluent Cloud Metrics API key (obtain from CC console) |
| `{{CC_METRICS_API_SECRET}}` | (empty -- must fill) | Confluent Cloud Metrics API secret |
| `{{JMX_EXPORTER_HOST}}` | `localhost` | JMX exporter host for CFK/CP deployments |
| `{{JMX_EXPORTER_PORT}}` | `9101` | JMX exporter port (matches docker-compose.yml KAFKA_JMX_PORT) |
| `{{MIRROR_LAG_WARN_CRITICAL}}` | `30` | Mirror lag warn threshold for critical tier (seconds) |
| `{{MIRROR_LAG_ALERT_CRITICAL}}` | `60` | Mirror lag alert threshold for critical tier (seconds) |
| `{{MIRROR_LAG_WARN_STANDARD}}` | `300` | Mirror lag warn threshold for standard tier (seconds) |
| `{{MIRROR_LAG_ALERT_STANDARD}}` | `900` | Mirror lag alert threshold for standard tier (seconds) |
| `{{MIRROR_LAG_WARN_BESTEFFORT}}` | `3600` | Mirror lag warn threshold for best-effort tier (seconds) |
| `{{MIRROR_LAG_ALERT_BESTEFFORT}}` | `14400` | Mirror lag alert threshold for best-effort tier (seconds) |
| `{{MIRROR_LAG_WARN_COMPLIANCE}}` | `10` | Mirror lag warn threshold for compliance tier (seconds) |
| `{{MIRROR_LAG_ALERT_COMPLIANCE}}` | `30` | Mirror lag alert threshold for compliance tier (seconds) |

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
| `dashboard-cluster-health.json` | Grafana JSON | Broker metrics, partition health, controller status |
| `dashboard-consumer-lag.json` | Grafana JSON | Consumer group lag by topic with auto-discovery |
| `dashboard-connect-status.json` | Grafana JSON | Connector state monitoring via REST API |
| `dashboard-dr-readiness.json` | Grafana JSON | Mirror lag, DR health assessment |
| `dashboard-flink-jobs.json` | Grafana JSON | Flink job metrics via `io.confluent.flink/*` CC Metrics API |
| `alerts.yaml` | Grafana alerting YAML | SLA-tier alert rules for all panels |
| `cc-metrics-export.json` | Grafana datasource JSON | CC Metrics API Prometheus datasource config |
| `jmx-exporter-config.yaml` | JMX exporter YAML | JMX metric collection config for CFK/CP |

## Metrics Export

### Confluent Cloud Metrics API (CC deployments)

The `cc-metrics-export.json` file configures a Grafana Prometheus datasource that scrapes the CC Metrics API Prometheus export endpoint.

**Setup:**

1. Obtain a Cloud API key from Confluent Cloud console (Cloud environment > API keys > Add key)
2. Replace `{{CC_METRICS_API_KEY}}` and `{{CC_METRICS_API_SECRET}}` in the datasource config
3. Replace `{{CLUSTER_ID}}` with your Kafka cluster ID
4. Import the datasource via Grafana provisioning or API

**Endpoint:** `https://api.telemetry.confluent.cloud/v2/metrics/cloud/export`

**Multiple clusters:** Create one datasource per cluster with unique names (e.g., "CC Metrics - East", "CC Metrics - West").

### JMX Exporter (CFK/CP deployments)

The `jmx-exporter-config.yaml` file configures Prometheus JMX Exporter to collect Kafka broker metrics.

**Port:** 9101 (matches `reference/local-dev/docker-compose.yml` KAFKA_JMX_PORT)

**Setup:**

1. Deploy the JMX exporter agent alongside your Kafka brokers
2. Point the exporter at the broker's JMX port using this config
3. Configure Prometheus to scrape the exporter endpoint

## Flink Jobs Panel

The Flink Jobs dashboard (`dashboard-flink-jobs.json`) uses `io.confluent.flink/*` metrics from the CC Metrics API to visualize running jobs, checkpoint duration, backpressure, records throughput, pending records, and CFU utilization.

See `observability/metrics-mapping.md` for cross-provider query equivalents.

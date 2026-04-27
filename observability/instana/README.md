# FSI Kafka Platform - IBM Instana Observability

## Overview

This directory contains IBM Instana dashboard templates and alert configurations for the FSI Kafka Platform. The templates provide a complete observability solution covering 5 operational widget groups and SLA-tier-aware alerting.

**Widget Groups:**

| # | Group | Description |
|---|-------|-------------|
| 1 | Cluster Health | Broker count, under-replicated partitions, request rate, active controller, per-broker partitions |
| 2 | Consumer Lag | Consumer group lag (records) with domain prefix auto-discovery, per-partition breakdown, SLA-tier thresholds |
| 3 | Connect Status | Connector state (RUNNING/PAUSED/FAILED/UNASSIGNED), FAILED count, state distribution via REST API |
| 4 | DR Readiness | Mirror lag per topic (seconds), offset lag (records), cluster link state, SLA-tier thresholds |
| 5 | Flink Jobs | Running jobs, checkpoint duration, backpressure, records throughput, pending records, CFU utilization via CC Metrics API |

**Alert configurations:** `alerts.json` -- 20 alert configs covering mirror lag (4 tiers), consumer lag (4 tiers), Connect task failures, and cluster health.

**Metrics export:** `cc-metrics-export.json` (CC Metrics API custom metrics source) and `jmx-exporter-config.yaml` (Instana JMX sensor for CFK/CP deployments).

## Prerequisites

- IBM Instana tenant with custom dashboard and alerting access
- Instana API token (`INSTANA_API_TOKEN`) with configuration write permissions
- Instana host URL (`INSTANA_HOST`)
- Kafka data flowing into Instana via one of:
  - Instana Java agent with Kafka sensor (auto-discovery for on-prem / CFK / CP)
  - Custom metrics ingestion from CC Metrics API (CC deployments)
  - HTTP endpoint monitoring for Connect REST API

## Import Instructions

### Dashboard

1. Copy `dashboard.json`
2. Replace all placeholder variables (see Template Variables table below)
3. Import via Instana API:

```bash
curl -X POST "https://{{INSTANA_HOST}}/api/custom-dashboards" \
  -H "Authorization: apiToken {{INSTANA_API_TOKEN}}" \
  -H "Content-Type: application/json" \
  -d @dashboard.json
```

4. Verify the dashboard appears in Instana > Custom Dashboards
5. Confirm data populates within 5 minutes

### Alert Configurations

1. Copy `alerts.json`
2. Replace placeholder variables
3. Import each alert via Instana API:

```bash
# Import all alerts from the alerts array
for alert in $(cat alerts.json | python3 -c "import json,sys; [print(json.dumps(a)) for a in json.load(sys.stdin)['alerts']]"); do
  curl -X POST "https://{{INSTANA_HOST}}/api/events/settings/alert-configs" \
    -H "Authorization: apiToken {{INSTANA_API_TOKEN}}" \
    -H "Content-Type: application/json" \
    -d "$alert"
done
```

4. Configure alert channels (email, Slack, PagerDuty) in Instana > Settings > Alert Channels
5. Verify alerts appear in Instana > Events > Alert Configurations

## Template Variables

| Variable | Default Value | Description |
|----------|--------------|-------------|
| `{{INSTANA_HOST}}` | (empty -- must fill) | Instana tenant hostname (e.g., instana.internal or unit-tenant.instana.io) |
| `{{INSTANA_API_TOKEN}}` | (empty -- must fill) | Instana API token with configuration write permissions |
| `{{CLUSTER_ID}}` | (empty -- must fill) | Target Kafka cluster ID (e.g., lkc-xxxxx for CC, or cluster name for CFK/CP) |
| `{{DOMAIN_PREFIX}}` | `*` | Topic domain filter pattern (e.g., corebanking, fraud, or * for all domains). Used for auto-discovery via STARTS_WITH filter. |
| `{{ENVIRONMENT}}` | `prod` | Environment label (prod, staging, dev) |
| `{{CONNECT_REST_URL}}` | `http://connect.internal:8083` | Kafka Connect REST API endpoint for connector auto-discovery |
| `{{CC_METRICS_API_KEY}}` | (empty -- must fill) | Confluent Cloud Metrics API key |
| `{{CC_METRICS_API_SECRET}}` | (empty -- must fill) | Confluent Cloud Metrics API secret |
| `{{JMX_EXPORTER_HOST}}` | `localhost` | JMX host for CFK/CP deployments |
| `{{JMX_EXPORTER_PORT}}` | `9101` | JMX exporter port (matches docker-compose.yml KAFKA_JMX_PORT) |

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
| Any task in FAILED state | >= 1 task | Critical (severity 10, all tiers) |
| Task restart count | >= 3 restarts in 15 minutes | Warning (severity 5) |

## Dashboard Files

| File | Format | Purpose |
|------|--------|---------|
| `dashboard.json` | Instana custom dashboard API payload | 5 widget groups: Cluster Health, Consumer Lag, Connect Status, DR Readiness, Flink Jobs |
| `alerts.json` | Instana alert configuration payloads | SLA-tier alert rules for all panels |
| `cc-metrics-export.json` | Instana custom metrics source config | CC Metrics API ingestion |
| `jmx-exporter-config.yaml` | Instana JMX sensor config | JMX metric collection for CFK/CP |

## Metrics Export

### Confluent Cloud Metrics API (CC deployments)

The `cc-metrics-export.json` file configures Instana custom metrics ingestion from the CC Metrics API.

**Setup:**

1. Obtain a Cloud API key from Confluent Cloud console
2. Replace `{{CC_METRICS_API_KEY}}`, `{{CC_METRICS_API_SECRET}}`, and `{{CLUSTER_ID}}` in the config
3. Import via Instana backend configuration or custom metrics API

**Endpoint:** `https://api.telemetry.confluent.cloud/v2/metrics/cloud/export`

### JMX Sensor (CFK/CP deployments)

The `jmx-exporter-config.yaml` file configures the Instana JMX sensor for Kafka broker MBean collection.

**Port:** 9101 (matches `reference/local-dev/docker-compose.yml` KAFKA_JMX_PORT)

**Note:** Instana's Java agent auto-discovers Kafka MBeans when deployed alongside Kafka brokers. This config explicitly defines which custom MBeans to monitor for finer control.

## Flink Jobs Widget Group

The Flink Jobs widgets use `io.confluent.flink/*` metrics from the CC Metrics API to visualize running jobs, checkpoint duration, backpressure, records throughput, pending records, and CFU utilization.

See `observability/metrics-mapping.md` for cross-provider query equivalents.

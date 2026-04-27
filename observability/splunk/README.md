# FSI Kafka Platform - Splunk Observability

## Overview

This directory contains Splunk dashboard templates and alert definitions for the FSI Kafka Platform. The templates provide a complete observability solution covering 5 operational panels and SLA-tier-aware alerting using Splunk Simple XML format.

**Dashboards:**

| # | Panel | Description |
|---|-------|-------------|
| 1 | Cluster Health | Broker connections, under-replicated partitions, active controller, request rate |
| 2 | Consumer Lag | Consumer group lag (records) with domain prefix auto-discovery, per-partition breakdown |
| 3 | Connect Status | Connector state (RUNNING/PAUSED/FAILED/UNASSIGNED) with color-coded table |
| 4 | DR Readiness | Mirror lag per topic with SLA-tier threshold reference |
| 5 | Flink Jobs | Running jobs, checkpoint duration, backpressure, records throughput, pending records, CFU utilization via CC Metrics API |

**Alert rules:** `alerts.json` -- Splunk saved search / alert definitions for mirror lag, consumer lag, Connect task failures, and cluster health.

**Metrics export:** `cc-metrics-export.conf` (Splunk scripted input for CC Metrics API) and `jmx-exporter-config.conf` (Splunk JMX add-on for CFK/CP deployments).

## Prerequisites

- Splunk Enterprise 8.x+ or Splunk Cloud
- Index `kafka` created and configured
- Sourcetypes configured: `confluent_cloud:metrics`, `kafka:connect`, `kafka:jmx`
- For CC deployments: Scripted input or HEC for CC Metrics API ingestion
- For CFK/CP deployments: Splunk Add-on for JMX (Splunkbase) or custom collector
- For Connect Status: Scripted input polling Connect REST API or HEC-ingested connector events

## Import Instructions

### Dashboard

1. **Copy** `dashboard.xml` template
2. **Replace** `$CLUSTER_ID$`, `$DOMAIN_PREFIX$`, `$ENVIRONMENT$`, `$SLA_TIER$` tokens with your values, or leave defaults and use the dashboard input controls
3. **Import via Splunk Web:**
   - Navigate to Dashboards > Create New Dashboard
   - Select "Dashboard (Classic)"
   - Click "Source" (top right)
   - Paste the XML from `dashboard.xml`
   - Click "Save"
4. **Or import via REST API:**
   ```bash
   curl -k -u admin:changeme \
     "https://splunk-host:8089/servicesNS/admin/search/data/ui/views" \
     -d name=fsi_kafka_observability \
     --data-urlencode eai:data@dashboard.xml
   ```
5. **Verify data appears within 5 minutes** after import

### Alert Rules

1. **Copy** `alerts.json` template
2. **Replace** `{{CLUSTER_ID}}`, `{{ALERT_EMAIL}}`, `{{ALERT_WEBHOOK_URL}}` placeholders
3. **Import each alert** via Splunk REST API:
   ```bash
   for alert in $(jq -c '.[]' alerts.json); do
     name=$(echo "$alert" | jq -r '.name')
     curl -k -u admin:changeme \
       "https://splunk-host:8089/servicesNS/admin/search/saved/searches" \
       -d "name=$name" \
       --data-urlencode "search=$(echo "$alert" | jq -r '.search')" \
       -d "is_scheduled=1" \
       -d "cron_schedule=$(echo "$alert" | jq -r '.cron_schedule')"
   done
   ```
4. **Verify alerts** in Settings > Searches, reports, and alerts

### Metrics Export (CC Deployments)

1. Deploy the collector script `cc_metrics_collector.py` to `$SPLUNK_HOME/etc/apps/fsi_kafka/bin/`
2. Copy `cc-metrics-export.conf` to `$SPLUNK_HOME/etc/apps/fsi_kafka/local/inputs.conf`
3. Replace `{{CC_METRICS_API_KEY}}`, `{{CC_METRICS_API_SECRET}}`, and `{{CLUSTER_ID}}` in the config
4. Restart Splunk or use `splunk reload deploy-server`
5. Verify metrics appear in Search: `index=kafka sourcetype=confluent_cloud:metrics | head 10`

## Template Variables

| Variable | Default Value | Description |
|----------|--------------|-------------|
| `$CLUSTER_ID$` | `*` | Target Kafka cluster ID (Splunk dashboard token) |
| `$DOMAIN_PREFIX$` | `*` | Topic domain filter pattern (e.g., corebanking, fraud, or * for all) |
| `$ENVIRONMENT$` | `prod` | Environment dropdown (prod, staging, dev) |
| `$SLA_TIER$` | `*` | SLA tier filter dropdown |
| `{{CLUSTER_ID}}` | (empty -- must fill) | Cluster ID in alert searches and metrics export config |
| `{{CC_METRICS_API_KEY}}` | (empty -- must fill) | Confluent Cloud Metrics API key |
| `{{CC_METRICS_API_SECRET}}` | (empty -- must fill) | Confluent Cloud Metrics API secret |
| `{{ALERT_EMAIL}}` | (empty -- must fill) | Alert notification email address |
| `{{ALERT_WEBHOOK_URL}}` | (empty -- must fill) | Alert webhook URL (PagerDuty, Slack, etc.) |
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
| `dashboard.xml` | Splunk Simple XML | All 5 row sections in a single dashboard |
| `alerts.json` | JSON (for REST API import) | Saved search / alert definitions |
| `cc-metrics-export.conf` | Splunk inputs.conf | CC Metrics API scripted input config |
| `jmx-exporter-config.conf` | Splunk inputs.conf | JMX data collection for CFK/CP |

## Flink Jobs Panel

The Flink Jobs panel uses `io.confluent.flink/*` metrics from the CC Metrics API to visualize running jobs, checkpoint duration, backpressure, records throughput, pending records, and CFU utilization.

See `observability/metrics-mapping.md` for cross-provider query equivalents.

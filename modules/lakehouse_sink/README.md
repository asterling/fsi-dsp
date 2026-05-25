# `modules/lakehouse_sink`

Confluent Cloud managed connector for Databricks Delta Lake or Snowflake
Snowpipe Streaming. One module call produces:

- `confluent_connector` (managed sink)
- `confluent_service_account` + `confluent_api_key` (connector identity)
- `confluent_role_binding` × 4 (source topic read, DLQ write, SR subject
  read, consumer group read)
- `confluent_kafka_topic` (per-sink DLQ)

## When to use

This module is the **CC-managed path** (DB-C and SF-A). See
[ADR-011](../../docs/adr/011-lakehouse-integration-patterns.md) for the
full decision matrix.

For self-managed CP / CFK / LinuxONE deployments, use the JSON templates
at `reference/connect-configs/databricks-delta-sink-example.json` and
`snowflake-snowpipe-sink-example.json` with the `ansible/roles/cp_*_sink`
roles or CFK `Connector` CRs.

## Usage

```hcl
module "corebanking_to_databricks" {
  source = "../../modules/lakehouse_sink"

  sink_type             = "DatabricksDeltaLakeSink"
  source_topic_name     = module.corebanking_account_txn.topic_name
  target_table          = "fsi_prod.kafka_corebanking.account_transaction"
  databricks_workspace_url = "https://adb-1234567890.123.azuredatabricks.net"
  credentials_secret_ref   = "secret/fsi/databricks#token"
  sla_tier              = "critical"

  environment_id                = local.infra.environment_id
  kafka_cluster_id              = local.infra.kafka_cluster_id
  kafka_cluster_crn             = local.infra.kafka_cluster_crn
  kafka_rest_endpoint           = local.infra.kafka_rest_endpoint
  kafka_api_key                 = var.kafka_api_key
  kafka_api_secret              = var.kafka_api_secret
  schema_registry_cluster_crn   = local.infra.sr_cluster_crn
  schema_registry_rest_endpoint = local.infra.sr_rest_endpoint
}
```

## SLA-tier-derived defaults

| Tier | tasks.max | DLQ partitions | DLQ retention |
|---|---|---|---|
| critical | 6 | 3 | 7 days |
| standard | 3 | 3 | 7 days |
| best-effort | 1 | 3 | 7 days |
| compliance | 6 | 3 | 7 days |

Override `tasks_max_override` for connector throughput tuning. Override
`dlq_retention_ms` if the DLQ itself needs longer retention for compliance
review.

## sink_type matrix

| sink_type | Connector class | Required inputs |
|---|---|---|
| `DatabricksDeltaLakeSink` | `DatabricksDeltaLakeSink` | `databricks_workspace_url`, `target_table` (catalog.schema.table) |
| `SnowflakeSink` | `SnowflakeSink` | `snowflake_account_url`, `snowflake_user`, `target_table` (DATABASE.SCHEMA.TABLE) |

## Connector overrides

The `connector_overrides` map merges last into the final connector
configuration, allowing per-instance tuning without forking the module.
Document the *why* in the calling module.

```hcl
connector_overrides = {
  "flush.interval.ms"   = "1000"  # tighter latency, smaller files
  "max.poll.records"    = "5000"  # batch larger to improve throughput
}
```

## Outputs

| Output | Purpose |
|---|---|
| `connector_name` | Use for cross-module references and dashboard labels |
| `connector_id` | CC resource ID for API access |
| `dlq_topic_name` | Wire downstream DLQ consumer or alerting |
| `service_account_id` | Reference from RBAC modules |
| `service_account_crn` | RBAC binding principal |
| `tasks_max` | Verify effective task count |

## Scoped exception to ADR-004

ADR-004 (Accepted 2026-03-21) selects self-managed on-prem Connect for
enterprise workloads. ADR-011 carves out a narrow exception for CC-managed
lakehouse sinks where the source cluster is CC and the target is a SaaS
lakehouse: in that case there is no on-prem element in the pipeline, and a
managed connector eliminates worker operations entirely.

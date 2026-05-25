# Snowflake Integration Guide

Two supported paths from Kafka to Snowflake. Pick the one that matches your
source cluster deployment model — the decision tree is in
[ADR-011](adr/011-lakehouse-integration-patterns.md).

| Path | Source cluster | Mechanism | Latency | Operational model |
|---|---|---|---|---|
| **SF-A** | CC / CP / CFK / LinuxONE | Snowpipe Streaming Kafka Connector | sub-second to seconds | CC-managed *or* self-managed Connect |
| **SF-B** | Confluent Cloud only | Tableflow → Iceberg → Snowflake Horizon catalog | minutes (materialization cadence) | Zero Connect workers; CC-managed |

If the source cluster is **not** Confluent Cloud, SF-B is unavailable —
Tableflow is a CC-only product. Use SF-A.

---

## SF-A: Snowpipe Streaming Kafka Connector

### What it does

A Snowflake-supplied Kafka Connect connector that uses the `SNOWPIPE_STREAMING`
ingestion method. Records flow directly into Snowflake tables without
intermediate stages, achieving sub-second end-to-end latency.

Connector class: `com.snowflake.kafka.connector.SnowflakeSinkConnector`

### When to use

- You need low-latency ingest (sub-second to single-digit seconds)
- Source cluster is anywhere (CC, CP, CFK, or LinuxONE)
- You want push-based delivery (vs. Snowflake pulling from object storage)

### CC-managed (source cluster in Confluent Cloud)

```hcl
module "fraud_to_snowflake" {
  source = "../../modules/lakehouse_sink"

  sink_type         = "SnowflakeSink"
  source_topic_name = module.fraud_alert_signal.topic_name
  target_table      = "FSI_PROD.KAFKA_FRAUD.ALERT_SIGNAL"
  snowflake_account_url    = "https://abc12345.us-east-1.snowflakecomputing.com"
  snowflake_user           = "FSI_KAFKA_CONNECTOR_SVC"
  credentials_secret_ref   = "secret/fsi/snowflake#private_key"
  sla_tier          = "critical"

  kafka_cluster_id              = local.infra.kafka_cluster_id
  schema_registry_cluster_id    = local.infra.sr_cluster_id
  schema_registry_rest_endpoint = local.infra.sr_rest_endpoint
  schema_registry_api_key       = var.sr_api_key
  schema_registry_api_secret    = var.sr_api_secret
}
```

### Self-managed (CP, CFK, LinuxONE)

Connector JSON: [`reference/connect-configs/snowflake-snowpipe-sink-example.json`](../reference/connect-configs/snowflake-snowpipe-sink-example.json)

Deploy via Ansible on CP / CP-on-RHEL-on-L1:

```bash
ansible-playbook -i ansible/inventories/prod ansible/playbooks/deploy-lakehouse-sinks.yml \
  --tags snowflake
```

Deploy as a `Connector` CR on CFK on OCP:

```bash
oc apply -f scenarios/cfk-openshift/connectors/snowflake-snowpipe-sink.yaml
```

Deploy via Kustomize on CFK on OCP on LinuxONE:

```bash
oc apply -k accelerators/confluent-on-linuxone/overlays/prod
```

### Authentication

Snowpipe Streaming uses **key-pair authentication** (RSA private key); user
+ password is not supported for streaming. Generate the key pair, register
the public key with Snowflake, and store the private key in Vault:

```
secret/fsi/snowflake#private_key
```

The user must have `INSERT` and `OWNERSHIP`-or-`USAGE` privileges on the
target schema. The platform convention is a per-environment service user
(`FSI_PROD_KAFKA_CONNECTOR_SVC`, `FSI_DR_KAFKA_CONNECTOR_SVC`).

For LinuxONE deployments where Vault is not reachable from the closed
z/IRD network, the private key is loaded from a JCEKS keystore — see
`scenarios/cp-rhel-linuxone/group_vars/lakehouse.yml`.

### Ingestion method

Always use `snowflake.ingestion.method = SNOWPIPE_STREAMING`. The legacy
`SNOWPIPE` method (object-storage based) is not configured by the platform
templates because it has minute-scale latency and adds an S3/ADLS hop.

### Schema evolution

- `snowflake.enable.schematization = true` is the platform default. Avro
  schema changes propagate to Snowflake table columns automatically when
  compatible with the table.
- Snowflake `VARIANT`-typed columns capture nested records faithfully.
- For `critical` SLA tier topics, `FULL_TRANSITIVE` Schema Registry
  compatibility prevents incompatible changes from reaching Snowflake.

### DLQ

Per-sink DLQ topic named `lakehouse.dlq.<sink-name>`, provisioned by
`modules/lakehouse_sink/` with `sla_tier = "best-effort"`.

### Observability

Grafana dashboard:
[`observability/grafana/dashboard-lakehouse-sink-snowflake.json`](../observability/grafana/dashboard-lakehouse-sink-snowflake.json)

Key panels: connector task state, records-per-second per channel,
streaming channel offset lag, DLQ rate, Snowpipe Streaming insert
errors by error code.

### Operational notes

- Snowpipe Streaming exactly-once is achieved via the connector's per-channel
  offset tracking inside Snowflake. Do not enable Kafka transactional
  consumer mode on top — it is redundant and adds latency.
- The Snowflake connector JAR is pure Java and runs on s390x. The Connect
  base image must be s390x for LinuxONE deployments.
- Snowflake clustering keys on the target table do **not** prevent ingest;
  they affect query performance only. Configure them on the Snowflake side.

---

## SF-B: Tableflow → Iceberg → Snowflake

### What it does

Tableflow materializes a topic to Iceberg in CC-managed storage. Snowflake
reads the Iceberg table via the Horizon open catalog (preferred) or via an
external table backed by the same Iceberg metadata.

### When to use

- Source cluster is Confluent Cloud
- Target audience tolerates minute-scale freshness
- You want zero Connect worker operations
- You also intend to query the same Iceberg table from other engines (e.g.,
  Trino, Spark, Athena) without duplicating data

### Terraform usage

```hcl
module "fraud_tableflow_snowflake" {
  source = "../../modules/tableflow"

  source_topic_name = module.fraud_alert_signal.topic_name
  storage_format    = "ICEBERG"
  catalog_target    = "snowflake-horizon"

  snowflake_open_catalog_endpoint = "https://abc12345.snowflakecomputing.com/open-catalog"
  snowflake_warehouse             = "FSI_KAFKA_WH"
  snowflake_allowed_scope         = "PRINCIPAL_ROLE:fsi_kafka_ingest"
  snowflake_oauth_client_id       = "$${vault:secret/fsi/snowflake-oc-oauth#client_id}"
  snowflake_oauth_client_secret   = "$${vault:secret/fsi/snowflake-oc-oauth#client_secret}"

  tableflow_bucket_name             = var.tableflow_bucket_name
  tableflow_provider_integration_id = var.tableflow_provider_integration_id

  environment_id       = var.environment_id
  kafka_cluster_id     = local.infra.kafka_cluster_id
  tableflow_api_key    = var.tableflow_api_key
  tableflow_api_secret = var.tableflow_api_secret
}
```

Note: Snowflake Open Catalog uses OAuth client credentials. The Snowpipe
Streaming **sink** connector (SF-A above) uses RSA key-pair auth — these
are two distinct credential sets and serve different purposes.

### Schema evolution

- Iceberg supports column addition, type widening, and renames natively.
- For `critical` and `compliance` SLA tier topics, Schema Registry
  compatibility prevents incompatible changes from reaching the Iceberg
  table.
- Snowflake refreshes its metadata view of the external Iceberg table on
  a configurable cadence; default is 60 seconds.

### Snowflake-side setup

The `snowflake-horizon` catalog target writes table metadata via Snowflake's
**Open Catalog** OAuth API. Before applying Terraform:

1. Configure a Snowflake security integration of type `external_oauth` for
   the Tableflow service principal.
2. Grant the principal a `PRINCIPAL_ROLE` (e.g., `fsi_kafka_ingest`) with
   `USAGE` on the target warehouse and `CREATE EXTERNAL TABLE` on the
   intended schema.
3. Pass the OAuth client ID/secret via Vault; pass the warehouse name and
   `PRINCIPAL_ROLE:<role>` scope via module inputs.

Queries against the materialized Iceberg table land via Snowflake's
catalog-aware engine; no external volume needs to be created manually.

### Operational notes

- Materialization cadence is minute-scale; SF-A is the right choice if
  freshness matters.
- DR: cluster link promotion does not affect Iceberg storage location.
  Snowflake's view of the table continues to work after failover.
- Cost: storage is in the CC account; Snowflake query compute is the
  customer's warehouse.

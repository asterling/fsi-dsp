# Databricks Integration Guide

Two supported paths from Kafka to Databricks. Pick the one that matches your
source cluster deployment model — the decision tree is in
[ADR-011](adr/011-lakehouse-integration-patterns.md).

| Path | Source cluster | Mechanism | Latency | Operational model |
|---|---|---|---|---|
| **DB-A** | Confluent Cloud only | Tableflow → Delta/Iceberg → Unity Catalog | minutes (materialization cadence) | Zero Connect workers; CC-managed |
| **DB-C** | CC / CP / CFK / LinuxONE | Databricks Delta Lake Sink Connector | seconds (connector throughput) | CC-managed *or* self-managed Connect |

If the source cluster is **not** Confluent Cloud, DB-A is unavailable —
Tableflow is a CC-only product. Use DB-C with the self-managed connector
configuration.

---

## DB-A: Confluent Tableflow → Databricks Unity Catalog

### What it does

Tableflow materializes a topic to object storage (Iceberg or Delta) on a
schedule managed by Confluent Cloud. A catalog integration (Unity Catalog)
makes the materialized table queryable from Databricks SQL, notebooks, and
ML pipelines.

### When to use

- Source cluster is Confluent Cloud
- Target audience tolerates minute-scale freshness
- You want zero Connect worker operations
- Iceberg or Delta is the desired table format

### Terraform usage

```hcl
module "corebanking_tableflow_databricks" {
  source = "../../modules/tableflow"

  source_topic_name = module.corebanking_account_txn.topic_name
  storage_format    = "DELTA"           # ICEBERG is fine too; UC reads both via UniForm
  catalog_target    = "unity-catalog"

  databricks_workspace_endpoint  = "https://adb-1234567890.123.azuredatabricks.net"
  databricks_catalog_name        = "fsi_prod"
  databricks_oauth_client_id     = "$${vault:secret/fsi/databricks-uc-oauth#client_id}"
  databricks_oauth_client_secret = "$${vault:secret/fsi/databricks-uc-oauth#client_secret}"

  tableflow_bucket_name             = var.tableflow_bucket_name
  tableflow_provider_integration_id = var.tableflow_provider_integration_id

  environment_id       = var.environment_id
  kafka_cluster_id     = local.infra.kafka_cluster_id
  tableflow_api_key    = var.tableflow_api_key
  tableflow_api_secret = var.tableflow_api_secret
}
```

Note: Unity Catalog integration uses OAuth client credentials (service
principal), **not** a Databricks PAT. The PAT pattern below is used by
the Delta Lake Sink **connector** (DB-C), which is a separate credential
set for a different purpose (row inserts vs catalog metadata writes).

### Schema evolution

- Table schema follows the topic's Avro schema; the source-of-truth is
  Schema Registry, not the lakehouse.
- For `critical` and `compliance` SLA tiers, `FULL_TRANSITIVE` compatibility
  prevents incompatible changes from reaching Databricks.
- New fields appear as new Delta columns automatically. Dropped fields stay
  in the Delta table as nullable historical columns (Delta does not delete
  historical data).

### PII handling

Topics with `data_classification = "confidential"` use CSFLE field-level
encryption. The encrypted payload is materialized as-is; consumers in
Databricks need access to the same KEK (configured via Unity Catalog
service principal) to decrypt. See
[csfle-guide.md](csfle-guide.md) for the cross-platform key flow.

### Operational notes

- Materialization cadence is managed by Confluent Cloud; SLA is published
  in the CC console (typically 60–120 seconds for normal-throughput topics).
- Tableflow storage is billed to the CC account.
- DR: on a regional failover (cluster link promotion), Tableflow continues
  to materialize from the now-primary cluster. The Unity Catalog table name
  does not change.

---

## DB-C: Databricks Delta Lake Sink Connector

### What it does

A Kafka Connect connector reads from one or more topics and writes records
into a Databricks Delta table via the Databricks SQL endpoint.

Connector class: `io.confluent.connect.databricks.DatabricksDeltaLakeSinkConnector`

### When to use

- Source cluster is anywhere (CC, CP, CFK, or LinuxONE)
- Target audience needs second-scale freshness
- You already operate a Connect cluster (CP / CFK / LinuxONE)
- You need control over batching, exactly-once semantics, or DLQ behavior

### CC-managed (source cluster in Confluent Cloud)

```hcl
module "corebanking_to_databricks" {
  source = "../../modules/lakehouse_sink"

  sink_type           = "DatabricksDeltaLakeSink"
  source_topic_name   = module.corebanking_account_txn.topic_name
  target_table        = "fsi_prod.kafka_corebanking.account_transaction"
  databricks_workspace_url = "https://adb-1234567890.123.azuredatabricks.net"
  credentials_secret_ref   = "secret/fsi/databricks#token"
  sla_tier            = "critical"

  kafka_cluster_id              = local.infra.kafka_cluster_id
  schema_registry_cluster_id    = local.infra.sr_cluster_id
  schema_registry_rest_endpoint = local.infra.sr_rest_endpoint
  schema_registry_api_key       = var.sr_api_key
  schema_registry_api_secret    = var.sr_api_secret
}
```

### Self-managed (CP, CFK, LinuxONE)

Connector JSON: [`reference/connect-configs/databricks-delta-sink-example.json`](../reference/connect-configs/databricks-delta-sink-example.json)

Deploy via Ansible on CP / CP-on-RHEL-on-L1:

```bash
ansible-playbook -i ansible/inventories/prod ansible/playbooks/deploy-lakehouse-sinks.yml \
  --tags databricks
```

Deploy via Kustomize on CFK on OCP on LinuxONE:

```bash
oc apply -k accelerators/confluent-on-linuxone/overlays/prod
```

Deploy as a `Connector` CR on stock CFK on OCP:

```bash
oc apply -f scenarios/cfk-openshift/connectors/databricks-delta-sink.yaml
```

### Authentication

Databricks Personal Access Tokens (PAT) or OAuth M2M credentials. The
platform standard is PAT stored in Vault:

```
secret/fsi/databricks#token
```

For non-Vault environments on LinuxONE (e.g., when Vault is unreachable
from a closed z/IRD network), the connector consumes credentials from a
JCEKS keystore — see `scenarios/cp-rhel-linuxone/group_vars/lakehouse.yml`.

### Schema evolution

- `auto.evolve` is **disabled by default** (matches JDBC sink convention,
  ADR-002). Schema changes are explicit DDL on Databricks side.
- For `standard` SLA tier topics where rapid iteration is needed,
  `auto.evolve: true` can be enabled per connector via
  `connector_overrides`.

### DLQ

Every lakehouse sink writes failed records to a per-sink DLQ topic. Naming
convention:

```
lakehouse.dlq.<sink-name>
```

The DLQ topic is provisioned automatically by `modules/lakehouse_sink/`
with `sla_tier = "best-effort"` (3 partitions, 1-day retention). Override
via `dlq_sla_tier` if the DLQ itself needs longer retention for compliance
review.

### Observability

Grafana dashboard:
[`observability/grafana/dashboard-lakehouse-sink-databricks.json`](../observability/grafana/dashboard-lakehouse-sink-databricks.json)

Key panels: connector task state, records-per-second per task, DLQ rate,
target table commit latency, Databricks SQL warehouse queue depth.

### Operational notes

- Connector requires the Databricks Delta Lake Sink JAR. On self-managed
  Connect this is sideloaded into `/opt/kafka-connect/plugins/`; on CC
  managed connectors the JAR is supplied by Confluent.
- For LinuxONE: the Delta Sink JAR is pure Java and runs on s390x without
  modification. The Connect base image must be s390x — see
  `accelerators/confluent-on-linuxone/layers/06-lakehouse-sinks/connect-cr.yaml`.
- Exactly-once is **not** offered by this connector (no transactional
  consumer mode). For exactly-once to Databricks, use Tableflow (DB-A).

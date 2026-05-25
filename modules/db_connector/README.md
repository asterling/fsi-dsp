# `modules/db_connector`

Polymorphic Confluent Cloud managed connector for an operational database.
One module call per integration; six legal `(db_type, direction)` combos.

## Legal combinations

| db_type | direction | CC connector class | Use case |
|---|---|---|---|
| `mongodb` | `source` | `MongoDbAtlasSource` | Change streams CDC |
| `mongodb` | `sink` | `MongoDbAtlasSink` | Write Kafka → collection |
| `redis` | `sink` | `RedisSink` | Hot-cache rebuild |
| `cockroachdb` | `sink` | `PostgresSink` (wire-compatible, port 26257) | Write Kafka → CRDB |
| `postgres` | `source` | `PostgresCdcSourceV2` | Debezium-based CDC |
| `postgres` | `sink` | `PostgresSink` | Write Kafka → Postgres |

## Rejected combinations (terraform plan fails fast)

| db_type | direction | Reason |
|---|---|---|
| `redis` | `source` | Redis is a cache, not a source of truth |
| `cockroachdb` | `source` | Use the **native** `CREATE CHANGEFEED` SQL on the CRDB side — runs inside CRDB, no Kafka Connect involved. See [`docs/cockroachdb-integration-guide.md`](../../docs/cockroachdb-integration-guide.md) |

## When to use this module

CC-managed path only. For self-managed deployments (CP, CFK, LinuxONE),
use:

- JSON templates: `reference/connect-configs/{mongodb,redis,postgres,...}-*.json`
- Ansible roles: `ansible/roles/cp_{mongodb,redis,cockroachdb,postgres}/`
- CFK CRs: `scenarios/cfk-openshift/connectors/*.yaml`
- L1 accelerator: `accelerators/confluent-on-linuxone/layers/07-database-connectors/`

See [ADR-012](../../docs/adr/012-database-connector-patterns.md) for the
full decision matrix.

## Usage examples

### Postgres CDC source (Debezium, the canonical FSI compliance pattern)

```hcl
module "corebanking_from_postgres_cdc" {
  source = "../../modules/db_connector"

  db_type              = "postgres"
  direction            = "source"
  target_topic_pattern = "corebanking.transactions.v1."
  source_db_url        = "pg-east.fsi.internal"
  credentials_secret_ref = "secret/fsi/postgres#password"
  sla_tier             = "critical"

  postgres_database    = "banking"
  postgres_publication = "fsi_kafka_publication"
  postgres_slot_name   = "fsi_kafka_prod"

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

### MongoDB sink

```hcl
module "corebanking_to_mongodb" {
  source = "../../modules/db_connector"

  db_type           = "mongodb"
  direction         = "sink"
  source_topic_name = module.corebanking_account_txn.topic_name
  target_db_url     = "cluster0.abcde.mongodb.net"
  credentials_secret_ref = "secret/fsi/mongodb#connection_uri"
  sla_tier          = "critical"

  mongodb_database   = "kafka_corebanking"
  mongodb_collection = "account_transaction"

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

### Redis sink for hot-cache rebuild

```hcl
module "compliance_to_redis_cache" {
  source = "../../modules/db_connector"

  db_type           = "redis"
  direction         = "sink"
  source_topic_name = module.compliance_screening_result.topic_name
  target_db_url     = "rediss://redis-prod.fsi.internal:6380"
  credentials_secret_ref = "secret/fsi/redis#password"
  sla_tier          = "best-effort"

  redis_client_mode = "Standalone"
  redis_key_prefix  = "compliance:screening:"
  redis_ttl_seconds = 3600

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

### CockroachDB sink (JDBC, port 26257, pg-wire)

```hcl
module "corebanking_to_cockroachdb" {
  source = "../../modules/db_connector"

  db_type           = "cockroachdb"
  direction         = "sink"
  source_topic_name = module.corebanking_account_txn.topic_name
  target_db_url     = "crdb-east.fsi.internal"
  credentials_secret_ref = "secret/fsi/cockroachdb#password"
  sla_tier          = "critical"

  jdbc_database   = "banking"
  jdbc_table_name = "kafka_account_transaction"
  jdbc_pk_fields  = "transaction_id"

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

| Tier | tasks.max (sink) | tasks.max (source) | DLQ partitions | DLQ retention |
|---|---|---|---|---|
| critical | 6 | 4 | 3 | 7 days |
| standard | 3 | 2 | 3 | 7 days |
| best-effort | 1 | 1 | 3 | 7 days |
| compliance | 6 | 4 | 3 | 7 days |

Sources favor fewer tasks for ordering preservation; sinks favor more for
throughput.

## Connector overrides

```hcl
connector_overrides = {
  "snapshot.mode"             = "never"    # Debezium: skip initial snapshot
  "heartbeat.interval.ms"     = "30000"    # Debezium: prevent slot lag on quiet tables
  "max.poll.records"          = "5000"     # Sink: larger batches
}
```

## Outputs

| Output | Purpose |
|---|---|
| `connector_name` | Use for dashboard labels, cross-module references |
| `connector_id` | CC resource ID for API access |
| `connector_class` | Effective CC connector class string |
| `dlq_topic_name` | Wire downstream DLQ consumer or alerting |
| `service_account_id` | Reference from RBAC modules |
| `tasks_max` | Verify effective task count |

## Scoped exception to ADR-004

ADR-004 selects self-managed on-prem Connect for enterprise workloads.
ADR-012 carves out a narrow exception for CC-managed database connectors
when the source cluster is CC and the target is a SaaS database
(MongoDB Atlas, CockroachDB Cloud, Redis Cloud, AWS RDS Postgres). Same
exception pattern as ADR-011 for lakehouse sinks.

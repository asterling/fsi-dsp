# MongoDB Integration Guide

Two paths between Kafka and MongoDB, both via the **MongoDB Kafka
Connector** (first-party, maintained by MongoDB Inc.). The decision tree
is in [ADR-012](adr/012-database-connector-patterns.md).

| Direction | Source cluster | Mechanism | Latency | Operational model |
|---|---|---|---|---|
| **Kafka ← MongoDB** (CDC) | CC / CP / CFK / LinuxONE | `MongoSourceConnector` (change streams) | sub-second | CC-managed *or* self-managed |
| **Kafka → MongoDB** (sink) | CC / CP / CFK / LinuxONE | `MongoSinkConnector` | seconds | CC-managed *or* self-managed |

Connector class for source: `com.mongodb.kafka.connect.MongoSourceConnector`
Connector class for sink: `com.mongodb.kafka.connect.MongoSinkConnector`

---

## Source — MongoDB → Kafka via change streams

### What it does

Tails MongoDB change streams on one or more collections and emits each
change event (insert, update, delete, drop) to a Kafka topic. Change
streams require a replica set or sharded cluster — not standalone Mongo.

### When to use

- The collection is the source of truth and downstream systems need every
  change (FSI member-profile updates, compliance KYC mutations).
- You want exactly-once delivery semantics via resume tokens (the
  connector stores resume tokens in offsets so restart is gap-free).

### CC-managed (source cluster in Confluent Cloud, target MongoDB Atlas)

```hcl
module "member_updates_from_mongodb_atlas" {
  source = "../../modules/db_connector"

  db_type           = "mongodb"
  direction         = "source"
  target_topic_pattern = "corebanking.transactions.v1.member-update"
  source_db_url     = "mongodb+srv://cluster0.abcde.mongodb.net"
  credentials_secret_ref = "secret/fsi/mongodb#connection_uri"
  sla_tier          = "critical"

  mongodb_database   = "corebanking"
  mongodb_collection = "member_profile"

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

### Self-managed (CP, CFK, LinuxONE)

JSON template: [`reference/connect-configs/mongodb-source-example.json`](../reference/connect-configs/mongodb-source-example.json)

Deploy via Ansible:

```bash
ansible-playbook -i ansible/inventories/prod \
  ansible/playbooks/deploy-database-connectors.yml \
  --tags mongodb
```

### Schema mapping

- BSON `Document` → Avro `record` via the connector's schema inference.
- `output.format.value=schema` (Avro) is the platform default; not JSON.
- Nested documents become nested Avro records. Arrays become Avro arrays.
- `ObjectId` becomes Avro `string` (24-char hex).
- `Decimal128` becomes Avro `bytes` with `logicalType=decimal`.

For governed topics in `critical` or `compliance` SLA tier, hand-author
the Avro schema and disable inference (`output.schema.infer.value=false`)
so Schema Registry compatibility is enforced.

### Full document on update

Default change streams emit only the diff for updates. To capture the
full document (typical FSI requirement for audit/replay):

```json
"change.stream.full.document": "updateLookup"
```

This costs an extra read per update but is non-negotiable for compliance
pipelines.

---

## Sink — Kafka → MongoDB

### What it does

Reads a Kafka topic and writes documents to a MongoDB collection.
Supports upsert semantics via configurable write strategies.

### When to use

- Materialized view of a Kafka event stream in MongoDB for downstream
  apps that want document queries.
- Replication of governed Kafka topics into a member-facing MongoDB
  collection (e.g., the FSI mobile app reads from Mongo, not Kafka).

### CC-managed

```hcl
module "corebanking_to_mongodb" {
  source = "../../modules/db_connector"

  db_type           = "mongodb"
  direction         = "sink"
  source_topic_name = module.corebanking_account_txn.topic_name
  target_db_url     = "mongodb+srv://cluster0.abcde.mongodb.net"
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

### Self-managed

JSON template: [`reference/connect-configs/mongodb-sink-example.json`](../reference/connect-configs/mongodb-sink-example.json)

### Write strategies

The platform default is `UpdateOneTimestampsStrategy` — upsert by record
key, with `_insertedTS` / `_modifiedTS` fields injected. Override per
sink via `connector_overrides`:

- `ReplaceOneDefaultStrategy` — full document replacement
- `DeleteOneDefaultStrategy` — delete by key (use when the source is a
  Debezium tombstone stream)

## Authentication

The platform pattern is **TLS + SCRAM-SHA-256** for self-hosted MongoDB,
or **X.509 client certificates** when Mongo's auth is delegated to mTLS.
For Atlas, the connector accepts the Atlas connection string with the
service account credentials embedded — store the full URI in Vault at
`secret/fsi/mongodb#connection_uri`.

For LinuxONE deployments where Vault is unreachable from the closed
z/IRD network, credentials load from a JCEKS keystore — see
`scenarios/cp-rhel-linuxone/group_vars/databases.yml`.

## DLQ

Per-connector DLQ named `database.dlq.<connector-name>` (e.g.
`database.dlq.mongodb-corebanking-account-txn`). Provisioned
automatically by `modules/db_connector/` for CC-managed; pre-created by
the KafkaTopic CR in layer 07 for CFK on L1.

## Observability

Grafana dashboard:
[`observability/grafana/dashboard-mongodb-connector.json`](../observability/grafana/dashboard-mongodb-connector.json)

Source-specific metrics: change-stream cursor age (lag from oldest
unconsumed change), source records/sec, resume-token offset.

Sink-specific metrics: write latency p95, write retries, document-
strategy success/failure counts.

## Operational notes

- The MongoDB Kafka Connector JAR is pure Java. Runs on s390x without
  modification. The Connect base image must be s390x for LinuxONE
  deployments.
- Change streams require a replica set or sharded cluster. Standalone
  Mongo is unsupported (the connector will fail at startup with
  `ChangeStreamHistoryLost`).
- Resume tokens are stateful: if the connector is offline longer than
  the MongoDB oplog window, resume tokens expire and a snapshot is
  required. Monitor the cursor-age metric and the connector's `lag` JMX.

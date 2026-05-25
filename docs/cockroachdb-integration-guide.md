# CockroachDB Integration Guide

CockroachDB is unique among the platform's database targets: it can emit
CDC events directly to Kafka via SQL DDL — no Kafka Connect required.
This guide covers **two distinct paths**. Pick by your CRDB licence and
operational preference; the full decision matrix is in
[ADR-012](adr/012-database-connector-patterns.md).

| Path | Direction | Mechanism | Operational owner | Licence |
|---|---|---|---|---|
| **A: Native changefeed** | CRDB → Kafka | `CREATE CHANGEFEED INTO 'kafka://...'` SQL | CRDB DBA | CRDB Enterprise |
| **B: JDBC sink** | Kafka → CRDB | `JdbcSinkConnector` with Postgres driver, port 26257 | Kafka Connect ops | CRDB Core or Enterprise |

There is **no Kafka Connect source for CRDB** in the platform. If you
need CDC from CockroachDB and lack an Enterprise licence, the recommended
fallback is to write events directly to Kafka from the application layer
— the platform does not ship a workaround connector.

---

## Path A: Native changefeed (CRDB → Kafka)

### What it does

`CREATE CHANGEFEED INTO 'kafka://<broker>' WITH ... AS SELECT ... FROM <table>`
runs inside CRDB. It tails the rangefeed (CRDB's internal CDC mechanism)
and emits Avro records to Kafka. The changefeed is a first-class CRDB
resource with its own lifecycle (`PAUSE JOB`, `RESUME JOB`, `CANCEL JOB`).

The platform has **no operational surface** for this path:
- No Connect worker
- No connector JSON
- No JAR install
- No DLQ topic provisioned by the platform (CRDB has its own
  error-handling and retry policy)
- No Terraform module / Ansible role

The platform deliverables are:
- This guide
- [`reference/cockroachdb/changefeed-examples.sql`](../reference/cockroachdb/changefeed-examples.sql) — FSI-flavored `CREATE CHANGEFEED` examples
- The Grafana dashboard that scrapes CRDB's own Prometheus metrics

### When to use

- You have a CRDB Enterprise licence.
- You want the cleanest, lowest-operational-burden CDC path from CRDB
  to Kafka.
- The DBA team is comfortable owning the changefeed lifecycle in SQL.

### Quick start

Run as a CRDB user with the `CHANGEFEED` privilege (in CRDB 23.1+;
earlier versions require `admin`):

```sql
-- 1. Verify Enterprise licence is loaded
SHOW CLUSTER SETTING enterprise.license;

-- 2. Verify rangefeed is enabled
SHOW CLUSTER SETTING kv.rangefeed.enabled;     -- should be 'true'

-- 3. Create the changefeed
CREATE CHANGEFEED FOR TABLE corebanking.transactions
INTO 'kafka://kafka.fsi.internal:9092?topic_name=corebanking.transactions.v1.account-transaction'
WITH
  envelope = 'wrapped',
  format = 'avro',
  confluent_schema_registry = 'https://schema.fsi.internal',
  resolved = '10s',
  updated;
```

See [`reference/cockroachdb/changefeed-examples.sql`](../reference/cockroachdb/changefeed-examples.sql)
for the full FSI-flavored set (mTLS auth, sink-specific options, error
handling, watermark cadence per SLA tier).

### Schema evolution

- `format = 'avro'` registers schemas with Confluent Schema Registry
  automatically.
- Adding a nullable column propagates as `BACKWARD`-compatible schema
  evolution.
- Dropping or retyping a column requires recreating the changefeed
  (the schema-registry compatibility check rejects incompatible changes).

### DR considerations

- Changefeeds survive single-node failures (the rangefeed mechanism is
  consensus-based). They do **not** survive whole-cluster loss — on DR
  cutover to a different CRDB cluster, the changefeed must be recreated
  on the surviving cluster, and resume position is set by the DBA via
  `cursor =` option.
- Failover from East Kafka to West Kafka: update the sink URL in a
  `ALTER CHANGEFEED` (in CRDB 23.2+) or recreate the changefeed.

### Observability

Grafana dashboard:
[`observability/grafana/dashboard-cockroachdb-changefeed.json`](../observability/grafana/dashboard-cockroachdb-changefeed.json)

This dashboard is **structurally different** from the other connector
dashboards — it scrapes the CRDB Prometheus endpoint (port 8080 by
default), not the Kafka Connect REST API. Key panels:

- `changefeed.emitted_messages` (rate) — events delivered to Kafka
- `changefeed.emit_latency_p95` — end-to-end CRDB-to-Kafka latency
- `changefeed.error_retries` — sink errors retried
- `changefeed.checkpoint_progress` — resolved-timestamp watermark lag

---

## Path B: JDBC sink (Kafka → CRDB)

### What it does

Reads a Kafka topic and writes rows to a CRDB table via the JDBC sink
connector. CRDB is PostgreSQL-wire-compatible, so the standard Postgres
JDBC driver works — pointed at port `26257` (CRDB's default) instead of
`5432`.

Connector class: `io.confluent.connect.jdbc.JdbcSinkConnector`

### When to use

- You need to write Kafka events into CockroachDB tables.
- You are on CRDB Core (no changefeed licence) or you want symmetric
  bidirectional flow.

### CC-managed

```hcl
module "corebanking_to_cockroachdb" {
  source = "../../modules/db_connector"

  db_type           = "cockroachdb"
  direction         = "sink"
  source_topic_name = module.corebanking_account_txn.topic_name
  target_db_url     = "jdbc:postgresql://crdb-east.fsi.internal:26257/banking?sslmode=verify-full"
  credentials_secret_ref = "secret/fsi/cockroachdb#password"
  sla_tier          = "critical"

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

### Self-managed

JSON template: [`reference/connect-configs/cockroachdb-jdbc-sink-example.json`](../reference/connect-configs/cockroachdb-jdbc-sink-example.json)

Deploy via Ansible:

```bash
ansible-playbook -i ansible/inventories/prod \
  ansible/playbooks/deploy-database-connectors.yml \
  --tags cockroachdb
```

### Authentication

The platform standard is **CRDB-managed certificates** (CRDB clusters
mint client certs through the built-in CA). Mount the cert + key + CA
bundle into the Connect pod and reference via `sslcert=`, `sslkey=`,
`sslrootcert=` in the JDBC URL.

Vault path: `secret/fsi/cockroachdb#password` (only used when not using
client certs).

For LinuxONE, see `scenarios/cp-rhel-linuxone/group_vars/databases.yml`
for the JCEKS-bundle pattern.

### Schema evolution

- `auto.evolve=false` (platform default). DDL is explicit, applied by the
  CRDB DBA. ADR-002 governs this.
- `insert.mode=upsert` with `pk.mode=record_value` + `pk.fields=<column>`
  is the FSI default for idempotent writes.

### Multi-region tables

For CRDB multi-region tables (`SURVIVE REGION FAILURE`), specify the
`region` column in the connector's `pk.fields` to avoid cross-region
write amplification.

---

## Picking between A and B

```
Got CRDB Enterprise?
  yes ─> Path A (native changefeed). Lowest operational burden.
  no  ─> Path B (JDBC sink) for Kafka → CRDB.
         For CRDB → Kafka, write events from the app layer (no platform-
         supported workaround).

Need bidirectional (Kafka ↔ CRDB)?
  ─> Path A for outbound + Path B for inbound. They are independent.
```

## Operational notes

- The JDBC Sink Connector + Postgres JDBC driver are pure Java; run
  unchanged on s390x.
- CRDB's `26257` port is for SQL traffic, not the admin UI (`8080`).
  Don't confuse them when configuring connectors.
- Native changefeed throughput is bounded by the rangefeed processor's
  capacity per CRDB node. For very high-throughput tables (> 100k rows/sec),
  partition the changefeed via `WITH split_column = ...` (CRDB 23.2+).

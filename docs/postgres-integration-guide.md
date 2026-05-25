# PostgreSQL Integration Guide

Two supported paths between Kafka and PostgreSQL. The full decision tree
is in [ADR-012](adr/012-database-connector-patterns.md).

| Path | Direction | Mechanism | Latency | Operational owner |
|---|---|---|---|---|
| **A: Debezium CDC source** | Postgres → Kafka | `PostgresConnector` via logical decoding (`pgoutput`) | sub-second | Kafka Connect ops + Postgres DBA |
| **B: JDBC sink** | Kafka → Postgres | `JdbcSinkConnector` | seconds | Kafka Connect ops |

Path A replaces the legacy `timestamp+incrementing` JDBC polling source
([`jdbc-source-example.json`](../reference/connect-configs/jdbc-source-example.json))
as the platform default for Postgres CDC. Polling is still documented for
low-throughput tables without a replication slot.

---

## Path A: Debezium PostgreSQL Source (CDC)

### What it does

Reads PostgreSQL's logical replication stream via the `pgoutput` plugin
(built into Postgres 10+) and emits each row change (INSERT, UPDATE,
DELETE, TRUNCATE) as a Kafka record. Each table → one Kafka topic by
default, customizable via SMTs.

Connector class: `io.debezium.connector.postgresql.PostgresConnector`

### When to use

- Compliance pipelines that require every-change-captured semantics
  (including deletes).
- Audit / replay use cases where ordering and exactly-once-per-LSN
  guarantees matter.
- Real-time materialized views downstream of an OLTP Postgres database.

### Postgres-side prerequisites (DBA-owned)

1. **Set `wal_level = logical`** in `postgresql.conf` and restart.
2. **Increase `max_wal_senders` and `max_replication_slots`** (≥ 5 each
   for FSI clusters).
3. **Create a replication role** with `REPLICATION` and `LOGIN`
   privileges:
   ```sql
   CREATE ROLE fsi_debezium WITH LOGIN REPLICATION PASSWORD '...';
   GRANT SELECT ON ALL TABLES IN SCHEMA banking TO fsi_debezium;
   ```
4. **Set `REPLICA IDENTITY`** on each captured table:
   ```sql
   ALTER TABLE banking.account_transaction REPLICA IDENTITY FULL;
   ```
   `FULL` is required to capture pre-update values on UPDATE/DELETE.
5. **Pre-create the publication** (platform pattern; do NOT use
   `publication.autocreate.mode=all_tables`):
   ```sql
   CREATE PUBLICATION fsi_kafka_publication FOR TABLE
     banking.account_transaction,
     banking.member_profile;
   ```
6. **Pre-create the replication slot** (optional; the connector creates
   it on first start otherwise):
   ```sql
   SELECT pg_create_logical_replication_slot('fsi_kafka_prod', 'pgoutput');
   ```

### CC-managed

```hcl
module "corebanking_from_postgres_cdc" {
  source = "../../modules/db_connector"

  db_type           = "postgres"
  direction         = "source"
  target_topic_pattern = "corebanking.transactions.v1.${tableName}"
  source_db_url     = "jdbc:postgresql://pg-east.fsi.internal:5432/banking?sslmode=verify-full"
  credentials_secret_ref = "secret/fsi/postgres#password"
  sla_tier          = "critical"

  postgres_database   = "banking"
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

### Self-managed

JSON template: [`reference/connect-configs/postgres-debezium-source-example.json`](../reference/connect-configs/postgres-debezium-source-example.json)

Deploy via Ansible:

```bash
ansible-playbook -i ansible/inventories/prod \
  ansible/playbooks/deploy-database-connectors.yml \
  --tags postgres
```

### Topic naming

Default Debezium emits to `<server>.<schema>.<table>`. The platform
applies an SMT chain to route to `<domain>.<application>.<v>.<entity>`
per ADR-007:

```json
"transforms": "route",
"transforms.route.type": "org.apache.kafka.connect.transforms.RegexRouter",
"transforms.route.regex": "([^.]+)\\.([^.]+)\\.([^.]+)",
"transforms.route.replacement": "corebanking.transactions.v1.$3"
```

### Schema evolution

- Adding a nullable column: propagates as `BACKWARD`-compatible.
- Adding a NOT NULL column: requires backfill on the Postgres side
  before Debezium can emit valid records — coordinate with the DBA.
- Dropping a column: emits an empty value for that field; downstream
  consumers must tolerate.

For `critical` and `compliance` SLA tier topics, `FULL_TRANSITIVE`
compatibility (per ADR-002) blocks incompatible Postgres DDL from
reaching Kafka — the connector task fails fast and the DBA is paged.

### Slot lag — the metric that matters

The replication slot retains WAL until the connector consumes past it.
If the connector stops (network blip, OOM, etc.), the slot lag grows
and Postgres disk fills. **Alert on slot lag > 1 GiB.**

Grafana dashboard:
[`observability/grafana/dashboard-postgres-cdc.json`](../observability/grafana/dashboard-postgres-cdc.json)

Panels: `pg_replication_slots.confirmed_flush_lsn` lag, snapshot
progress, WAL position, `debezium_metrics_milliseconds_behind_source`,
DLQ rate.

---

## Path B: JDBC Sink (Kafka → Postgres)

### What it does

Reads a Kafka topic and writes rows to a Postgres table.

Connector class: `io.confluent.connect.jdbc.JdbcSinkConnector`

### When to use

- Reporting / analytical tables hydrated from Kafka events.
- Materialized views on Postgres downstream of an event stream.

### CC-managed

```hcl
module "compliance_to_postgres_reporting" {
  source = "../../modules/db_connector"

  db_type           = "postgres"
  direction         = "sink"
  source_topic_name = module.compliance_screening_result.topic_name
  target_db_url     = "jdbc:postgresql://pg-reporting.fsi.internal:5432/reporting?sslmode=verify-full"
  credentials_secret_ref = "secret/fsi/postgres#password"
  sla_tier          = "standard"

  jdbc_table_name = "compliance_screening_result"
  jdbc_pk_fields  = "match_id"

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

JSON template: [`reference/connect-configs/postgres-jdbc-sink-example.json`](../reference/connect-configs/postgres-jdbc-sink-example.json)

Same shape as the existing Oracle-flavored
[`jdbc-sink-example.json`](../reference/connect-configs/jdbc-sink-example.json);
differs only in the JDBC URL and driver.

### Schema evolution

- `auto.evolve=false` (platform default; ADR-002).
- `insert.mode=upsert` with `pk.mode=record_value` + `pk.fields=<column>`.

---

## Authentication

Both paths use the same Vault secret:

```
secret/fsi/postgres#username
secret/fsi/postgres#password
```

For the Debezium source, the user must additionally have `REPLICATION`
and `LOGIN` privileges in Postgres (the JDBC sink user does not).

For LinuxONE, see `scenarios/cp-rhel-linuxone/group_vars/databases.yml`
for the JCEKS-bundle pattern.

## DLQ

Per-connector DLQ named `database.dlq.<connector-name>` (e.g.
`database.dlq.postgres-debezium-corebanking`,
`database.dlq.postgres-jdbc-sink-compliance-reporting`).

## Picking between Debezium and JDBC polling source

| Use case | Mechanism |
|---|---|
| Real-time CDC, every event captured (incl. deletes) | Debezium (default) |
| Low-throughput table (< 100 rows/sec), no rep slot allowed | JDBC polling (`jdbc-source-example.json`) |
| Tables on Postgres < 10, polling tolerated | JDBC polling |
| Tables that need replay-by-LSN | Debezium |

## Operational notes

- The Debezium PostgreSQL connector JAR is pure Java; runs unchanged on
  s390x. Connect base image must be s390x for LinuxONE.
- The `pgoutput` plugin ships with Postgres 10+; no extension install
  required (unlike the older `wal2json` plugin).
- Connector restart resumes from the last committed LSN — no data loss,
  no duplicates within a single transaction. Across restarts, exactly-
  once semantics require Kafka transactional consumer settings on the
  downstream side.
- Postgres major version upgrade: the replication slot must be recreated
  on the new primary; coordinate with the DBA before pg_upgrade.

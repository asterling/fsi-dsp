# ADR-012: Database Connector Patterns — MongoDB, Redis, CockroachDB, PostgreSQL

**Status:** Accepted
**Date:** 2026-05-25
**Author:** Platform C4E

## Context

The platform now ships first-class lakehouse integration (ADR-011). The
next-most-requested integration target is operational data stores —
specifically the four that dominate FSI workloads: MongoDB (member profile,
document store), Redis (hot cache), CockroachDB (multi-region OLTP), and
PostgreSQL (analytical / reporting / RDS).

Today the repo has:

- One Oracle-flavored JDBC sink example
  (`reference/connect-configs/jdbc-sink-example.json`)
- One Oracle-flavored JDBC polling source example
  (`reference/connect-configs/jdbc-source-example.json` using
  `timestamp+incrementing` mode — not true CDC)
- A `jdbc-sink-postgres-reporting` stub in
  `ansible/vars/connectors-example.yml`

Everything else for these four databases is greenfield. There is no true
CDC pattern (Debezium / logical decoding) anywhere in the repo.

Five candidate mechanisms exist per database in 2026:

| Path | Source (Kafka ← DB) | Sink (Kafka → DB) |
|---|---|---|
| **MongoDB** | MongoDB Kafka Connector (`MongoSourceConnector`, change streams) | MongoDB Kafka Connector (`MongoSinkConnector`) |
| **Redis** | n/a — Redis is a cache, not a source of truth | Confluent `RedisSinkConnector` |
| **CockroachDB** | Native `CREATE CHANGEFEED INTO 'kafka://...'` — runs inside CRDB, **no Kafka Connect required** | `JdbcSinkConnector` with the Postgres driver pointed at port 26257 |
| **PostgreSQL** | Debezium `PostgresConnector` (logical decoding via `pgoutput`) | `JdbcSinkConnector` |

Three cross-cutting design forces shape this ADR:

1. **True CDC vs polling.** The existing JDBC source is polling — it
   misses deletes, lags by `poll.interval.ms`, and stresses the source
   DB. For Postgres, logical decoding via `pgoutput` is the FSI standard
   for compliance pipelines (every event captured, every delete recorded,
   replay-able by LSN). ADR-012 picks Debezium as the default Postgres
   source while keeping the polling source documented for low-throughput
   tables that lack a replication slot.

2. **CockroachDB native changefeed is fundamentally different.** Unlike
   Connect-based CDC, `CREATE CHANGEFEED` runs **inside CRDB nodes** and
   emits Avro to Kafka directly. The platform has no operational surface
   (no Connect worker, no JAR install, no DLQ topic provisioned by the
   platform). DBAs own the changefeed lifecycle via SQL DDL. This must
   be documented as a first-class path even though no Terraform module
   or Ansible role can manage it.

3. **ADR-004 scope (self-managed on-prem Connect) remains in effect.** As
   with the lakehouse phase (ADR-011), CC-managed database connectors are
   a scoped exception: allowed when the source cluster is CC and the
   target is a SaaS database (MongoDB Atlas, CockroachDB Cloud, Redis
   Cloud, AWS RDS Postgres). Self-managed everywhere else.

## Decision

**The platform ships first-class assets for all four databases across all
five deployment models (CC, CP on RHEL, CFK on OCP, CP on RHEL on L1, CFK
on OCP on L1), with these direction-by-database commitments:**

| Database | Source (CDC) | Sink |
|---|---|---|
| MongoDB | ✅ Change streams via MongoDB Kafka Connector | ✅ MongoDB Kafka Connector |
| Redis | ❌ Not a source of truth | ✅ Confluent Redis Sink Connector |
| CockroachDB | ✅ Native `CREATE CHANGEFEED` (DBA-driven, no Connect) | ✅ JDBC Sink with Postgres driver on port 26257 |
| PostgreSQL | ✅ Debezium `PostgresConnector` (default); JDBC polling source supported for low-throughput edge cases | ✅ JDBC Sink |

A new reusable Terraform module — `modules/db_connector/` — emits a fully
governed CC-managed connector parameterized by `db_type` (`mongodb` |
`redis` | `cockroachdb` | `postgres`) × `direction` (`source` | `sink`).
The module rejects invalid combinations (Redis source, CockroachDB
source) at `terraform plan` time via `lifecycle.precondition`.

Self-managed paths reuse the existing `cp_connect` Ansible role with four
new wrapper roles (`cp_mongodb`, `cp_redis`, `cp_cockroachdb`,
`cp_postgres`) and six new connector JSON templates under
`reference/connect-configs/`.

For CFK on OCP on LinuxONE, a new Kustomize layer `07-database-connectors`
mounts a dedicated `connect-databases` Connect cluster alongside the
existing `connect` (audit, layer 04) and `connect-lakehouse` (layer 06)
clusters. The dedicated cluster preserves operational isolation: a
Postgres replication-slot stall must not back up the audit pipeline.

For CockroachDB native changefeed, the deliverable is documentation
(`docs/cockroachdb-integration-guide.md`) plus a tested SQL example file
(`reference/cockroachdb/changefeed-examples.sql`). No Terraform resource
or Ansible role exists for this path because there is no Kafka-platform-
side resource to manage — DBAs run the `CREATE CHANGEFEED` statement
inside CRDB itself.

### Default selection guidance

1. **Need CDC from Postgres?** → Debezium source (default). Drop to JDBC
   polling only when the source table is < 100 rows/sec and a replication
   slot cannot be provisioned (rare in FSI).
2. **Need CDC from MongoDB?** → MongoDB Source Connector (change streams).
3. **Need CDC from CockroachDB?** → Native changefeed (path A in the
   CockroachDB guide). Use JDBC sink (path B) only when the CRDB cluster
   is on Core licence and changefeeds are unavailable.
4. **Need to write Kafka → operational DB?** → The respective sink
   connector for each target. JDBC for Cockroach and Postgres; MongoDB
   Sink for Mongo; Redis Sink for Redis.

## Consequences

**Easier:**

- A CC topic can be reflected into MongoDB Atlas, Redis Cloud, CRDB Cloud,
  or AWS RDS Postgres with a single Terraform module call. No Connect
  cluster, no JAR install, no DLQ provisioning, no service-account dance.
- On-prem teams get the same connector-JSON template + Ansible role
  shape they already use for JDBC sinks, with `${vault:...}` placeholders
  and DLQ pre-wired.
- LinuxONE customers get a Kustomize layer (07) that mirrors layer 06
  structurally — same `connect-<purpose>` isolation pattern, same
  `secrets.template.yaml` Vault-Agent contract, same s390x image build
  recipe.
- Postgres CDC is finally first-class. Compliance pipelines that need
  every-event-captured semantics no longer have to roll their own
  Debezium setup.
- CockroachDB users get the unique no-Connect changefeed pattern
  documented and SQL-exemplified, not buried in vendor docs.

**Harder:**

- This is the first true CDC pattern in the repo. Debezium has its own
  operational discipline: replication slots are stateful (slot lag
  grows if the consumer stops), publications must be pre-created with
  the right `REPLICA IDENTITY`, and `pgoutput` requires the Postgres
  user to have `REPLICATION` privilege. The platform docs surface this
  but the responsibility lives with the source-DB DBA.
- Vault paths multiply: four new system paths (`secret/fsi/mongodb`,
  `/redis`, `/cockroachdb`, `/postgres`) on top of the existing
  `oracle`, `sr`, `databricks`, `snowflake`, `aws-databricks-staging`.
  Operators must populate them before the connectors will start.
- CockroachDB native changefeed has **no platform-side telemetry**. Its
  metrics come from the CRDB Prometheus endpoint, not the Connect REST
  API. The Grafana dashboard for this path is structurally different
  from the other connector dashboards.
- DLQ topic count grows again. Per-sink DLQ named
  `database.dlq.<connector-name>` (parallel to `lakehouse.dlq.*`). With
  six legal direction-by-DB combinations × N source topics, the count
  can multiply quickly. The module wires one DLQ per connector
  instance, not per source topic, to keep the count bounded.

**Neutral but worth noting:**

- ADR-004 remains in effect for non-database-non-lakehouse sinks. ADR-012
  is a second scoped exception to ADR-004, parallel to ADR-011.
- The existing `reference/connect-configs/jdbc-sink-example.json` (Oracle)
  and `jdbc-source-example.json` (Oracle polling) stay as-is. The new
  `postgres-jdbc-sink-example.json` and `postgres-debezium-source-example.json`
  are additive — Oracle is still a valid target.
- The MongoDB Kafka Connector, Redis Sink Connector, Debezium PostgreSQL,
  and Confluent JDBC Connector JARs are all pure Java. They run on s390x
  without recompilation; the LinuxONE Connect base image is what must be
  multi-arch.

## Cross-References

- ADR-004 — On-prem Connect (self-managed); ADR-012 is a scoped exception
  for CC managed connectors targeting SaaS databases, not a reversal
- ADR-011 — Lakehouse integration patterns; precedent for the scoped-
  exception pattern and the dedicated-Connect-cluster operational
  isolation argument used by layer 07
- ADR-001 — Avro over Protobuf (CDC sources use AvroConverter via SR)
- ADR-002 — Compatibility by tier (CDC schema follows topic schema's
  compatibility mode; `auto.evolve=false` on sinks per existing JDBC
  convention)
- ADR-007 — Topic naming (CDC sources route to
  `<domain>.<application>.<v>.<entity>` via RegexRouter SMTs)
- `docs/mongodb-integration-guide.md` — MongoDB source + sink operator guide
- `docs/redis-integration-guide.md` — Redis sink operator guide
- `docs/cockroachdb-integration-guide.md` — Native changefeed + JDBC sink
- `docs/postgres-integration-guide.md` — Debezium CDC + JDBC sink
- `reference/cockroachdb/changefeed-examples.sql` — FSI-flavored
  `CREATE CHANGEFEED` SQL

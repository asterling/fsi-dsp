# Layer 07: Database Connectors

## FSI Rationale

Every FSI team that landed Kafka on the platform now wants to integrate
with operational data stores — MongoDB for member profiles, Redis for hot
cache, CockroachDB for multi-region OLTP, PostgreSQL for reporting and
RDS. Without a sanctioned, governed path each business unit invents its
own: ad-hoc Connect clusters, hardcoded credentials, no DLQ, no
observability, replication slots stalling silently and filling Postgres
disks.

**Failure mode without this layer:** member-profile changes don't reach
the mobile app's MongoDB; compliance match results don't refresh the
fraud screening hot cache; OLTP writes don't replicate to the analytical
side. Worse: in regulated environments, the lack of a sanctioned CDC
path forces application-layer dual-writes that violate the
event-sourcing invariant — eventually causing audit findings.

## What this layer does

Implements [ADR-012](../../../../docs/adr/012-database-connector-patterns.md):
MongoDB (source + sink), Redis (sink), CockroachDB (sink), PostgreSQL
(Debezium source + JDBC sink) on CFK on OCP on LinuxONE (s390x).

### Components

1. **`kafkatopic-database-dlq.yaml`** — pre-creates six per-connector
   DLQ topics (`database.dlq.*`) with `min.insync.replicas=2`,
   7-day retention.

2. **`connect-cr.yaml`** — deploys a dedicated `connect-databases`
   Connect cluster (separate from layer-04 `connect` and layer-06
   `connect-lakehouse` clusters) plus six `Connector` CRs:
   - MongoDB Source (change streams)
   - MongoDB Sink
   - Redis Sink
   - CockroachDB JDBC Sink (Postgres driver on port 26257)
   - Postgres Debezium Source (logical decoding via `pgoutput`)
   - Postgres JDBC Sink

3. **`rolebindings.yaml`** — MDS `ConfluentRolebinding` CRs for the
   `database-connector` principal: source-topic read (sinks), target-
   topic write PREFIXED (sources), DLQ write PREFIXED, SR subject
   read/write per direction, connector consumer group read.

4. **`service-accounts.yaml`** — Kubernetes SA for pod identity (Kafka
   auth is via mTLS from layer 02-tls).

5. **`secrets.template.yaml`** — documents the `database-creds` Secret
   contract. Reconciled by Vault-Agent; not committed with real values.

### CockroachDB source is intentionally absent

Path A from `docs/cockroachdb-integration-guide.md` — native
`CREATE CHANGEFEED` — runs inside CRDB itself. There is no Kafka-side
resource to manage. See `reference/cockroachdb/changefeed-examples.sql`
and the CockroachDB Prometheus dashboard
(`observability/grafana/dashboard-cockroachdb-changefeed.json`).

### Architecture-neutral JARs, s390x-required Connect base image

All four connector JARs (MongoDB, Redis, JDBC, Debezium Postgres) are
pure Java. They run on s390x without recompilation. The Connect base
image must be s390x:

```bash
docker buildx build --platform linux/s390x \
  --tag <registry>/fsi-cp-connect-databases:7.6.0 \
  -f scenarios/cfk-openshift/connectors/Dockerfile.databases .
```

Then substitute `<PLACEHOLDER_S390X_CONNECT_DATABASES_IMAGE>` in
`connect-cr.yaml` with the resulting image reference.

## Dependencies on prior layers

| Layer | Required for | What breaks without it |
|---|---|---|
| 01-rbac | MDS authorizer + ConfluentRolebinding CRD | Connector cannot read/write topics — auth deny |
| 02-tls | cert-manager + confluent-ca-issuer; `connect-databases-tls` Secret | Connect-to-broker mTLS fails |
| 03-schema-governance | Schema Registry + governed subjects | AvroConverter cannot resolve schema by ID |

Layer 07 does **not** depend on 04-audit, 05-flink, or 06-lakehouse-sinks.
It is appended after 06 in the overlay; ordering preserves layer
independence.

Add to `overlays/prod/kustomization.yaml`:

```yaml
components:
  - ../../layers/01-rbac
  - ../../layers/02-tls
  - ../../layers/03-schema-governance
  - ../../layers/04-audit
  - ../../layers/05-flink
  - ../../layers/06-lakehouse-sinks
  - ../../layers/07-database-connectors   # <-- new
```

## Why a dedicated connect-databases cluster

Three separate Connect clusters preserve operational isolation:

| Cluster | Purpose | Layer |
|---|---|---|
| `connect` | Audit log shipping (Splunk, Dynatrace) | 04 |
| `connect-lakehouse` | Databricks + Snowflake sinks | 06 |
| `connect-databases` | MongoDB + Redis + JDBC + Debezium | 07 |

A Postgres replication-slot stall must not back up the audit pipeline.
A Databricks credential rotation must not interrupt MongoDB CDC. A
single shared cluster can't optimize for both source ordering
preservation and sink throughput.

## Postgres-side prerequisites (DBA-owned, out of layer scope)

Before this layer's Postgres CDC connector starts, the Postgres DBA must:

1. Set `wal_level = logical` and restart.
2. Create a replication role with `REPLICATION` + `LOGIN` privileges.
3. Set `REPLICA IDENTITY FULL` on captured tables.
4. Pre-create the publication
   (`CREATE PUBLICATION fsi_kafka_publication FOR TABLE ...`).
5. Optionally pre-create the replication slot
   (`pg_create_logical_replication_slot('fsi_kafka_prod', 'pgoutput')`).

See `docs/postgres-integration-guide.md` for the full walkthrough.
**Alert on slot lag > 1 GiB** — that's the metric that determines
whether Postgres disk fills.

## Validation

```bash
# 1. Manifests assemble cleanly
kustomize build accelerators/confluent-on-linuxone/overlays/prod | \
  yq 'select(.kind == "Connector" and (.metadata.labels."fsi.io/connector-type" // "" | contains("source") or contains("sink")))' | \
  head -150

# 2. Apply
oc apply -k accelerators/confluent-on-linuxone/overlays/prod

# 3. connect-databases cluster reaches READY
oc get connect -n confluent connect-databases

# 4. All six connectors reach RUNNING
oc get connector -n confluent -l app.kubernetes.io/part-of=fsi-kafka-platform | \
  grep -E "database-(mongodb|redis|cockroachdb|postgres)"

# 5. DLQ topics exist
oc get kafkatopic -n confluent -l fsi.io/dlq-for | grep database-dlq

# 6. Postgres source: confirm the replication slot is consuming WAL
oc exec -n confluent connect-databases-0 -- \
  curl -s http://localhost:8083/connectors/database-postgres-source-corebanking-cdc/status | jq
```

## Observability

`connect-databases` inherits the platform JMX exporter config. Four
purpose-built Grafana dashboards pick up the new connectors by name:

- `observability/grafana/dashboard-mongodb-connector.json`
- `observability/grafana/dashboard-redis-sink.json`
- `observability/grafana/dashboard-cockroachdb-changefeed.json` (scrapes
  CRDB Prometheus, not Connect REST API — for native changefeed path)
- `observability/grafana/dashboard-postgres-cdc.json` (Debezium-specific
  metrics: slot lag, snapshot progress, WAL position)

## Cross-references

- [ADR-012](../../../../docs/adr/012-database-connector-patterns.md) — the decision
- [`docs/mongodb-integration-guide.md`](../../../../docs/mongodb-integration-guide.md)
- [`docs/redis-integration-guide.md`](../../../../docs/redis-integration-guide.md)
- [`docs/cockroachdb-integration-guide.md`](../../../../docs/cockroachdb-integration-guide.md)
- [`docs/postgres-integration-guide.md`](../../../../docs/postgres-integration-guide.md)
- `reference/cockroachdb/changefeed-examples.sql` — CRDB-side SQL for
  the native changefeed path
- `layers/01-rbac/` — MDS authorizer prerequisite
- `layers/02-tls/` — cert-manager + TLS material
- `layers/06-lakehouse-sinks/` — sibling Connect-cluster pattern

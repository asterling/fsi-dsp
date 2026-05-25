# Database Connector Configs

Reference JSON for the self-managed paths from ADR-012:

| File | Connector class | Notes |
|---|---|---|
| `mongodb-source-example.json` | `com.mongodb.kafka.connect.MongoSourceConnector` | Change streams CDC |
| `mongodb-sink-example.json` | `com.mongodb.kafka.connect.MongoSinkConnector` | Document writes |
| `redis-sink-example.json` | `io.confluent.connect.redis.RedisSinkConnector` | Sink only |
| `cockroachdb-jdbc-sink-example.json` | `io.confluent.connect.jdbc.JdbcSinkConnector` | Postgres driver, port 26257 |
| `postgres-debezium-source-example.json` | `io.debezium.connector.postgresql.PostgresConnector` | True CDC via `pgoutput` |
| `postgres-jdbc-sink-example.json` | `io.confluent.connect.jdbc.JdbcSinkConnector` | Postgres twin of the existing Oracle JDBC sink |

For CC-managed equivalents, use `modules/db_connector/`. For
CockroachDB **source** there is no Connect-based path — see
`reference/cockroachdb/changefeed-examples.sql` and
`docs/cockroachdb-integration-guide.md`.

## Connector JAR installation

The base CP Connect distribution does not include MongoDB, Redis,
Debezium, or JDBC drivers. Install via `confluent-hub`:

### CP on RHEL / RHEL on LinuxONE

```bash
# MongoDB Kafka Connector (covers both source and sink)
confluent-hub install --no-prompt \
  --component-dir /opt/kafka-connect/plugins \
  mongodb/kafka-connect-mongodb:latest

# Confluent Redis Sink Connector
confluent-hub install --no-prompt \
  --component-dir /opt/kafka-connect/plugins \
  confluentinc/kafka-connect-redis:latest

# Debezium PostgreSQL Source
confluent-hub install --no-prompt \
  --component-dir /opt/kafka-connect/plugins \
  debezium/debezium-connector-postgresql:latest

# Confluent JDBC Connector (sink for Postgres and CockroachDB)
confluent-hub install --no-prompt \
  --component-dir /opt/kafka-connect/plugins \
  confluentinc/kafka-connect-jdbc:latest

# Postgres JDBC driver (required by JDBC Sink for both Postgres and CRDB)
curl -L https://jdbc.postgresql.org/download/postgresql-42.7.3.jar \
  -o /opt/kafka-connect/plugins/confluentinc-kafka-connect-jdbc/lib/postgresql-42.7.3.jar

systemctl restart confluent-kafka-connect
```

All five JARs are pure Java and run unchanged on s390x.

### CFK on OpenShift

The JARs are baked into a custom Connect image. See:
- `scenarios/cfk-openshift/connectors/README.md` (build recipe)
- `accelerators/confluent-on-linuxone/layers/07-database-connectors/connect-cr.yaml`
  (s390x flavor)

## Postgres-side prerequisites for Debezium

Before deploying the Postgres CDC source, the DBA must:

1. Set `wal_level = logical` and restart Postgres.
2. Increase `max_wal_senders` and `max_replication_slots` (≥ 5 each).
3. Create the replication role:
   ```sql
   CREATE ROLE fsi_debezium WITH LOGIN REPLICATION PASSWORD '...';
   GRANT SELECT ON ALL TABLES IN SCHEMA banking TO fsi_debezium;
   ```
4. Set `REPLICA IDENTITY FULL` on each captured table.
5. Pre-create the publication (`CREATE PUBLICATION fsi_kafka_publication FOR TABLE ...`)
   — the platform's connector config uses `publication.autocreate.mode=disabled`
   so the DBA stays in control.

See `docs/postgres-integration-guide.md` for the full prerequisite walkthrough.

## Deployment

### Via Ansible (CP / CP on RHEL on L1)

```bash
# All databases
ansible-playbook -i ansible/inventories/prod \
  ansible/playbooks/deploy-database-connectors.yml

# Selective
ansible-playbook -i ansible/inventories/prod \
  ansible/playbooks/deploy-database-connectors.yml --tags mongodb
# also: --tags redis, --tags cockroachdb, --tags postgres
```

### Via Connect REST (manual)

```bash
curl -X PUT \
  -H "Content-Type: application/json" \
  --data @postgres-debezium-source-example.json \
  https://connect.fsi.internal:8083/connectors/database-postgres-source-corebanking-cdc/config
```

### Via Kustomize (CFK on OCP on LinuxONE)

```bash
oc apply -k accelerators/confluent-on-linuxone/overlays/prod
```

## Secret patterns

All credentials use `${vault:secret/fsi/<system>#<field>}`. Vault paths
used by these configs:

| Path | Used by |
|---|---|
| `secret/fsi/mongodb#connection_uri` | Mongo connection URI (Atlas-style or self-hosted) |
| `secret/fsi/redis#username` | Redis ACL user (optional; default user often suffices) |
| `secret/fsi/redis#password` | Redis ACL password |
| `secret/fsi/redis-tls#truststore_password` | Redis TLS truststore unlock (rare; only if client truststore is encrypted) |
| `secret/fsi/cockroachdb#username` / `#password` | CRDB SQL user (when not using client certs) |
| `secret/fsi/postgres#cdc_username` / `#cdc_password` | Postgres replication-role for Debezium |
| `secret/fsi/postgres#username` / `#password` | Postgres app user for JDBC sink |
| `secret/fsi/sr#api_key` / `#api_secret` | Schema Registry (platform-wide) |

CockroachDB client certs are typically mounted via cert-manager / Vault-
Agent into `/mnt/sslcerts/cockroachdb-{ca,client}.{crt,key}`; the JDBC
URL references them via `sslcert=` / `sslkey=` / `sslrootcert=` params.

On LinuxONE deployments where Vault is unreachable from the closed
z/IRD network, credentials are loaded from a JCEKS keystore — see
`scenarios/cp-rhel-linuxone/group_vars/databases.yml`.

## DLQ topics

Each connector writes errors to a per-connector DLQ named
`database.dlq.<connector-name>` (distinct prefix from the lakehouse
`lakehouse.dlq.*`). The DLQ must exist before the connector starts;
SLA tier is `best-effort` by default. For CC-managed connectors the
DLQ is provisioned automatically by `modules/db_connector/`; for CFK
on L1 the KafkaTopic CRs in layer 07 pre-create them.

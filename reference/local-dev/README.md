# Local Development Environment

Single-node local development environment for the FSI Kafka Platform. Provides Kafka, Schema Registry, Kafka Connect, and optionally Apache Flink for stream processing development and testing.

**Not for production.** Uses Confluent Community Edition (no license required).

## Services

| Service | Container | Port | Profile |
|---------|-----------|------|---------|
| Kafka | fsi-broker | 9092 | default |
| Schema Registry | fsi-schema-registry | 8081 | default |
| Kafka Connect | fsi-connect | 8083 | default |
| Flink JobManager | fsi-flink-jobmanager | 8085 (UI) | flink |
| Flink TaskManager | fsi-flink-taskmanager | - | flink |
| Flink SQL Client | fsi-flink-sql-client | - | flink |

## Quick Start

```bash
# Start core services (Kafka, SR, Connect)
cd reference/local-dev
docker compose up -d

# Wait for all services to be healthy
docker compose ps

# Start with Flink (optional)
docker compose --profile flink up -d
```

## Register a Schema

```bash
# Register the account-transaction schema
curl -X POST http://localhost:8081/subjects/corebanking.transactions.v1.account-transaction-value/versions \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  -d "{\"schema\": $(cat ../../schemas/examples/account-transaction.avsc | jq -Rs .)}"
```

## Create a Topic

```bash
docker exec fsi-broker kafka-topics --create \
  --topic corebanking.transactions.v1.account-transaction \
  --partitions 3 \
  --replication-factor 1 \
  --bootstrap-server broker:29092
```

## Flink SQL

The Flink profile starts a JobManager, TaskManager, and SQL Client with pre-installed Kafka and Avro-Confluent connector JARs. The custom Flink image is built from `flink-sql/Dockerfile`.

### Access the SQL Client

```bash
docker exec -it fsi-flink-sql-client /opt/flink/bin/sql-client.sh
```

### Example: Stream from Kafka with Avro-Confluent Format

```sql
-- Create a table reading from a Kafka topic with Avro-Confluent format
CREATE TABLE account_transactions (
  transaction_id STRING,
  amount DECIMAL(15, 2),
  timestamp_ms BIGINT,
  proc_time AS PROCTIME()
) WITH (
  'connector' = 'kafka',
  'topic' = 'corebanking.transactions.v1.account-transaction',
  'properties.bootstrap.servers' = 'broker:29092',
  'scan.startup.mode' = 'earliest-offset',
  'format' = 'avro-confluent',
  'avro-confluent.url' = 'http://schema-registry:8081'
);

-- Query the stream
SELECT * FROM account_transactions;
```

### Flink Web UI

The Flink dashboard is available at [http://localhost:8085](http://localhost:8085) when the `flink` profile is active.

## Integration Tests

Run the integration test suite against the local dev environment:

```bash
# Happy path -- produce, consume, verify roundtrip
bash reference/integration-test/roundtrip-test.sh

# Error paths -- serialization failure, RBAC denial, schema incompatibility, broker failure
bash reference/integration-test/error-path-tests.sh
```

## Troubleshooting

**Schema Registry not healthy**
Check that the broker is healthy first. Schema Registry depends on a running Kafka broker:
```bash
docker compose logs schema-registry
docker exec fsi-broker kafka-broker-api-versions --bootstrap-server broker:29092
```

**Flink SQL connector error**
Rebuild the Flink image to re-download connector JARs:
```bash
docker compose --profile flink build --no-cache
docker compose --profile flink up -d
```

**Port conflict on 8085**
Change the Flink UI port mapping in `docker-compose.yml`. The `flink-jobmanager` service maps `8085:8081` (port 8081 is already used by Schema Registry).

**Connect takes a long time to start**
Connect installs the JDBC connector on first startup. The `start_period: 60s` healthcheck accounts for this. Check logs with:
```bash
docker compose logs connect
```

## Clean Up

```bash
# Stop all services and remove volumes
docker compose --profile flink down -v

# Stop core services only (preserves Flink)
docker compose down -v
```

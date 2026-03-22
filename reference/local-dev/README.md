# Local Development Environment

Single-node Kafka + Schema Registry + Connect for local development and testing.

## Quick Start

```bash
docker compose up -d
docker compose logs -f
```

## Endpoints

| Service           | URL                     |
|-------------------|-------------------------|
| Kafka bootstrap   | `localhost:9092`        |
| Schema Registry   | `http://localhost:8081`  |
| Connect REST API  | `http://localhost:8083`  |

## Register a schema locally

```bash
# Register the CNCB account-transaction schema
curl -X POST http://localhost:8081/subjects/cncb.core.v1.account-transaction-value/versions \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  -d "{\"schema\": $(cat ../../schemas/cncb-account-transaction.avsc | jq -Rs .)}"
```

## Create a topic locally

```bash
docker exec fsi-broker kafka-topics --create \
  --topic cncb.core.v1.account-transaction \
  --partitions 3 \
  --replication-factor 1 \
  --bootstrap-server broker:29092
```

## Tear down

```bash
docker compose down -v
```

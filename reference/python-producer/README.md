# FSI C4E Reference Producer -- Python

Python reference implementation of the FSI C4E producer pattern. Mirrors the Java `FsiProducer` with identical behavior: idempotent delivery, Avro serialization via Schema Registry, Prometheus metrics, and Dead Letter Queue (DLQ) routing.

## Purpose

Provide Python teams with a production-ready Kafka producer that follows all C4E mandatory patterns:

- **Idempotent** (`enable.idempotence=True`, `acks=all`) for exactly-once per partition
- **Avro serialization** with Schema Registry (modern `AvroSerializer` API)
- **Prometheus metrics** exposed via HTTP endpoint for observability
- **DLQ routing** for failed messages with error categorization and exponential backoff
- **Graceful shutdown** with flush and final metrics logging

## Prerequisites

- Python 3.8+
- `pip` package manager
- Access to a Kafka cluster (local via Docker Compose or Confluent Cloud)
- Access to Schema Registry

## Installation

```bash
pip install -r requirements.txt
```

## Usage

### Basic Producer

```python
from fsi_producer import FsiProducer

config = {
    "topic.name": "corebanking.transactions.v1.account-transaction",
    "bootstrap.servers": "localhost:9092",
    "schema.registry.url": "http://localhost:8081",
}

with FsiProducer(config) as producer:
    # Async send (fire-and-forget with callback)
    producer.send("acct-001", {
        "transaction_id": "tx-20240101-001",
        "account_number": "acct-001",
        "amount": 150.00,
        "currency": "USD",
        "timestamp": 1704067200000,
    })

    # Sync send (blocking -- returns metadata)
    result = producer.send_sync("acct-002", {
        "transaction_id": "tx-20240101-002",
        "account_number": "acct-002",
        "amount": 250.00,
        "currency": "USD",
        "timestamp": 1704067201000,
    })
    print(f"Produced to {result['topic']}-{result['partition']} offset={result['offset']}")
```

### Confluent Cloud Configuration

```python
config = {
    "topic.name": "corebanking.transactions.v1.account-transaction",
    "bootstrap.servers": "pkc-xxxxx.us-east-1.aws.confluent.cloud:9092",
    "schema.registry.url": "https://psrc-xxxxx.us-east-1.aws.confluent.cloud",
    "schema.registry.basic.auth.user.info": "<sr-api-key>:<sr-api-secret>",
    "sasl.username": "<api-key>",
    "sasl.password": "<api-secret>",
    "metrics.port": "9090",
}
```

## Configuration

| Key | Required | Default | Description |
|-----|----------|---------|-------------|
| `topic.name` | Yes | -- | Fully qualified topic name |
| `bootstrap.servers` | No | `localhost:9092` | Kafka bootstrap servers |
| `schema.registry.url` | No | `http://localhost:8081` | Schema Registry URL |
| `schema.registry.basic.auth.user.info` | No | -- | SR credentials (`api_key:secret`) |
| `sasl.username` | No | -- | Confluent Cloud API key (enables SASL_SSL) |
| `sasl.password` | No | -- | Confluent Cloud API secret |
| `value.schema` | No | -- | Avro schema JSON string |
| `client.id` | No | `fsi-{domain}-producer-python` | Client identifier for monitoring |
| `dlq.enabled` | No | `true` | Enable DLQ routing for failed messages |
| `metrics.port` | No | `9090` | Prometheus HTTP metrics port |

### C4E Mandatory Settings (Non-configurable)

These are set automatically and cannot be overridden:

| Setting | Value | Reason |
|---------|-------|--------|
| `enable.idempotence` | `True` | Exactly-once per partition |
| `acks` | `all` | Full ISR acknowledgment |
| `max.in.flight.requests.per.connection` | `5` | Safe with idempotence enabled |
| `retries` | `2147483647` | Infinite retries (bounded by delivery.timeout.ms) |
| `delivery.timeout.ms` | `120000` | 2-minute delivery timeout |
| `compression.type` | `zstd` | Best compression ratio for FSI payloads |
| `batch.size` | `32768` | 32KB batches |
| `linger.ms` | `20` | 20ms linger for batching |

## Metrics

Prometheus metrics are exposed at `http://localhost:{metrics.port}/metrics`:

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `fsi_producer_total_sent` | Counter | `topic` | Total messages sent successfully |
| `fsi_producer_total_errors` | Counter | `topic` | Total send errors |
| `fsi_producer_last_latency_ms` | Gauge | `topic` | Last send latency in ms |
| `fsi_producer_dlq_sent` | Counter | `topic` | Total messages routed to DLQ |

## DLQ Behavior

When `dlq.enabled=true` (default), failed messages are routed to `{topic.name}.dlq`:

1. **Non-retryable errors** (serialization, authorization) are sent directly to DLQ
2. **Retryable errors** (broker timeout, leader election) are retried up to 3 times with exponential backoff (1s, 2s, 4s) before DLQ routing
3. DLQ messages include metadata headers: `dlq.original.topic`, `dlq.error.type`, `dlq.error.message`, `dlq.timestamp`, `dlq.retry.count`, `dlq.producer.client.id`

Error categories: `SERIALIZATION`, `SCHEMA_INCOMPATIBLE`, `BROKER_TIMEOUT`, `AUTH_DENIED`, `UNKNOWN`

## See Also

- Java reference: `reference/java-producer/`
- .NET reference: `reference/dotnet-producer/`
- DLQ handler: `fsi_dlq_handler.py`
- DLQ SQL pattern: `reference/flink-sql/dlq-pattern.sql`

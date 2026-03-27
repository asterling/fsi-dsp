# FSI C4E Reference Consumer -- Python

Python reference implementation of the FSI C4E consumer pattern. Mirrors the Java `FsiConsumer` with identical behavior: manual offset commit, Avro deserialization via Schema Registry, handler function pattern, Prometheus metrics, and graceful shutdown.

## Purpose

Provide Python teams with a production-ready Kafka consumer that follows all C4E mandatory patterns:

- **Manual offset commit** (`enable.auto.commit=False`) for at-least-once delivery
- **Avro deserialization** with Schema Registry (modern `AvroDeserializer` API)
- **Handler function pattern** -- inject your processing logic as a callable
- **Prometheus metrics** exposed via HTTP endpoint for observability
- **Graceful shutdown** via SIGTERM/SIGINT signal handlers

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

### Basic Consumer

```python
from fsi_consumer import FsiConsumer

def handle_record(key: str, value: dict):
    """Process a single record. Raise an exception to trigger error handling."""
    print(f"Received: {key} -> {value}")
    # Your business logic here

config = {
    "group.id": "corebanking-txn-processor",
    "topics": "corebanking.transactions.v1.account-transaction",
    "bootstrap.servers": "localhost:9092",
    "schema.registry.url": "http://localhost:8081",
}

with FsiConsumer(config, handle_record) as consumer:
    consumer.start()  # Blocks until SIGTERM/SIGINT
```

### Confluent Cloud Configuration

```python
config = {
    "group.id": "corebanking-txn-processor",
    "topics": "corebanking.transactions.v1.account-transaction",
    "bootstrap.servers": "pkc-xxxxx.us-east-1.aws.confluent.cloud:9092",
    "schema.registry.url": "https://psrc-xxxxx.us-east-1.aws.confluent.cloud",
    "schema.registry.basic.auth.user.info": "<sr-api-key>:<sr-api-secret>",
    "sasl.username": "<api-key>",
    "sasl.password": "<api-secret>",
    "metrics.port": "9091",
}
```

### Multiple Topics

```python
config = {
    "group.id": "multi-topic-processor",
    "topics": "corebanking.transactions.v1.account-transaction,fraud.alerts.v1.alert-signal",
    "bootstrap.servers": "localhost:9092",
    "schema.registry.url": "http://localhost:8081",
}
```

## Configuration

| Key | Required | Default | Description |
|-----|----------|---------|-------------|
| `group.id` | Yes | -- | Consumer group identifier |
| `topics` | Yes | -- | Comma-separated topic names |
| `bootstrap.servers` | No | `localhost:9092` | Kafka bootstrap servers |
| `schema.registry.url` | No | `http://localhost:8081` | Schema Registry URL |
| `schema.registry.basic.auth.user.info` | No | -- | SR credentials (`api_key:secret`) |
| `sasl.username` | No | -- | Confluent Cloud API key (enables SASL_SSL) |
| `sasl.password` | No | -- | Confluent Cloud API secret |
| `client.id` | No | `fsi-{group.id}-consumer-python` | Client identifier for monitoring |
| `metrics.port` | No | `9091` | Prometheus HTTP metrics port |

### C4E Mandatory Settings (Non-configurable)

| Setting | Value | Reason |
|---------|-------|--------|
| `enable.auto.commit` | `False` | Manual commit for at-least-once guarantee |
| `auto.offset.reset` | `earliest` | Don't miss messages on new consumer group |
| `max.poll.interval.ms` | `300000` | 5-minute max processing time per batch |
| `fetch.min.bytes` | `1024` | Reduce network overhead |
| `fetch.wait.max.ms` | `500` | Balance latency vs throughput |

## Metrics

Prometheus metrics are exposed at `http://localhost:{metrics.port}/metrics`:

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `fsi_consumer_total_consumed` | Counter | `group` | Total messages consumed successfully |
| `fsi_consumer_total_errors` | Counter | `group` | Total processing errors |
| `fsi_consumer_last_poll_count` | Gauge | `group` | Records in last poll batch |
| `fsi_consumer_last_commit_latency_ms` | Gauge | `group` | Last commit latency in ms |

## Shutdown Behavior

The consumer handles graceful shutdown automatically:

1. **SIGTERM/SIGINT** signals set `_running = False`
2. Current poll completes (up to 1 second timeout)
3. Consumer closes with offset commit
4. Final metrics logged (total consumed, errors)

This matches the Java `FsiConsumer` behavior of `consumer.wakeup()` on shutdown hook.

## Error Handling

- **Deserialization errors**: Logged and skipped (at-least-once semantics)
- **Handler exceptions**: Logged and skipped (message offset committed)
- **Commit failures**: Logged but processing continues (may cause redelivery)
- **Partition EOF**: Silently continued (normal operation)

## See Also

- Java reference: `reference/java-consumer/`
- .NET reference: `reference/dotnet-consumer/`
- Producer reference: `reference/python-producer/`

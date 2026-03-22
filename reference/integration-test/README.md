# Integration Test

Verifies the full produce → Schema Registry → consume roundtrip.

## Prerequisites

Start the local dev environment:
```bash
cd ../local-dev
docker compose up -d
```

## Run

```bash
./roundtrip-test.sh
```

The test creates a temporary topic, registers a test schema, produces an Avro record,
consumes it back, and verifies the content matches. All 5 steps must pass.

## Against Confluent Cloud (test environment)

```bash
./roundtrip-test.sh pkc-test.us-east-1.aws.confluent.cloud:9092 https://psrc-test.us-east-1.aws.confluent.cloud
```

Note: CC requires authentication — you'll need to set SASL config. The local-dev
version is the primary CI target.

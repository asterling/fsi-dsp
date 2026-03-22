#!/usr/bin/env bash
# =============================================================================
# FSI Kafka Platform — Integration Roundtrip Test
# =============================================================================
# Verifies: produce → Schema Registry → topic → consume → deserialize
# Run against local-dev Docker Compose or a test CC environment.
#
# Usage:
#   ./roundtrip-test.sh [bootstrap_server] [sr_url]
#
# Defaults to local-dev endpoints.
# =============================================================================
set -euo pipefail

BOOTSTRAP="${1:-localhost:9092}"
SR_URL="${2:-http://localhost:8081}"
TOPIC="test.integration.v1.roundtrip"
TEST_KEY="test-$(date +%s)"
TEST_VALUE="roundtrip-$(uuidgen 2>/dev/null || echo $RANDOM)"

echo "=== FSI Integration Roundtrip Test ==="
echo "Bootstrap: ${BOOTSTRAP}"
echo "SR:        ${SR_URL}"
echo "Topic:     ${TOPIC}"
echo "Test key:  ${TEST_KEY}"
echo ""

# ── Step 1: Create test topic ──
echo "[1/5] Creating topic..."
docker exec fsi-broker kafka-topics --create \
  --topic "${TOPIC}" \
  --partitions 1 \
  --replication-factor 1 \
  --bootstrap-server broker:29092 \
  --if-not-exists 2>/dev/null || true
echo "  OK"

# ── Step 2: Register test schema ──
echo "[2/5] Registering schema..."
SCHEMA='{
  "type": "record",
  "name": "RoundtripTest",
  "namespace": "org.fsi.test",
  "fields": [
    {"name": "test_key", "type": "string"},
    {"name": "test_value", "type": "string"},
    {"name": "timestamp", "type": {"type": "long", "logicalType": "timestamp-millis"}}
  ]
}'

SCHEMA_ID=$(curl -s -X POST "${SR_URL}/subjects/${TOPIC}-value/versions" \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  -d "{\"schema\": $(echo "$SCHEMA" | jq -Rs .)}" \
  | jq -r '.id')

if [ -z "$SCHEMA_ID" ] || [ "$SCHEMA_ID" = "null" ]; then
  echo "  FAIL: Could not register schema"
  exit 1
fi
echo "  OK (schema ID: ${SCHEMA_ID})"

# ── Step 3: Produce a test record ──
echo "[3/5] Producing record..."
# Using kafka-avro-console-producer
echo "{\"test_key\": \"${TEST_KEY}\", \"test_value\": \"${TEST_VALUE}\", \"timestamp\": $(date +%s000)}" \
  | docker exec -i fsi-schema-registry kafka-avro-console-producer \
    --broker-list broker:29092 \
    --topic "${TOPIC}" \
    --property schema.registry.url=http://schema-registry:8081 \
    --property value.schema="$(echo "$SCHEMA" | tr -d '\n')" \
    2>/dev/null
echo "  OK"

# ── Step 4: Consume and verify ──
echo "[4/5] Consuming record..."
CONSUMED=$(docker exec fsi-schema-registry kafka-avro-console-consumer \
  --bootstrap-server broker:29092 \
  --topic "${TOPIC}" \
  --from-beginning \
  --max-messages 1 \
  --timeout-ms 10000 \
  --property schema.registry.url=http://schema-registry:8081 \
  2>/dev/null)

if echo "$CONSUMED" | grep -q "${TEST_KEY}"; then
  echo "  OK — Record roundtripped successfully"
else
  echo "  FAIL — Expected key '${TEST_KEY}' in consumed record"
  echo "  Got: ${CONSUMED}"
  exit 1
fi

# ── Step 5: Verify schema in registry ──
echo "[5/5] Verifying schema registration..."
SUBJECTS=$(curl -s "${SR_URL}/subjects")
if echo "$SUBJECTS" | grep -q "${TOPIC}-value"; then
  echo "  OK — Subject '${TOPIC}-value' registered"
else
  echo "  FAIL — Subject not found in registry"
  exit 1
fi

# ── Cleanup ──
echo ""
echo "=== ALL TESTS PASSED ==="
echo "  Topic created:    ${TOPIC}"
echo "  Schema registered: ID ${SCHEMA_ID}"
echo "  Record produced:  key=${TEST_KEY}"
echo "  Record consumed:  verified"
echo ""
echo "Clean up with: docker exec fsi-broker kafka-topics --delete --topic ${TOPIC} --bootstrap-server broker:29092"

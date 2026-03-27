#!/usr/bin/env bash
# =============================================================================
# FSI Kafka Platform -- Error Path Integration Tests
# =============================================================================
# Validates failure handling: serialization, RBAC denial, schema incompat,
# broker failure. Run against local-dev Docker Compose (requires services
# running).
#
# Prerequisites:
#   cd reference/local-dev && docker compose up -d
#   # Wait for all services to be healthy
#
# Usage:
#   ./error-path-tests.sh [bootstrap_server] [sr_url]
# =============================================================================
set -euo pipefail

BOOTSTRAP="${1:-localhost:9092}"
SR_URL="${2:-http://localhost:8081}"
TOPIC="test.errorpath.v1.validation"
DLQ_TOPIC="test.errorpath.v1.validation.dlq"
RBAC_TOPIC="test.errorpath.v1.rbac-denied"
PASSED=0
FAILED=0

# -- Determine Docker Compose file location --
# Script may be invoked from the repo root or the integration-test directory.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/../local-dev/docker-compose.yml"
if [ ! -f "${COMPOSE_FILE}" ]; then
  echo "ERROR: Cannot find docker-compose.yml at ${COMPOSE_FILE}"
  exit 1
fi

# =============================================================================
# Helper functions
# =============================================================================

wait_for_broker() {
  echo "  Waiting for broker to become healthy..."
  local attempts=0
  local max_attempts=30
  while [ ${attempts} -lt ${max_attempts} ]; do
    if docker exec fsi-broker kafka-broker-api-versions \
        --bootstrap-server broker:29092 >/dev/null 2>&1; then
      echo "  Broker is healthy."
      return 0
    fi
    attempts=$((attempts + 1))
    sleep 2
  done
  echo "  ERROR: Broker did not become healthy after ${max_attempts} attempts."
  return 1
}

cleanup() {
  echo ""
  echo "[CLEANUP] Removing test resources..."

  # Delete test topics (ignore errors if they don't exist)
  docker exec fsi-broker kafka-topics --delete \
    --topic "${TOPIC}" \
    --bootstrap-server broker:29092 2>/dev/null || true
  docker exec fsi-broker kafka-topics --delete \
    --topic "${DLQ_TOPIC}" \
    --bootstrap-server broker:29092 2>/dev/null || true
  docker exec fsi-broker kafka-topics --delete \
    --topic "${RBAC_TOPIC}" \
    --bootstrap-server broker:29092 2>/dev/null || true

  # Remove any RBAC ACLs left behind
  docker exec fsi-broker kafka-acls --bootstrap-server broker:29092 \
    --remove --deny-principal User:ANONYMOUS --operation Write \
    --topic "${RBAC_TOPIC}" --force 2>/dev/null || true

  # Remove ACL authorizer config (restore default)
  docker exec fsi-broker kafka-configs --bootstrap-server broker:29092 \
    --alter --entity-type brokers --entity-default \
    --delete-config authorizer.class.name,super.users 2>/dev/null || true

  # Delete test schema subjects
  curl -s -X DELETE "${SR_URL}/subjects/${TOPIC}-value" >/dev/null 2>&1 || true
  curl -s -X DELETE "${SR_URL}/subjects/${TOPIC}-value?permanent=true" >/dev/null 2>&1 || true

  echo "[CLEANUP] Done."
}

record_pass() {
  local test_name="$1"
  PASSED=$((PASSED + 1))
  echo "  PASS -- ${test_name}"
}

record_fail() {
  local test_name="$1"
  local detail="${2:-}"
  FAILED=$((FAILED + 1))
  echo "  FAIL -- ${test_name}: ${detail}"
}

trap cleanup EXIT

# =============================================================================
# Setup
# =============================================================================

echo "=== FSI Error Path Integration Tests ==="
echo "Bootstrap: ${BOOTSTRAP}"
echo "SR:        ${SR_URL}"
echo ""

echo "[SETUP] Creating test topics..."
docker exec fsi-broker kafka-topics --create \
  --topic "${TOPIC}" --partitions 1 --replication-factor 1 \
  --bootstrap-server broker:29092 --if-not-exists 2>/dev/null || true
docker exec fsi-broker kafka-topics --create \
  --topic "${DLQ_TOPIC}" --partitions 1 --replication-factor 1 \
  --bootstrap-server broker:29092 --if-not-exists 2>/dev/null || true

# Register a valid test schema
SCHEMA='{"type":"record","name":"ErrorPathTest","namespace":"org.fsi.test","fields":[{"name":"test_key","type":"string"},{"name":"test_value","type":"string"},{"name":"timestamp","type":{"type":"long","logicalType":"timestamp-millis"}}]}'

echo "[SETUP] Registering test schema..."
SCHEMA_ID=$(curl -s -X POST "${SR_URL}/subjects/${TOPIC}-value/versions" \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  -d "{\"schema\": $(echo "${SCHEMA}" | jq -Rs .)}" \
  | jq -r '.id')

if [ -z "${SCHEMA_ID}" ] || [ "${SCHEMA_ID}" = "null" ]; then
  echo "ERROR: Could not register test schema. Is Schema Registry running?"
  exit 1
fi
echo "[SETUP] Schema registered (ID: ${SCHEMA_ID})"
echo ""

# =============================================================================
# Error Path 1: Serialization Failure                                    [1/4]
# =============================================================================

echo "[1/4] Error Path 1: Serialization Failure"
echo "  Sending malformed record that does not match Avro schema..."

set +e
SERIALIZATION_OUTPUT=$(echo '{"unknown_field": 123}' \
  | docker exec -i fsi-schema-registry kafka-avro-console-producer \
    --broker-list broker:29092 \
    --topic "${TOPIC}" \
    --property schema.registry.url=http://schema-registry:8081 \
    --property value.schema="${SCHEMA}" 2>&1)
SERIALIZATION_EXIT=$?
set -e

# The producer should fail because the record does not match the schema.
# Check for serialization/schema error indicators in output or non-zero exit.
if echo "${SERIALIZATION_OUTPUT}" | grep -qiE "error|exception|could not|failed|serialize"; then
  record_pass "Serialization failure detected correctly"
elif [ ${SERIALIZATION_EXIT} -ne 0 ]; then
  record_pass "Serialization failure detected (non-zero exit code)"
else
  record_fail "Serialization failure" "Malformed record was accepted without error"
fi
echo ""

# =============================================================================
# Error Path 2: RBAC Denial (ACL-based)                                  [2/4]
# =============================================================================

echo "[2/4] Error Path 2: RBAC Denial (Authorization)"
echo "  Configuring ACL authorizer on broker..."

# Create the RBAC test topic
docker exec fsi-broker kafka-topics --create \
  --topic "${RBAC_TOPIC}" --partitions 1 --replication-factor 1 \
  --bootstrap-server broker:29092 --if-not-exists 2>/dev/null || true

# Enable ACL authorizer with ANONYMOUS as super user so existing connections
# continue to work. Then add a DENY ACL for ANONYMOUS on the RBAC test topic.
docker exec fsi-broker kafka-configs --bootstrap-server broker:29092 \
  --alter --entity-type brokers --entity-default \
  --add-config "authorizer.class.name=kafka.security.authorizer.AclAuthorizer,super.users=User:ANONYMOUS" \
  2>/dev/null || true

# Add a DENY ACL for ANONYMOUS on the RBAC test topic specifically
echo "  Adding DENY ACL for User:ANONYMOUS on ${RBAC_TOPIC}..."
docker exec fsi-broker kafka-acls --bootstrap-server broker:29092 \
  --add --deny-principal User:ANONYMOUS --operation Write \
  --topic "${RBAC_TOPIC}" 2>/dev/null || true

# Small delay for ACL propagation
sleep 2

echo "  Attempting to produce to denied topic..."
set +e
RBAC_OUTPUT=$(echo '{"test_key":"rbac-test","test_value":"should-fail","timestamp":1700000000000}' \
  | timeout 15 docker exec -i fsi-schema-registry kafka-avro-console-producer \
    --broker-list broker:29092 \
    --topic "${RBAC_TOPIC}" \
    --property schema.registry.url=http://schema-registry:8081 \
    --property value.schema="${SCHEMA}" 2>&1)
RBAC_EXIT=$?
set -e

if echo "${RBAC_OUTPUT}" | grep -qiE "TopicAuthorizationException|TOPIC_AUTHORIZATION_FAILED|Not authorized|authorization|denied"; then
  record_pass "RBAC denial detected -- authorization error returned"
elif [ ${RBAC_EXIT} -ne 0 ]; then
  record_pass "RBAC denial detected (non-zero exit code: ${RBAC_EXIT})"
else
  record_fail "RBAC denial" "Message was accepted despite DENY ACL"
fi

# Clean up RBAC config immediately to avoid affecting other tests
echo "  Removing DENY ACL and authorizer config..."
docker exec fsi-broker kafka-acls --bootstrap-server broker:29092 \
  --remove --deny-principal User:ANONYMOUS --operation Write \
  --topic "${RBAC_TOPIC}" --force 2>/dev/null || true
docker exec fsi-broker kafka-configs --bootstrap-server broker:29092 \
  --alter --entity-type brokers --entity-default \
  --delete-config authorizer.class.name,super.users 2>/dev/null || true
echo ""

# =============================================================================
# Error Path 3: Schema Incompatibility                                    [3/4]
# =============================================================================

echo "[3/4] Error Path 3: Schema Incompatibility"
echo "  Setting subject compatibility to FULL..."

curl -s -X PUT "${SR_URL}/config/${TOPIC}-value" \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  -d '{"compatibility":"FULL"}' >/dev/null

# Attempt to register an incompatible schema: removes existing fields and adds
# a new required field without a default. This breaks both forward and backward
# compatibility under FULL mode.
INCOMPATIBLE_SCHEMA='{"type":"record","name":"ErrorPathTest","namespace":"org.fsi.test","fields":[{"name":"test_key","type":"string"},{"name":"breaking_new_field","type":"string"}]}'

echo "  Registering incompatible schema evolution..."
set +e
COMPAT_RESPONSE=$(curl -s -X POST "${SR_URL}/subjects/${TOPIC}-value/versions" \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  -d "{\"schema\": $(echo "${INCOMPATIBLE_SCHEMA}" | jq -Rs .)}")
COMPAT_EXIT=$?
set -e

# Schema Registry should reject the incompatible evolution with a 409 or
# an error message containing "incompatible" or "compatibility"
if echo "${COMPAT_RESPONSE}" | grep -qiE "incompatible|compatibility|409|error_code"; then
  record_pass "Schema incompatibility correctly rejected by Schema Registry"
else
  record_fail "Schema incompatibility" "Incompatible schema was accepted: ${COMPAT_RESPONSE}"
fi
echo ""

# =============================================================================
# Error Path 4: Broker Failure and Recovery                               [4/4]
# =============================================================================

echo "[4/4] Error Path 4: Broker Failure and Recovery"

# Step 1: Produce a message successfully (baseline)
echo "  Step 1: Producing baseline message..."
set +e
BASELINE_OUTPUT=$(echo '{"test_key":"pre-outage","test_value":"should-succeed","timestamp":1700000000000}' \
  | docker exec -i fsi-schema-registry kafka-avro-console-producer \
    --broker-list broker:29092 \
    --topic "${TOPIC}" \
    --property schema.registry.url=http://schema-registry:8081 \
    --property value.schema="${SCHEMA}" 2>&1)
BASELINE_EXIT=$?
set -e

BASELINE_OK=false
if [ ${BASELINE_EXIT} -eq 0 ]; then
  BASELINE_OK=true
  echo "  Baseline produce succeeded."
else
  echo "  WARNING: Baseline produce failed (exit ${BASELINE_EXIT}). Test may be unreliable."
fi

# Step 2: Stop the broker
echo "  Step 2: Stopping broker..."
docker compose -f "${COMPOSE_FILE}" stop broker 2>/dev/null

# Give containers a moment to notice
sleep 3

# Step 3: Attempt produce during outage (should fail with timeout)
echo "  Step 3: Producing during broker outage (expect failure)..."
set +e
OUTAGE_OUTPUT=$(echo '{"test_key":"during-outage","test_value":"should-fail","timestamp":1700000000000}' \
  | timeout 15 docker exec -i fsi-schema-registry kafka-avro-console-producer \
    --broker-list broker:29092 \
    --topic "${TOPIC}" \
    --property schema.registry.url=http://schema-registry:8081 \
    --property value.schema="${SCHEMA}" 2>&1)
OUTAGE_EXIT=$?
set -e

OUTAGE_FAILED=false
if [ ${OUTAGE_EXIT} -ne 0 ] || echo "${OUTAGE_OUTPUT}" | grep -qiE "error|timeout|disconnect|unavailable|failed|exception"; then
  OUTAGE_FAILED=true
  echo "  Produce during outage failed as expected."
else
  echo "  WARNING: Produce during outage did not clearly fail."
fi

# Step 4: Restart broker and wait for recovery
echo "  Step 4: Restarting broker..."
docker compose -f "${COMPOSE_FILE}" start broker 2>/dev/null
wait_for_broker

# Step 5: Produce after recovery (should succeed)
echo "  Step 5: Producing after recovery..."
set +e
RECOVERY_OUTPUT=$(echo '{"test_key":"post-recovery","test_value":"should-succeed","timestamp":1700000000000}' \
  | docker exec -i fsi-schema-registry kafka-avro-console-producer \
    --broker-list broker:29092 \
    --topic "${TOPIC}" \
    --property schema.registry.url=http://schema-registry:8081 \
    --property value.schema="${SCHEMA}" 2>&1)
RECOVERY_EXIT=$?
set -e

RECOVERY_OK=false
if [ ${RECOVERY_EXIT} -eq 0 ]; then
  RECOVERY_OK=true
  echo "  Post-recovery produce succeeded."
else
  echo "  Post-recovery produce failed (exit ${RECOVERY_EXIT})."
fi

# Evaluate broker failure test
if ${BASELINE_OK} && ${OUTAGE_FAILED} && ${RECOVERY_OK}; then
  record_pass "Broker failure: baseline OK, outage detected, recovery confirmed"
elif ! ${BASELINE_OK}; then
  record_fail "Broker failure" "Baseline produce failed before outage test"
elif ! ${OUTAGE_FAILED}; then
  record_fail "Broker failure" "Produce during outage did not fail as expected"
else
  record_fail "Broker failure" "Post-recovery produce failed"
fi
echo ""

# =============================================================================
# Summary
# =============================================================================

echo "=== ERROR PATH TEST RESULTS ==="
echo "  Passed: ${PASSED}/4"
echo "  Failed: ${FAILED}/4"

if [ "${FAILED}" -gt 0 ]; then
  echo ""
  echo "RESULT: ${FAILED} ERROR PATH TESTS FAILED"
  exit 1
fi
echo ""
echo "RESULT: ALL ERROR PATH TESTS PASSED"

# Testing Patterns

**Analysis Date:** 2026-03-21

## Test Framework

**Test Approach:**
- No JUnit/TestNG configuration found in Java reference implementations
- Integration-focused testing via shell scripts and Docker Compose
- Reference implementations are designed to be copied and adapted (not tested in-place)

**Assertion Library:**
- Shell scripts: `grep` for string matching, exit codes for assertions (see `roundtrip-test.sh` lines 85-90)
- Docker-based integration testing (Compose stack defined in `reference/local-dev/`)

**Run Commands:**
```bash
# Integration test (end-to-end roundtrip)
./reference/integration-test/roundtrip-test.sh [bootstrap_server] [schema_registry_url]

# Local dev setup (start Kafka + Schema Registry)
cd reference/local-dev && docker-compose up -d

# Cleanup
docker-compose down -v
```

## Test File Organization

**Location:**
- Integration tests: `reference/integration-test/`
- Local dev environment: `reference/local-dev/`
- DR failover/failback scripts: `scripts/`
- Schema examples: `schemas/examples/`

**Naming:**
- Integration test: `roundtrip-test.sh` (describes what it tests)
- Operational scripts: `mirror-failover.sh`, `mirror-failback.sh`, `consul-flip-region.sh`, `connect-pause-all.sh`
- No test discovery pattern — scripts are explicit entry points

**Structure:**
```
reference/
├── integration-test/
│   └── roundtrip-test.sh       # Main integration test
├── local-dev/
│   ├── docker-compose.yml      # Test infrastructure
│   └── README.md
└── [language]-[consumer|producer]/
    ├── pom.xml                 # Maven config
    ├── src/main/java/          # Reference implementation (not tested)
    └── ...
```

## Integration Test Structure

**Roundtrip Test Pattern** (`reference/integration-test/roundtrip-test.sh`):

```bash
#!/usr/bin/env bash
set -euo pipefail

# Step 1: Define test data
BOOTSTRAP="${1:-localhost:9092}"
SR_URL="${2:-http://localhost:8081}"
TOPIC="test.integration.v1.roundtrip"
TEST_KEY="test-$(date +%s)"

# Step 2: Setup (create topic, register schema)
docker exec fsi-broker kafka-topics --create \
  --topic "${TOPIC}" \
  --partitions 1 \
  --replication-factor 1 \
  --bootstrap-server broker:29092 \
  --if-not-exists

# Step 3: Produce a record
echo "{...}" | docker exec -i fsi-schema-registry kafka-avro-console-producer ...

# Step 4: Consume and verify
CONSUMED=$(docker exec fsi-schema-registry kafka-avro-console-consumer ...)
if echo "$CONSUMED" | grep -q "${TEST_KEY}"; then
  echo "  OK — Record roundtripped successfully"
else
  echo "  FAIL — Expected key in record"
  exit 1
fi

# Step 5: Verify system state
curl -s "${SR_URL}/subjects" | grep -q "${TOPIC}-value"
```

**Test Flow:**
1. Create topic with single partition (lines 29-35)
2. Register Avro schema via REST API (lines 38-60)
3. Produce single record with Avro serialization (lines 62-72)
4. Consume single record and verify key present (lines 74-91)
5. Verify schema subject registered in Schema Registry (lines 93-101)
6. Cleanup instructions provided (line 111)

**Assertions:**
- Exit code: Script exits 1 on any error (via `set -e`)
- String matching: `grep -q` for silent match check (line 85)
- Schema registration: API response contains subject (line 96)
- Print summary on success (lines 105-110)

## Local Dev Environment

**Docker Compose Setup** (`reference/local-dev/docker-compose.yml`):
- `fsi-broker`: Kafka broker on port 9092
- `fsi-schema-registry`: Confluent Schema Registry on port 8081
- `fsi-connect`: Kafka Connect (distributed mode) for source/sink testing
- Volume mounts for persistent storage during test runs

**Usage:**
```bash
cd reference/local-dev
docker-compose up -d           # Start stack
docker-compose logs -f broker  # View broker logs
docker-compose down -v         # Clean up (remove volumes)
```

## Test Categories

**Integration Tests:**
- **Scope:** End-to-end produce-consume-deserialize roundtrip
- **Coverage:** Schema Registry integration, Avro serialization/deserialization, topic creation, offset management
- **Approach:** Shell script with Docker Compose stack (see `roundtrip-test.sh`)
- **Triggers:** Manual run or CI pipeline (if `.github/workflows/` defines test jobs)

**Operational Verification Scripts:**
- **Scope:** Failover/failback procedures, region flips, connector state management
- **Coverage:** Cluster link status, mirror topic promotion, DNS flip coordination
- **Approach:** Confluent CLI wrapper scripts with confirmation prompts (see `mirror-failover.sh`, `consul-flip-region.sh`)
- **Safety:** Require user confirmation (`read -p "Proceed?"`) before destructive operations

**Reference Implementations:**
- **Scope:** NOT unit tested — designed for copy-adapt pattern
- **Coverage:** Configuration patterns, error handling, JMX metrics, graceful shutdown
- **Approach:** Self-documenting with JavaDoc comments (see `FsiProducer.java`, `FsiConsumer.java`)
- **Usage:** Teams copy these to their projects and extend

**Terraform Validation:**
- **Scope:** Variable validation, schema references, resource dependencies
- **Coverage:** Input constraints (domain/app/entity naming), SLA tier mappings, RBAC rule syntax
- **Approach:** Inline `validation` blocks with regex (see `modules/topic/variables.tf`)
- **Triggers:** `terraform validate` before plan/apply

## Test Data

**Fixtures** (`reference/integration-test/roundtrip-test.sh` lines 15-19):
```bash
TOPIC="test.integration.v1.roundtrip"
TEST_KEY="test-$(date +%s)"
TEST_VALUE="roundtrip-$(uuidgen 2>/dev/null || echo $RANDOM)"
```
- Topic name follows FSI convention (domain.app.version.entity)
- Key: timestamp-based for uniqueness
- Value: UUID or random for verification

**Schema Fixtures** (`schemas/examples/`):
- `account-transaction.avsc`: Financial transaction with PII fields
- `fraud-score-result.avsc`: Risk scoring output
- `integration-event.avsc`: Generic event envelope
- Used as references; copied to project-specific `schemas/` during engagement

**Test Record Structure** (`roundtrip-test.sh` lines 40-49):
```json
{
  "type": "record",
  "name": "RoundtripTest",
  "namespace": "org.fsi.test",
  "fields": [
    {"name": "test_key", "type": "string"},
    {"name": "test_value", "type": "string"},
    {"name": "timestamp", "type": {"type": "long", "logicalType": "timestamp-millis"}}
  ]
}
```
- Minimal schema for roundtrip verification
- Includes timestamp with logical type for data type validation
- Registered dynamically via Schema Registry REST API

## Mocking

**Framework:** No mocking framework detected

**Patterns:**
- Java reference implementations use concrete Kafka client (no mocks)
- Integration tests use real Docker-based Kafka cluster
- Docker containers act as test doubles for external services (broker, schema registry, connect)

**What to Mock:**
- Not applicable — integration tests use real services
- Reference implementations include comments suggesting DLQ/retry/alert handlers (see `FsiProducer.java` lines 138-141) but don't implement them — teams add per their requirements

**What NOT to Mock:**
- Kafka client (use real client for actual integration verification)
- Schema Registry (use real instance in Docker Compose)
- Serialization (Avro schema is real, ensures type correctness)

## Coverage

**Requirements:** No coverage tool configured

**View Coverage:** Not applicable — shell script integration tests lack code coverage reporting

**Reference Implementations:**
- Designed for adaptation (teams copy and extend)
- Coverage is team's responsibility after copy/adapt
- Patterns documented via JavaDoc and inline comments

## Terraform Testing

**Validation:**
```bash
terraform validate
```
- Checks syntax and resource references
- Runs inline variable validations (regex patterns, enum checks)
- Does NOT provision resources

**Plan + Review:**
```bash
terraform plan -out=tfplan
# Review output for unintended changes
terraform apply tfplan
```
- Plan shows resource changes before apply
- Manual review catches breaking modifications
- CI pipeline (`.github/workflows/terraform-plan.yml`) runs plan on PR, blocks merge until reviewed

**Test Topics:**
- Create test topics in non-production environments first
- Verify topic creation, schema registration, RBAC bindings via `confluent kafka topic list` + `confluent schema list-subjects`
- No automated post-apply validation detected — manual verification required

## Operational Testing

**DR Failover Runbook** (`scripts/mirror-failover.sh`):
```bash
# Step 1: List mirror topics (status check)
confluent kafka mirror list --link "${LINK_NAME}" -o json

# Step 2: Promote mirrors (the actual failover)
confluent kafka mirror failover ${MIRROR_TOPICS} --link "${LINK_NAME}"

# Step 3: Verify promotion (post-failover check)
confluent kafka mirror list --link "${LINK_NAME}"
```
- Fetch before action (verify precondition)
- Execute action (promote mirrors)
- Verify after (confirm success)
- User confirmation before destructive operation (line 34-35)

**Integration Test Verification Steps** (`roundtrip-test.sh`):
```bash
echo "[1/5] Creating topic..."        # Named steps with progress
echo "[2/5] Registering schema..."
echo "[3/5] Producing record..."
echo "[4/5] Consuming record..."      # Verification
echo "[5/5] Verifying schema..."      # Post-condition check
```
- Clear numbered steps for debugging
- Each step has explicit success/failure messages
- Final summary reports what was tested (lines 105-110)

## Common Testing Scenarios

**Happy Path — Roundtrip Test** (`roundtrip-test.sh`):
1. Create topic
2. Register schema
3. Produce avro record with key
4. Consume record with key verification
5. Confirm schema in registry

**Error Handling — Test Variations (Not Implemented):**
- Serialize error (invalid Avro data)
- Deserialize error (schema incompatibility)
- Broker error (connection failure)
- Schema Registry error (unreachable)

**Failover Path — Operational Verification** (`mirror-failover.sh`):
1. List mirror topics (precondition)
2. Confirm user intent (confirmation gate)
3. Promote mirror topics to primary
4. Verify promotion status
5. Next step guidance

## Testing Best Practices Used

**What This Codebase Does Well:**
- **Integration-first:** Real systems tested, not mocks
- **Documented test data:** Schemas versioned in repo (`schemas/examples/`)
- **Operational runbooks:** DR procedures are versioned scripts (`scripts/mirror-*.sh`)
- **Self-documenting:** Test scripts have numbered steps and clear output
- **Fail-fast:** `set -euo pipefail` in shell scripts catches errors immediately
- **Cleanup instructions:** Test scripts document how to clean up (see line 111)

**What's Missing:**
- Unit test framework for reference implementations
- Automated code coverage reporting
- Post-apply Terraform state validation
- Error path test coverage (serialization failures, broker failures, timeout scenarios)
- CI/CD integration test automation (workflows exist but content not shown)

---

*Testing analysis: 2026-03-21*

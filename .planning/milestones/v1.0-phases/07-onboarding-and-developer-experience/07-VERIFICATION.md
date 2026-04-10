---
phase: 07-onboarding-and-developer-experience
verified: 2026-03-27T00:00:00Z
status: passed
score: 11/11 must-haves verified
re_verification: null
gaps: []
human_verification:
  - test: "Render GitHub issue form in real GitHub 'New Issue' UI"
    expected: "Structured dropdown fields appear for deployment model, SLA tier, data classification, and optional Flink section with correct options"
    why_human: "GitHub YAML issue form rendering requires the GitHub UI — cannot be verified by linting alone"
  - test: "Run error-path integration tests against live Docker Compose environment"
    expected: "All 4 paths (serialization, RBAC, schema compat, broker failure) produce PASS results"
    why_human: "Tests require running Docker containers with real services; cannot verify script behavior without a live environment"
  - test: "Build and start Flink services via `docker compose --profile flink up -d`"
    expected: "Flink JobManager, TaskManager, and SQL Client start; `docker exec -it fsi-flink-sql-client /opt/flink/bin/sql-client.sh` launches SQL prompt; Flink UI reachable at localhost:8085"
    why_human: "Requires Docker build from Maven Central (wget of JARs) and container startup — cannot verify without running the build"
---

# Phase 7: Onboarding and Developer Experience Verification Report

**Phase Goal:** Self-service intake forms, reference implementations in all three languages with DLQ handling, error-path integration tests, and local Flink dev environment.
**Verified:** 2026-03-27
**Status:** PASSED
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Intake form renders in GitHub 'New Issue' dropdown with structured dropdowns for deployment model, SLA tier, data classification, and optional Flink section | VERIFIED | `.github/ISSUE_TEMPLATE/new-topic-request.yml` validated as YAML, contains `type: dropdown` for all 4 fields, all 5 deployment model options present, Flink section marked `required: false` |
| 2 | C4E pre-check script validates naming convention, schema compatibility, RBAC completeness, SLA tier consistency, and PII field audit from .tf source files | VERIFIED | `ci/scripts/c4e-precheck.py` has `def check_naming`, `def check_schema`, `def check_rbac`, `def check_sla_tier`, `def check_pii`; uses stdlib only; `--help` exits 0; domain regex `^[a-z][a-z0-9-]{1,30}$` confirmed |
| 3 | CI workflow runs C4E pre-check on PRs touching scenarios/ or schemas/ directories before human review | VERIFIED | `.github/workflows/terraform-scenario.yml` contains "C4E Pre-Check Suite" step with `if: inputs.mode == 'plan'`, positioned after "Check Compatibility Overrides" and before "Terraform Init", calls `python3 ci/scripts/c4e-precheck.py` with `--scenario-dir` and `--schemas-dir` args |
| 4 | Python producer sends Avro-serialized messages with idempotence, metrics, and DLQ routing — identical method signatures to Java FsiProducer | VERIFIED | `fsi_producer.py` has `send`, `send_sync`, `flush`, `close`, `__enter__`, `__exit__`; uses `AvroSerializer` (not deprecated `AvroProducer`); `enable.idempotence: True`, `acks: all`; DLQ wired via `from fsi_dlq_handler import FsiDlqHandler` |
| 5 | Python consumer deserializes Avro with manual commit and handler function pattern — identical to Java FsiConsumer | VERIFIED | `fsi_consumer.py` has `start`, `shutdown`, `__enter__`, `__exit__`; uses `AvroDeserializer`; `enable.auto.commit: False`; SIGTERM/SIGINT handlers; callable handler pattern |
| 6 | DLQ handler in all three languages (Java, .NET, Python) implements 3-retry exponential backoff with error categorization and Kafka headers metadata | VERIFIED | All 3 handlers confirmed: `MAX_RETRIES=3`/`BASE_BACKOFF_MS=1000` in Java and .NET; `MAX_RETRIES=3`/`BASE_BACKOFF_S=1` in Python; 6 DLQ headers (`dlq.original.topic`, `dlq.error.type`, `dlq.error.message`, `dlq.timestamp`, `dlq.retry.count`, `dlq.producer.client.id`) in all 3 |
| 7 | DLQ topic naming follows `{source-topic}.dlq` convention across all languages | VERIFIED | Python: `f"{source_topic}.dlq"`; Java: `sourceTopic + ".dlq"`; .NET: `sourceTopic + ".dlq"` |
| 8 | Error-path test script validates 4 failure scenarios: serialization failure, RBAC denial, schema incompatibility, and broker failure | VERIFIED | `error-path-tests.sh` has sections `[1/4]` through `[4/4]`; bash syntax check passes; `DLQ_TOPIC` set; `trap cleanup EXIT` present; `set -euo pipefail` at top |
| 9 | Local dev Docker Compose starts Flink jobmanager + taskmanager via --profile flink alongside existing Kafka, SR, and Connect | VERIFIED | `docker-compose.yml` adds `flink-jobmanager`, `flink-taskmanager`, `flink-sql-client` services all with `profiles: [flink]`; existing broker/schema-registry/connect services unchanged; port `8085:8081` for Flink UI |
| 10 | Flink SQL client connects to local Kafka and Schema Registry for stream processing development | VERIFIED | `flink-sql/Dockerfile` uses `FROM flink:1.20-java17`, downloads `flink-sql-connector-kafka-3.2.0-1.20.jar` and `flink-sql-avro-confluent-1.20.0.jar`; `flink-sql-client` service with `command: sleep infinity` ready for `docker exec -it fsi-flink-sql-client /opt/flink/bin/sql-client.sh` |
| 11 | Python files parse without AST errors (syntactic validity gate) | VERIFIED | `ast.parse()` passes on all three: `fsi_producer.py`, `fsi_dlq_handler.py`, `fsi_consumer.py` |

**Score:** 11/11 truths verified (3 flagged for human testing — environment-dependent behavior)

---

## Required Artifacts

### Plan 01: Intake Form & C4E Automation

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `.github/ISSUE_TEMPLATE/new-topic-request.yml` | YAML issue form with structured dropdowns | VERIFIED | Exists, YAML valid, contains `type: dropdown` for deployment-model/sla-tier/data-classification/flink-required; all 5 deployment model options; generic FSI examples; no cncb/rtfd/ofac |
| `ci/scripts/c4e-precheck.py` | C4E validation script with 5 check categories | VERIFIED | Exists, 486 lines, all 5 `def check_*` functions, stdlib-only imports, `--scenario-dir` required arg, exits 0 on `--help` |
| `.github/workflows/terraform-scenario.yml` | CI workflow with C4E pre-check step | VERIFIED | Contains "C4E Pre-Check Suite" step, `if: inputs.mode == 'plan'`, correct argument passing |
| `.github/ISSUE_TEMPLATE/new-topic-request-legacy.md` | Deprecated legacy form with comment | VERIFIED | Exists, first line is DEPRECATED comment |

### Plan 02: Reference Implementations & DLQ

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `reference/python-producer/fsi_producer.py` | Python FsiProducer with Avro, idempotence, Prometheus, DLQ | VERIFIED | 332 lines, `class FsiProducer`, all required methods, modern `AvroSerializer` API, DLQ wired |
| `reference/python-producer/fsi_dlq_handler.py` | Python DLQ handler with error categorization and retry | VERIFIED | 236 lines, `class FsiDlqHandler`, `NON_RETRYABLE_ERRORS` set, `handle_error`/`_classify_error`/`close` methods, `2 ** retry_count` backoff |
| `reference/python-consumer/fsi_consumer.py` | Python FsiConsumer with manual commit and handler pattern | VERIFIED | 284 lines, `class FsiConsumer`, `AvroDeserializer`, `enable.auto.commit: False`, SIGTERM/SIGINT handlers |
| `reference/java-producer/.../FsiDlqHandler.java` | Java DLQ handler retrofitted | VERIFIED | 191 lines, `MAX_RETRIES=3`, `BASE_BACKOFF_MS=1000`, `NON_RETRYABLE` set, all 4 methods, 6 DLQ headers |
| `reference/dotnet-producer/FsiDlqHandler.cs` | .NET DLQ handler retrofitted | VERIFIED | 195 lines, `MaxRetries=3`, `BaseBackoffMs=1000`, `public long DlqSent`, `Dispose()` logs "Total DLQ messages" |
| `reference/python-producer/requirements.txt` | confluent-kafka[avro]==2.13.2 + prometheus_client==0.24.1 | VERIFIED | Exact versions confirmed |
| `reference/python-consumer/requirements.txt` | confluent-kafka[avro]==2.13.2 + prometheus_client==0.24.1 | VERIFIED | Exact versions confirmed |

### Plan 03: Error-Path Tests & Flink Local Dev

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `reference/integration-test/error-path-tests.sh` | 4 error-path test scenarios | VERIFIED | Passes `bash -n`; sections [1/4]-[4/4] confirmed; `DLQ_TOPIC` set; `trap cleanup EXIT`; `PASSED`/`FAILED` counters; exits 1 on failure |
| `reference/local-dev/docker-compose.yml` | Extended with Flink services under 'flink' profile | VERIFIED | `flink-jobmanager`/`flink-taskmanager`/`flink-sql-client` all with `profiles: [flink]`; existing services preserved; port `8085:8081` |
| `reference/local-dev/flink-sql/Dockerfile` | Custom Flink image with Kafka + Avro-Confluent connector JARs | VERIFIED | `FROM flink:1.20-java17`; both JAR URLs present (`3.2.0-1.20` and `1.20.0`); version rationale comment included |
| `reference/local-dev/README.md` | Local dev documentation | VERIFIED | Contains services table, Quick Start, Flink SQL section with `docker compose --profile flink up -d` and `docker exec -it fsi-flink-sql-client` |

---

## Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `.github/workflows/terraform-scenario.yml` | `ci/scripts/c4e-precheck.py` | CI step calling `python3 ci/scripts/c4e-precheck.py` | WIRED | Step "C4E Pre-Check Suite" at line 129; `--scenario-dir ${{ inputs.scenario-dir }}` and `--schemas-dir schemas/` passed |
| `ci/scripts/c4e-precheck.py` | `modules/topic/variables.tf` | Regex extraction of module args from .tf files | WIRED | Script parses `domain|application|schema_version|entity|sla_tier|data_classification|schema_file|owner|compatibility_override` via regex; validates against `^[a-z][a-z0-9-]{1,30}$` (matching variables.tf) |
| `reference/python-producer/fsi_producer.py` | `reference/python-producer/fsi_dlq_handler.py` | `from fsi_dlq_handler import FsiDlqHandler` | WIRED | Import at line 21; `FsiDlqHandler(config, self._topic_name)` instantiated in `__init__`; `handle_error()` called in delivery callback |
| `reference/python-producer/fsi_producer.py` | `confluent_kafka.schema_registry.avro` | `from confluent_kafka.schema_registry.avro import AvroSerializer` | WIRED | Line 13; `AvroSerializer` used for value serialization (not deprecated `AvroProducer`) |
| `reference/java-producer/.../FsiProducer.java` | `reference/java-producer/.../FsiDlqHandler.java` | DLQ routing in send callback | WIRED | `private final FsiDlqHandler dlqHandler` (line 36); `new FsiDlqHandler(config, topicName)` (line 65); `dlqHandler.sendToDlq(keyBytes, null, exception, 0)` in send callback (line 147) |
| `reference/integration-test/error-path-tests.sh` | `reference/local-dev/docker-compose.yml` | `docker compose stop broker` / `docker compose start broker` | WIRED | Lines 282, 309: `docker compose -f "${COMPOSE_FILE}" stop broker` and `start broker` using computed `COMPOSE_FILE` path |
| `reference/local-dev/docker-compose.yml` | `reference/local-dev/flink-sql/Dockerfile` | `build.context: ./flink-sql` | WIRED | `flink-jobmanager`, `flink-taskmanager`, `flink-sql-client` all use `build: {context: ./flink-sql, dockerfile: Dockerfile}` |
| `reference/local-dev/flink-sql/Dockerfile` | `flink-sql-connector-kafka` | `wget` from Maven Central | WIRED | `flink-sql-connector-kafka-3.2.0-1.20.jar` and `flink-sql-avro-confluent-1.20.0.jar` downloaded via `RUN wget` |

---

## Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| ONBOARD-01 | 07-01 | Generic FSI intake form with deployment model selection, no client-specific references | SATISFIED | `new-topic-request.yml` has deployment-model dropdown with all 5 models; no cncb/rtfd/ofac found; generic examples (corebanking, fraud, compliance) |
| ONBOARD-02 | 07-01 | C4E review automation in CI validates naming, schema compat, RBAC completeness, SLA tier | SATISFIED | `c4e-precheck.py` implements all 5 checks; wired into `terraform-scenario.yml` as blocking step before Terraform init |
| ONBOARD-03 | 07-02 | Python reference producer/consumer using confluent-kafka-python | SATISFIED | `fsi_producer.py` and `fsi_consumer.py` both exist; modern API (AvroSerializer/AvroDeserializer); method signatures mirror Java; README with usage examples |
| ONBOARD-04 | 07-03 | Integration test suite covers error paths: serialization, RBAC denial, schema incompatibility, broker failure | SATISFIED | `error-path-tests.sh` has all 4 scenarios with numbered sections, PASS/FAIL reporting, cleanup, broker stop/start |
| ONBOARD-05 | 07-03 | Local dev Docker Compose extended with Flink for stream processing development | SATISFIED | `docker-compose.yml` has 3 Flink services under `--profile flink`; custom Dockerfile with connector JARs; README documents Flink SQL access |
| ONBOARD-06 | 07-02 | DLQ pattern in reference producers (Java, .NET, Python) with exponential backoff retry, error categorization, and JMX metrics | SATISFIED | All 3 DLQ handlers: 3-retry backoff (1s/2s/4s), 5-category error classification, 6 Kafka headers; Java: JMX `getDlqSent()` via MBean; Python: Prometheus Counter; .NET: `public long DlqSent` + Dispose() log |

**All 6 ONBOARD requirements: SATISFIED**

Traceability matrix in REQUIREMENTS.md correctly maps ONBOARD-01 through ONBOARD-06 to Phase 7, all marked Complete. No orphaned requirements found.

---

## Anti-Patterns Found

| File | Pattern | Severity | Assessment |
|------|---------|----------|-----------|
| `reference/java-producer/.../FsiProducer.java` line 147 | `dlqHandler.sendToDlq(keyBytes, null, exception, 0)` — value is `null` | INFO | The `null` value is intentional and documented ("value bytes not available in callback"). The DLQ handler accepts null value gracefully. This is a known limitation of the callback approach (serialized bytes are not accessible after the callback fires). Not a blocker. |
| `reference/python-producer/fsi_dlq_handler.py` | DLQ uses simple counter `self._dlq_sent += 1` instead of Prometheus Counter | INFO | The PLAN spec for this file called for a prometheus Counter named `fsi_dlq_handler_total_sent`. The file uses a plain int counter instead (exposed as `@property dlq_sent`). The parent `fsi_producer.py` tracks DLQ routing via its own `_dlq_sent` Prometheus Counter. Functional parity is maintained across languages but implementation differs from spec. Not a blocker — metrics are still observable. |

No blocker or warning-level anti-patterns found. No placeholder/TODO/stub patterns detected in any delivered file.

---

## Human Verification Required

### 1. GitHub Issue Form Rendering

**Test:** Navigate to the repository's Issues tab in GitHub, click "New Issue", and confirm the "New Topic Request" form appears with the correct structured fields.
**Expected:** Dropdown for "Deployment Model" shows 5 options (Confluent Cloud - AWS/Azure/GCP, Confluent for Kubernetes (OpenShift), Confluent Platform (RHEL)); Flink section appears as optional (not required); labels `topic-request` and `c4e-review` are automatically applied on submission.
**Why human:** GitHub YAML issue form rendering is a UI behavior that requires a live GitHub repository — cannot be verified by YAML linting alone.

### 2. Error-Path Integration Tests (Live Execution)

**Test:** Start local dev environment with `cd reference/local-dev && docker compose up -d`, wait for all services to be healthy, then run `bash reference/integration-test/error-path-tests.sh`.
**Expected:** All 4 tests PASS — "Serialization failure detected correctly", "RBAC denial detected", "Schema incompatibility correctly rejected", "Broker failure: baseline OK, outage detected, recovery confirmed". Final output: "RESULT: ALL ERROR PATH TESTS PASSED".
**Why human:** Tests require running Docker containers with `fsi-broker`, `fsi-schema-registry`, and their CLI tools. The RBAC test also modifies live broker config (ACL authorizer), which requires a real running broker. Cannot verify script behavior without a live environment.

### 3. Flink Local Dev Build and Startup

**Test:** Run `cd reference/local-dev && docker compose --profile flink up -d`, wait for `fsi-flink-jobmanager` healthcheck to pass, then run `docker exec -it fsi-flink-sql-client /opt/flink/bin/sql-client.sh`.
**Expected:** Flink SQL client launches with interactive prompt; Flink Web UI reachable at http://localhost:8085; a `CREATE TABLE ... WITH ('connector' = 'kafka', 'format' = 'avro-confluent')` statement executes without "class not found" errors, confirming connector JARs are installed.
**Why human:** Requires Docker to build the custom Flink image (downloading JARs from Maven Central) and run containers. The JAR download and connector registration cannot be verified offline.

---

## Commit Verification

All 6 commits from SUMMARYs confirmed in git log:

| Commit | Summary |
|--------|---------|
| `8480e35` | feat(07-01): intake form YAML + C4E pre-check script |
| `42da5d8` | feat(07-01): wire C4E pre-check into CI workflow |
| `56095f7` | feat(07-02): add Python reference producer, consumer, and DLQ handler |
| `b100efb` | feat(07-02): retrofit DLQ handling into Java and .NET producers |
| `a7bce84` | feat(07-03): create error-path integration test script |
| `d117dfa` | feat(07-03): extend Docker Compose with Flink and add local dev README |

---

## Gaps Summary

No gaps found. All 11 must-haves verified against actual codebase content. All 6 ONBOARD requirements satisfied. All commits exist in git history.

Three items require human verification (environment-dependent behavior: GitHub UI form rendering, live Docker test execution, Flink container build). These are not blockers to phase completion — they are acceptance tests that require running infrastructure.

---

_Verified: 2026-03-27_
_Verifier: Claude (gsd-verifier)_

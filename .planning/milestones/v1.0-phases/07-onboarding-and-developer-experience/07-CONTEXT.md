# Phase 7: Onboarding and Developer Experience - Context

**Gathered:** 2026-03-27
**Status:** Ready for planning

<domain>
## Phase Boundary

New FSI teams can go from intake form to first message produced in under a day. This phase delivers: generic intake form with deployment model + Flink fields, C4E review automation (full pre-check suite before human gate), Python reference producer/consumer, error-path integration tests, local dev with Flink, and DLQ patterns across all three languages (Java, .NET, Python).

</domain>

<decisions>
## Implementation Decisions

### Intake Form & C4E Review Flow
- **D-01:** Convert existing `new-topic-request.md` (freeform markdown) to GitHub issue form (YAML-based) with structured dropdowns for deployment model, SLA tier, data classification
- **D-02:** Replace client-specific domain examples (cncb, rtfd, ofac) with generic FSI examples (corebanking, fraud, compliance)
- **D-03:** Add optional Flink section to intake form — compute pool size, SQL statements to deploy. Teams skip if not using Flink
- **D-04:** Full C4E pre-check suite in CI: naming validation + schema compat + RBAC completeness (SA exists for each binding) + SLA tier consistency (retention matches tier) + PII field audit. Human review is the final gate, not the first check

### Python Client Design
- **D-05:** Mirror Java pattern exactly — class-based FsiProducer/FsiConsumer with dict config, Avro serialization, same method signatures (send, send_sync, consume). Consistent across languages for team comparison
- **D-06:** Use confluent-kafka-python library (not kafka-python) for parity with Java's confluent client
- **D-07:** Metrics via prometheus_client library exposing counters/gauges on HTTP port. Works with all 6 observability providers from Phase 5

### Error-Path Test Strategy
- **D-08:** All error-path tests run against Docker Compose (real Kafka + SR). Simulate failures by stopping containers, sending bad data, revoking ACLs
- **D-09:** Shell scripts extending existing roundtrip-test.sh pattern — error-path-tests.sh with numbered steps. Consistent with existing test infrastructure, no new dependencies
- **D-10:** Four required error paths: serialization failure, RBAC denial, schema incompatibility, broker failure

### DLQ Pattern Across Languages
- **D-11:** 3 retries with exponential backoff (1s/2s/4s). Error categorization: retryable (broker timeout, leader election) vs non-retryable (serialization, schema). Non-retryable go straight to DLQ
- **D-12:** DLQ topic naming: `{source-topic}.dlq` suffix convention. Matches CC Flink DLQ pattern from Phase 6. Auto-discoverable by observability
- **D-13:** DLQ pattern implemented in all three reference producers: Java (FsiProducer.java), .NET (FsiProducer.cs), Python (new fsi_producer.py)

### Claude's Discretion
- DLQ record format (what metadata to include: original topic, error type, timestamp, stack trace)
- Python project structure (directory layout, requirements.txt vs pyproject.toml)
- Error-path test Docker Compose modifications (what to stop/restart for each scenario)
- Local dev Flink container configuration (Apache Flink version, SQL client setup)
- C4E pre-check script implementation language (Python or shell)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Intake and Governance
- `.github/ISSUE_TEMPLATE/new-topic-request.md` -- Current intake form to be converted to YAML issue form
- `.github/pull_request_template.md` -- PR template with compliance checkboxes (Phase 3)
- `docs/onboarding.md` -- Self-service onboarding workflow
- `docs/schema-guide.md` -- Schema naming and compatibility rules

### CI Workflows
- `.github/workflows/terraform-plan.yml` -- Existing PR validation pipeline (naming, schema, Terraform)
- `.github/workflows/terraform-scenario.yml` -- Reusable scenario workflow (Phase 2)

### Reference Implementations
- `reference/java-producer/src/main/java/org/fsi/kafka/producer/FsiProducer.java` -- Java producer pattern to mirror in Python
- `reference/java-consumer/src/main/java/org/fsi/kafka/consumer/FsiConsumer.java` -- Java consumer pattern to mirror
- `reference/dotnet-producer/FsiProducer.cs` -- .NET producer for DLQ retrofit
- `reference/dotnet-consumer/FsiConsumer.cs` -- .NET consumer reference

### Testing
- `reference/integration-test/roundtrip-test.sh` -- Existing happy-path test pattern to extend
- `reference/local-dev/docker-compose.yml` -- Docker Compose to extend with Flink

### Flink
- `reference/flink-sql/README.md` -- Flink SQL usage guide (Phase 6)
- `reference/flink-sql/dlq-pattern.sql` -- CC Flink DLQ pattern for naming alignment

### ADRs
- `docs/adr/006-oauth-vs-api-keys.md` -- Auth decision affecting client configuration
- `docs/adr/007-topic-naming.md` -- Topic naming convention for validation rules
- `docs/adr/008-dr-tier-classification.md` -- SLA tier definitions used in C4E checks

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `FsiProducer.java` / `FsiConsumer.java`: Complete idempotent producer and manual-commit consumer patterns to replicate in Python
- `roundtrip-test.sh`: 5-step integration test pattern (create topic, register schema, produce, consume, verify) — extend for error paths
- `docker-compose.yml`: Kafka 7.6.0 + SR 7.6.0 + Connect 7.6.0 — add Flink container
- `terraform-scenario.yml`: Reusable CI workflow pattern for C4E checks

### Established Patterns
- Map/dict-based config injection (Java constructor takes `Map<String, String>`, .NET similar)
- Handler functions as functional interfaces (consumer `BiConsumer<String, GenericRecord>`)
- `set -euo pipefail` in all shell scripts with numbered steps and explicit success/failure messages
- SLA-tier-based behavior (critical/standard/best-effort) drives defaults throughout
- Per-provider observability templates (Phase 5) — Python prometheus_client aligns with Grafana/Prometheus

### Integration Points
- New Python client in `reference/python-producer/` and `reference/python-consumer/`
- Error-path tests in `reference/integration-test/error-path-tests.sh`
- Flink added to `reference/local-dev/docker-compose.yml`
- C4E check script in CI (new workflow step or standalone script)
- DLQ modifications to existing `reference/java-producer/` and `reference/dotnet-producer/`

</code_context>

<specifics>
## Specific Ideas

No specific requirements -- open to standard approaches.

</specifics>

<deferred>
## Deferred Ideas

None -- discussion stayed within phase scope.

</deferred>

---

*Phase: 07-onboarding-and-developer-experience*
*Context gathered: 2026-03-27*

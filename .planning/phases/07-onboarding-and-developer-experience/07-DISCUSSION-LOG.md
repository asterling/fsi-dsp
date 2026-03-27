# Phase 7: Onboarding and Developer Experience - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md -- this log preserves the alternatives considered.

**Date:** 2026-03-27
**Phase:** 07-onboarding-and-developer-experience
**Areas discussed:** Intake & C4E review flow, Python client design, Error-path test strategy, DLQ pattern across languages

---

## Intake & C4E Review Flow

| Option | Description | Selected |
|--------|-------------|----------|
| GitHub issue form (YAML) | Structured dropdowns for deployment model, SLA tier, data classification. Validates inputs before submission. | ✓ |
| Freeform markdown | Keep current format but replace client-specific examples with generic FSI ones. | |
| You decide | Claude picks the best format. | |

**User's choice:** GitHub issue form (YAML)
**Notes:** None

| Option | Description | Selected |
|--------|-------------|----------|
| Full pre-check suite | Naming + schema compat + RBAC completeness + SLA tier consistency + PII field audit. Human review is final gate. | ✓ |
| Lightweight checks only | Naming + schema compat only. Human reviewer checks RBAC and compliance manually. | |
| You decide | Claude determines the right balance. | |

**User's choice:** Full pre-check suite
**Notes:** None

| Option | Description | Selected |
|--------|-------------|----------|
| Topic + Flink | Add optional Flink section to form. Teams skip if not using Flink. | ✓ |
| Topic only | Flink requests handled separately or ad-hoc. | |

**User's choice:** Topic + Flink
**Notes:** None

---

## Python Client Design

| Option | Description | Selected |
|--------|-------------|----------|
| Mirror Java pattern | Class-based FsiProducer/FsiConsumer with dict config, Avro serialization, same method signatures. | ✓ |
| Pythonic idioms | Context managers, generators for consuming, dataclasses for config. | |
| You decide | Claude picks the right balance. | |

**User's choice:** Mirror Java pattern
**Notes:** None

| Option | Description | Selected |
|--------|-------------|----------|
| Prometheus client | prometheus_client library exposes counters/gauges on HTTP port. Works with all 6 observability providers. | ✓ |
| Structured logging only | Log metrics as JSON lines. No HTTP endpoint. | |
| You decide | Claude picks based on existing observability templates. | |

**User's choice:** Prometheus client
**Notes:** None

---

## Error-Path Test Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Docker Compose | Real Kafka + SR in Docker. Simulate failures by stopping containers, sending bad data, revoking ACLs. | ✓ |
| Mock-based | Python/shell scripts that simulate error responses without Docker. | |
| Hybrid | Docker Compose for serialization/schema errors, mocked for broker/RBAC failures. | |

**User's choice:** Docker Compose
**Notes:** None

| Option | Description | Selected |
|--------|-------------|----------|
| Shell scripts | Extend existing roundtrip-test.sh pattern. error-path-tests.sh with numbered steps. | ✓ |
| Python pytest | pytest with confluent-kafka-python. Better assertions, parameterized tests. | |
| You decide | Claude picks based on CI integration and existing patterns. | |

**User's choice:** Shell scripts
**Notes:** None

---

## DLQ Pattern Across Languages

| Option | Description | Selected |
|--------|-------------|----------|
| 3 retries, exponential backoff | 1s/2s/4s backoff. Categorize errors as retryable vs non-retryable. Non-retryable go straight to DLQ. | ✓ |
| No retry, immediate DLQ | Any produce failure goes directly to DLQ topic. | |
| Configurable retry | Default 3 retries but configurable via config map. | |

**User's choice:** 3 retries, exponential backoff
**Notes:** None

| Option | Description | Selected |
|--------|-------------|----------|
| {source-topic}.dlq | Append .dlq suffix to source topic name. Matches CC Flink DLQ pattern from Phase 6. | ✓ |
| Dedicated dlq.{domain}.errors | Separate DLQ namespace per domain. | |

**User's choice:** {source-topic}.dlq
**Notes:** None

---

## Claude's Discretion

- DLQ record format (metadata fields)
- Python project structure (directory layout, dependency management)
- Error-path test Docker Compose modifications
- Local dev Flink container configuration
- C4E pre-check script implementation language

## Deferred Ideas

None -- discussion stayed within phase scope.

# ADR-002: Schema compatibility modes by SLA tier

**Status:** Accepted
**Date:** 2026-03-21
**Author:** Jeremy Hogan

## Context
Schema compatibility determines whether a schema change is allowed or rejected by Schema Registry. Different topics have different risk profiles — core banking transactions require maximum protection, while integration events need flexibility.

## Decision
Compatibility mode is automatically derived from the topic's SLA tier:

| SLA Tier    | Compatibility Mode    | Rationale |
|-------------|----------------------|-----------|
| critical    | FULL_TRANSITIVE      | Both forward and backward compatible across all versions |
| standard    | BACKWARD_TRANSITIVE  | Consumers can be upgraded before producers |
| best-effort | BACKWARD             | Standard Confluent default |

Exception: OFAC topics use FULL_TRANSITIVE regardless of SLA tier (compliance/audit requirement, override in Terraform).

The Terraform module enforces this mapping. An optional `compatibility_override` variable exists for documented exceptions.

## Consequences
- Critical topics (CNCB, RTFD) cannot have fields removed or types changed
- Schema evolution for critical topics is limited to: adding optional fields with defaults
- Teams must plan schema changes carefully for critical topics (shift-left design)
- Standard topics have more flexibility but still prevent breaking consumers

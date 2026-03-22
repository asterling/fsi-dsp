# ADR-007: Topic Naming Convention

**Status:** Accepted
**Date:** 2026-03-21
**Author:** FSI C4E

## Context

Kafka topic names are permanent once created (renaming requires creating a new topic and migrating consumers). A consistent naming convention is essential for:

- **Discovery:** Teams can find topics by domain or application without a catalog
- **RBAC:** Role bindings can use wildcard patterns on topic prefixes (e.g., `corebanking.*`)
- **Observability:** Dashboard auto-discovery groups topics by domain prefix
- **Schema Registry:** Subject naming strategy (TopicNameStrategy) derives subject names from topic names
- **Governance:** Topic ownership, SLA tier, and data classification are encoded or derivable from the name

The convention must work across all deployment models (CC, CFK, CP) and all cloud providers.

## Decision

**Topic names follow the pattern: `{domain}.{application}.{version}.{entity}`**

### Segment Rules

| Segment | Regex | Example | Purpose |
|---------|-------|---------|---------|
| domain | `^[a-z][a-z0-9-]{1,30}$` | `corebanking` | Business domain ownership |
| application | `^[a-z][a-z0-9-]{1,30}$` | `transactions` | Application within domain |
| version | `^v[0-9]+$` | `v1` | Schema version (enables breaking change migration) |
| entity | `^[a-z][a-z0-9-]{1,60}$` | `account-transaction` | The data entity carried |

### Why Dots as Separators

- Dots (`.`) are the standard hierarchical separator in Kafka (used by Confluent for internal topics, metrics, consumer group IDs)
- Dots enable prefix-based RBAC: `DeveloperRead` on `corebanking.*` grants read to all corebanking topics
- Dots are visually distinct from hyphens within segments (e.g., `corebanking.transactions.v1.account-transaction` is unambiguous)
- Underscores (`_`) and dots are interchangeable in Kafka metric names, which can cause collisions. Using dots consistently avoids the `metrics_period_problem` where `a.b` and `a_b` map to the same metric.

### Why Version in Topic Name

- Schema compatibility modes (FULL_TRANSITIVE, BACKWARD_TRANSITIVE) prevent incompatible changes to existing topics
- When a breaking change is necessary, a new versioned topic (`v2`) is created alongside `v1`
- Both versions coexist during migration (see Breaking Change Runbook in schema-guide.md)
- The version segment makes dual-version operation explicit and discoverable

### Avro Namespace Convention

Avro schema namespaces follow: `org.fsi.{domain}.{application}.{version}`

The entity is NOT part of the namespace -- it is the Avro record name (e.g., `AccountTransaction`). This matches Java package conventions and allows multiple entity types within the same domain/application/version namespace.

### Examples

| Topic Name | Domain | Application | Version | Entity |
|------------|--------|-------------|---------|--------|
| `corebanking.transactions.v1.account-transaction` | corebanking | transactions | v1 | account-transaction |
| `fraud.detection.v1.alert-signal` | fraud | detection | v1 | alert-signal |
| `compliance.screening.v1.match-result` | compliance | screening | v1 | match-result |
| `corebanking.transactions.v2.account-transaction` | corebanking | transactions | v2 | account-transaction |

## Consequences

**Easier:**
- Topic discovery by domain prefix (`corebanking.*`)
- RBAC wildcard bindings per domain
- Dashboard auto-discovery by domain prefix pattern
- Breaking change migration via versioned topics
- Naming validation enforceable in Terraform module and CI

**Harder:**
- Long topic names (max ~61 chars in practice, well within Kafka 255 limit)
- Renaming a domain requires creating new topics (but this is rare and intentional)
- Teams must agree on domain boundaries upfront
- Version segment adds complexity for teams that never do breaking changes (but it costs nothing to include)

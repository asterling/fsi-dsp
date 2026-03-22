# FSI Kafka Platform

## What This Is

A universal, automation-first platform for standing up governed Kafka, Flink, and Schema Registry infrastructure across any deployment model — Confluent Cloud (AWS, Azure, GCP), Confluent Private Cloud, Confluent for Kubernetes on OpenShift, and Confluent Platform on RHEL. It packages FSI-specific C4E assets (Terraform modules, reference implementations, observability templates, DR automation, schema governance) into scenario-based starter kits that any financial institution can adopt in hours, not months.

## Core Value

Any FSI team can stand up a fully governed, observable, DR-ready Kafka/Flink/SR cluster in their deployment model of choice with a single automation run — and onboard their first topic in under a day.

## Requirements

### Validated

<!-- Shipped and confirmed valuable — inferred from existing codebase. -->

- ✓ Topic creation Terraform module with naming validation — existing (`modules/topic/`)
- ✓ Schema registration with Avro and compatibility mode enforcement — existing (`modules/topic/main.tf`)
- ✓ RBAC provisioning per service account — existing (`modules/topic/main.tf`)
- ✓ SLA-tier-based defaults (critical/standard/best-effort) — existing (`modules/topic/main.tf`)
- ✓ DR mirror topic creation via Cluster Linking — existing (`modules/topic/main.tf`)
- ✓ Schema metadata tags (owner, sla-tier, PII) — existing (`modules/topic/variables.tf`)
- ✓ Java producer reference (idempotent, Avro, JMX metrics) — existing (`reference/java-producer/`)
- ✓ Java consumer reference (offset management, Avro, JMX) — existing (`reference/java-consumer/`)
- ✓ .NET producer/consumer reference — existing (`reference/dotnet-producer/`, `reference/dotnet-consumer/`)
- ✓ Connect JDBC source/sink configs with Consul resolution — existing (`reference/connect-configs/`)
- ✓ DR failover/failback scripts — existing (`scripts/`)
- ✓ Consul service discovery for endpoint failover — existing (ADR-003)
- ✓ Architecture Decision Records (5 ADRs) — existing (`docs/adr/`)
- ✓ Schema governance guide — existing (`docs/schema-guide.md`)
- ✓ Self-service onboarding flow — existing (`docs/onboarding.md`)
- ✓ CI/CD pipeline (plan on PR, apply on merge) — existing (`.github/workflows/`)
- ✓ Local dev Docker Compose (Kafka + SR + Connect) — existing (`reference/local-dev/`)
- ✓ Integration test roundtrip — existing (`reference/integration-test/`)

### Active

<!-- Current scope. Building toward these. -->

**Multi-Deployment Scenarios:**
- [x] Confluent Cloud on AWS scenario directory with Terraform modules — Validated in Phase 2
- [x] Confluent Cloud on Azure scenario directory with Terraform modules — Validated in Phase 2
- [x] Confluent Cloud on GCP scenario directory with Terraform modules — Validated in Phase 2
- [ ] Confluent for Kubernetes (CFK) on OpenShift scenario with Helm/operator manifests
- [ ] Confluent Platform on RHEL scenario with Ansible/systemd deployment
- [ ] Confluent Private Cloud scenario directory
- [x] Shared module library consumed by all scenarios (topic, schema, RBAC, observability) — Validated in Phase 1

**Flink Runtime:**
- [ ] Flink cluster deployment per scenario (CC Flink, CFK Flink, standalone Flink)
- [ ] Flink SQL reference job templates (windowing, enrichment, filtering)
- [ ] Flink integration with Schema Registry (Avro serde)
- [ ] Flink observability integration (metrics export per provider)

**DR Framework:**
- [ ] Pluggable DR abstraction — unified failover CLI with backend adapters
- [ ] CC backend: Cluster Linking with automated failover/failback
- [ ] CFK/CP backend: MirrorMaker 2 with automated failover/failback
- [ ] MRC with automatic observer promotion (2.5-cluster pattern) for RPO=0
- [ ] Orchestrated failover script replacing 6 manual steps with single command
- [ ] Dry-run mode for all DR operations
- [ ] State validation between failover steps
- [ ] Rollback capability for partial failover
- [ ] Mirror lag monitoring with per-topic alerting

**Observability (Per-Provider Templates):**
- [ ] Dynatrace dashboard templates (cluster health, app view, Connect, DR readiness)
- [ ] Datadog dashboard templates
- [ ] Splunk dashboard templates
- [ ] New Relic dashboard templates
- [ ] IBM Instana dashboard templates
- [ ] Prometheus/Grafana dashboard templates
- [ ] Auto-discovery rules (new topics appear by domain prefix)
- [ ] Alert threshold configuration per SLA tier

**Concerns Remediation (from CONCERNS.md):**
- [x] Externalize hardcoded cluster IDs into centralized config — Validated in Phase 1
- [x] Post-apply Terraform validation (topic exists, schema registered, RBAC applied) — Validated in Phase 2
- [ ] Credential rotation automation with zero-downtime support
- [x] Schema evolution enforcement in CI (block dangerous compatibility overrides) — Validated in Phase 1
- [ ] DLQ pattern in reference producer with retry and alerting
- [ ] Connect state tracking for pause/resume coordination
- [x] Compliance-tier retention (configurable up to 7-year) — Validated in Phase 1
- [ ] Error-path integration tests (serialization failure, RBAC denial, broker failure)
- [ ] Unified DR runbook with decision trees and rollback guidance
- [x] Schema namespace collision prevention in CI — Validated in Phase 1
- [ ] Kafka topic health metrics export per deployment model

**Governance & Onboarding:**
- [ ] Generic FSI intake form template (no client-specific names)
- [ ] C4E review automation (lint + validate in CI, human review as gate)
- [x] Additional ADRs: OAuth vs API keys, topic naming rationale, DR tier classification — Validated in Phase 1

### Out of Scope

<!-- Explicit boundaries. -->

- Flink business logic (fraud scoring, compliance windowing) — runtime only, teams build their own jobs
- Mobile or web UI — CLI and IaC only
- Confluent Cloud account/org provisioning — assumes org and environment exist
- Client-specific customizations — generic FSI patterns only, teams extend
- Real-time chat/collaboration features — use existing Teams/Slack
- Data mesh or catalog integration — future milestone

## Context

This platform generalizes a proven NFCU-specific C4E engagement into reusable FSI starter assets. The existing codebase covers Confluent Cloud on Azure with a single topic module, reference implementations, and manual DR scripts. The gap is: no multi-cloud/multi-deployment support, no Flink, no observability beyond Dynatrace stubs, manual DR, and 14 documented technical concerns.

The C4E philosophy (from the engagement): **Automation > Documentation. Golden Path > Gatekeeping. Community > Committee.** Every asset should make it easier to do the right thing than the wrong thing.

**Deployment models to support:**
1. **Confluent Cloud** — fully managed on AWS, Azure, or GCP
2. **Confluent Private Cloud** — Confluent-managed in customer VPC
3. **Confluent for Kubernetes (CFK)** — operator-based on OpenShift
4. **Confluent Platform on RHEL** — traditional systemd/Ansible deployment

**Key architectural decisions:**
- Scenario directories over CLI scaffolding — teams pick their path
- Per-provider observability templates over abstraction layer
- DR framework with pluggable backends (Cluster Linking, MM2, MRC)
- MRC with 2.5-cluster observer promotion for RPO=0 scenarios

**Existing codebase map:** `.planning/codebase/` (7 documents, mapped 2026-03-21)

## Constraints

- **Deployment parity**: Core governance (topic naming, schema compat, RBAC) must work identically across all deployment models
- **No vendor lock-in on observability**: Templates per provider, no single-provider dependency
- **FSI compliance**: Retention policies must support regulatory requirements (up to 7-year for OFAC/AML)
- **Backward compatibility**: Existing Confluent Cloud Terraform modules must continue to work — extend, don't break
- **OpenShift compatibility**: CFK scenario must target OCP 4.x with operator lifecycle management

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Scenario directories over CLI | Lower barrier to entry, teams browse and pick | ✓ Good — Phase 2 delivered 3 scenarios |
| Per-provider observability templates | Simpler to maintain, each FSI has one provider | — Pending |
| Flink runtime only (no business logic) | Teams own their jobs, we provide the platform | — Pending |
| DR framework with pluggable backends | Same CLI/UX regardless of deployment model | — Pending |
| MRC 2.5-cluster for RPO=0 | FSI compliance may require zero data loss | — Pending |
| Avro over Protobuf (existing ADR-001) | FSI ecosystem alignment, SR compatibility | ✓ Good |
| Consul for service discovery (existing ADR-003) | Atomic failover across Kafka/SR/DB | ✓ Good |
| Cluster Linking over MRC for CC (existing ADR-005) | CC-native, meets ~2h RPO target | ✓ Good |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd:transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd:complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-03-22 after Phase 2 completion — CC multi-cloud scenarios (Azure, AWS, GCP) with validation and CI*

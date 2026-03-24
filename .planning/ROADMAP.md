# Roadmap: FSI Kafka Platform

## Overview

This roadmap transforms a proven single-cloud Confluent Cloud C4E engagement into a universal, multi-deployment FSI Kafka/Flink/SR platform. The journey starts with governance primitives and shared modules (the architectural linchpin that prevents governance drift), extends to CC multi-cloud scenarios, layers on access control, compliance, DR automation, observability, and Flink, then adds on-prem deployment models (CFK on OpenShift, CP on RHEL). Nine phases, each delivering a coherent, verifiable capability.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Shared Governance Foundation** - Shared module library, schema CI validation, externalized config, and architectural decision records
- [ ] **Phase 2: CC Multi-Cloud Scenarios** - Self-contained CC scenario directories for AWS and GCP with parameterized backends and post-apply validation
- [ ] **Phase 3: Access Control and Compliance** - Cross-deployment RBAC parity, OAuth authentication, credential rotation, compliance retention tiers, and audit trails
- [ ] **Phase 4: DR Automation Framework** - Pluggable DR CLI with Cluster Linking adapter, orchestrated failover/failback, dry-run, rollback, and mirror lag monitoring
- [ ] **Phase 5: Observability Templates** - Per-provider dashboard templates (6 providers), SLA-tier alerting, auto-discovery, and metrics export per deployment model
- [ ] **Phase 6: Flink on Confluent Cloud** - CC Flink compute pool deployment, SQL reference templates, SR integration, observability, and dead letter handling
- [ ] **Phase 7: Onboarding and Developer Experience** - Intake form, C4E review automation, Python reference client, error-path tests, local dev with Flink, and DLQ patterns
- [ ] **Phase 8: CFK on OpenShift** - Confluent for Kubernetes operator manifests, MM2 DR adapter, and Flink Kubernetes Operator deployment
- [ ] **Phase 9: CP on RHEL and Private Cloud** - Ansible/systemd deployment, Private Cloud scenario, MRC RPO=0, standalone Flink, and FIPS 140-2 compliance

## Phase Details

### Phase 1: Shared Governance Foundation
**Goal**: Governance primitives (topic naming, schema compatibility, RBAC patterns, SLA-tier defaults) are codified in a shared module library and enforced by CI -- before any new scenario directory is created
**Depends on**: Nothing (first phase)
**Requirements**: IAC-07, IAC-09, SCHEMA-01, SCHEMA-02, SCHEMA-03, SCHEMA-04, GOV-01, GOV-02, GOV-03
**Success Criteria** (what must be TRUE):
  1. Operator can import shared topic module from any scenario directory and get identical naming validation, schema compatibility, RBAC bindings, and SLA-tier defaults
  2. CI pipeline rejects a PR that introduces a schema incompatibility, namespace collision, or undocumented compatibility override
  3. Cluster IDs, REST endpoints, and CRNs are loaded from a centralized config file -- no hardcoded values remain in Terraform locals
  4. ADRs exist for OAuth vs API keys, topic naming rationale, and DR tier classification -- each with deployment-model-specific guidance
  5. Breaking change runbook in schema-guide.md provides step-by-step multi-topic migration instructions
**Plans**: 3 plans

Plans:
- [x] 01-01-PLAN.md -- Extend topic module with compliance SLA tier and externalize cluster config
- [x] 01-02-PLAN.md -- Schema CI validation pipeline, override detection, and breaking change runbook
- [x] 01-03-PLAN.md -- ADRs for OAuth vs API keys, topic naming, and DR tier classification

### Phase 2: CC Multi-Cloud Scenarios
**Goal**: Operators can deploy a fully governed Kafka environment on CC-AWS or CC-GCP using a self-contained scenario directory -- identical governance to existing CC-Azure
**Depends on**: Phase 1
**Requirements**: IAC-01, IAC-02, IAC-06, IAC-08, IAC-10
**Success Criteria** (what must be TRUE):
  1. Operator can run `terraform apply` in `scenarios/cc-aws/` and get a working Kafka cluster with topic, schema, RBAC, and DR mirror -- without modifying any module code
  2. Operator can run `terraform apply` in `scenarios/cc-gcp/` with the same outcome as CC-AWS
  3. Each scenario directory contains README, Terraform files, variable examples, and quickstart instructions sufficient for first-time use
  4. Terraform state backend is parameterized per provider (S3 for AWS, GCS for GCP, Azure Blob for Azure) with no hardcoded backend config
  5. Post-apply validation confirms topic exists, schema registered, RBAC applied, and mirror created -- failing validation produces actionable error messages
**Plans**: 2 plans

Plans:
- [x] 02-01-PLAN.md -- Create CC scenario directories for Azure (migrated), AWS, and GCP with native backends and quickstart READMEs
- [x] 02-02-PLAN.md -- Post-apply validation script and CI pipeline refactor with reusable workflow

### Phase 3: Access Control and Compliance
**Goal**: FSI teams get production-grade access control and compliance enforcement that works identically across CC deployment models and lays the RBAC pattern for future CFK/CP scenarios
**Depends on**: Phase 2
**Requirements**: RBAC-01, RBAC-02, RBAC-03, RBAC-04, COMP-01, COMP-02, COMP-04
**Success Criteria** (what must be TRUE):
  1. Service accounts are provisioned automatically alongside topic creation in CC scenarios -- no manual SA creation required
  2. RBAC binding patterns produce identical effective permissions across CC-AWS, CC-Azure, and CC-GCP scenarios
  3. OAuth/OAUTHBEARER authentication is configured and documented for CC deployments (Azure AD for Azure, AWS IAM for AWS)
  4. Credential rotation via Vault integration supports zero-downtime dual-credential window -- old and new credentials work simultaneously during rotation
  5. Compliance SLA tier with configurable retention up to 7 years is available for OFAC/AML/CFT topics
**Plans**: 4 plans

Plans:
- [x] 03-01-PLAN.md -- SA provisioning with create-or-reference pattern and RBAC binding refactor
- [x] 03-02-PLAN.md -- Per-scenario OAuth identity providers, Vault reference patterns, and credential rotation docs
- [x] 03-03-PLAN.md -- CSFLE encryption enforcement for confidential topics and configurable compliance retention
- [x] 03-04-PLAN.md -- CI audit trail with job summaries, PR template compliance checkboxes, and compliance guide

### Phase 4: DR Automation Framework
**Goal**: A single `fsi-dr failover` command replaces 6+ manual steps, with dry-run preview, state validation between steps, rollback on failure, and mirror lag monitoring
**Depends on**: Phase 2
**Requirements**: DR-01, DR-02, DR-03, DR-04, DR-07, DR-08, DR-09, DR-10, DR-11, DR-12
**Success Criteria** (what must be TRUE):
  1. Operator runs `fsi-dr failover` and the system pauses connectors, promotes mirrors, flips Consul, validates, resumes, and verifies -- all automatically
  2. Operator runs `fsi-dr failback` and the system re-establishes reverse replication, mirrors, and cuts over to primary -- all automatically
  3. Operator runs `fsi-dr failover --dry-run` and gets a complete preview of every step without any state change
  4. If a failover step fails, the system halts, reports which step failed, and offers rollback to safe state
  5. Mirror lag is monitored per-topic with SLA-tier-based alert thresholds -- critical topics alert at tighter lag than standard topics
**Plans**: TBD

Plans:
- [ ] 04-01: TBD
- [ ] 04-02: TBD
- [ ] 04-03: TBD

### Phase 5: Observability Templates
**Goal**: FSI teams import pre-built dashboard templates for their observability provider and get cluster health, consumer lag, Connect status, DR readiness, and Flink job visibility without building dashboards from scratch
**Depends on**: Phase 4
**Requirements**: OBS-01, OBS-02, OBS-03, OBS-04, OBS-05, OBS-06, OBS-07, OBS-08, OBS-09, OBS-10
**Success Criteria** (what must be TRUE):
  1. Dashboard templates exist for all six providers (Dynatrace, Prometheus/Grafana, Datadog, Splunk, New Relic, IBM Instana) covering cluster health, consumer lag, Connect status, DR readiness, and Flink job health
  2. Alert thresholds vary by SLA tier -- critical topics have tighter thresholds than standard or best-effort topics
  3. New topics appear automatically in dashboards by domain prefix pattern without manual dashboard configuration
  4. Metrics export is configured per deployment model (CC Metrics API for cloud, JMX exporter for CFK/CP)
  5. Connect connector status monitoring alerts on FAILED task state across all deployment models
**Plans**: TBD

Plans:
- [ ] 05-01: TBD
- [ ] 05-02: TBD
- [ ] 05-03: TBD

### Phase 6: Flink on Confluent Cloud
**Goal**: FSI teams can deploy a CC Flink compute pool via Terraform and use reference SQL templates for common stream processing patterns -- with SR integration and observability
**Depends on**: Phase 2, Phase 5
**Requirements**: FLINK-01, FLINK-04, FLINK-05, FLINK-06, FLINK-07
**Success Criteria** (what must be TRUE):
  1. Operator can provision a CC Flink compute pool and submit Flink SQL statements via Terraform
  2. Reference SQL templates exist for tumbling window aggregation, stream-table join enrichment, and filter-and-route patterns
  3. Flink auto-discovers Schema Registry subjects for Avro serde in CC deployments
  4. Flink job metrics (checkpoint duration, backpressure, throughput) appear in observability provider dashboards
  5. Deserialization and processing failures route to `{topic}.dlq` topics via Flink side output pattern
**Plans**: TBD

Plans:
- [ ] 06-01: TBD
- [ ] 06-02: TBD

### Phase 7: Onboarding and Developer Experience
**Goal**: New FSI teams can go from intake form to first message produced in under a day -- with Python reference clients, error-path tests, local dev with Flink, and DLQ patterns across all languages
**Depends on**: Phase 6
**Requirements**: ONBOARD-01, ONBOARD-02, ONBOARD-03, ONBOARD-04, ONBOARD-05, ONBOARD-06
**Success Criteria** (what must be TRUE):
  1. Generic FSI intake form template includes deployment model selection and contains no client-specific references
  2. C4E review automation in CI validates naming, schema compat, RBAC completeness, and SLA tier -- human review is the final gate, not the first check
  3. Python reference producer/consumer works alongside existing Java and .NET examples with identical patterns (idempotent, Avro, metrics)
  4. Integration test suite covers error paths: serialization failure, RBAC denial, schema incompatibility, and broker failure
  5. Local dev Docker Compose includes Flink alongside Kafka, SR, and Connect for stream processing development
**Plans**: TBD

Plans:
- [ ] 07-01: TBD
- [ ] 07-02: TBD
- [ ] 07-03: TBD

### Phase 8: CFK on OpenShift
**Goal**: Operators can deploy a fully governed Kafka environment on OpenShift using CFK operator manifests -- with identical governance to CC scenarios, MM2 DR, and Flink Kubernetes Operator
**Depends on**: Phase 1, Phase 4, Phase 6
**Requirements**: IAC-03, DR-05, FLINK-02
**Success Criteria** (what must be TRUE):
  1. Operator can deploy KafkaCluster, SchemaRegistry, Connect, and KafkaTopic CRDs on OpenShift via CFK operator with governance parity to CC scenarios
  2. MirrorMaker 2 adapter handles CFK failover/failback with topic replication using the same `fsi-dr` CLI interface as Cluster Linking
  3. Flink Kubernetes Operator is deployed via Helm chart on OpenShift with Flink SR integration and job metrics export
**Plans**: TBD

Plans:
- [ ] 08-01: TBD
- [ ] 08-02: TBD

### Phase 9: CP on RHEL and Private Cloud
**Goal**: Operators can deploy Kafka on bare-metal RHEL via Ansible and on Confluent Private Cloud via Terraform -- with FIPS compliance, MRC RPO=0, and standalone Flink
**Depends on**: Phase 1, Phase 4, Phase 6
**Requirements**: IAC-04, IAC-05, DR-06, FLINK-03, COMP-03
**Success Criteria** (what must be TRUE):
  1. Operator can deploy Kafka, SR, Connect, and MDS RBAC on RHEL via Ansible roles with systemd service management
  2. Confluent Private Cloud scenario directory deploys via Terraform with shared module governance
  3. MRC with automatic observer promotion (2.5-cluster pattern) provides RPO=0 for critical CP workloads
  4. Standalone Flink is deployed via Ansible roles with systemd and integrates with SR for Avro serde
  5. FIPS 140-2 compliance is automated for CP on RHEL (FIPS-validated JVM, TLS libraries) and CFK on FIPS-enabled OpenShift
**Plans**: TBD

Plans:
- [ ] 09-01: TBD
- [ ] 09-02: TBD
- [ ] 09-03: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4 -> 5 -> 6 -> 7 -> 8 -> 9
Note: Phases 4 and 5 can begin after Phase 2. Phase 8 and 9 depend on Phases 1, 4, and 6.

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Shared Governance Foundation | 3/3 | Complete | 2026-03-22 |
| 2. CC Multi-Cloud Scenarios | 0/2 | Planned | - |
| 3. Access Control and Compliance | 0/4 | Planned | - |
| 4. DR Automation Framework | 0/3 | Not started | - |
| 5. Observability Templates | 0/3 | Not started | - |
| 6. Flink on Confluent Cloud | 0/2 | Not started | - |
| 7. Onboarding and Developer Experience | 0/3 | Not started | - |
| 8. CFK on OpenShift | 0/2 | Not started | - |
| 9. CP on RHEL and Private Cloud | 0/3 | Not started | - |

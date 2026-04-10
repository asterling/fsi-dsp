# Roadmap: FSI Kafka Platform

## Milestones

- **v1.0 Terraform + Shell Foundation** - Phases 1-9 (complete)
- **v2.0 Ansible Based Automation** - Phases 10-15 (in progress)

## Overview

This roadmap transforms a proven single-cloud Confluent Cloud C4E engagement into a universal, multi-deployment FSI Kafka/Flink/SR platform. The journey starts with governance primitives and shared modules (the architectural linchpin that prevents governance drift), extends to CC multi-cloud scenarios, layers on access control, compliance, DR automation, observability, and Flink, then adds on-prem deployment models (CFK on OpenShift, CP on RHEL). v2.0 adds Ansible-native automation for Confluent Platform deployments -- topic governance, schema management, RBAC, observability, and DR -- in an `ansible/` directory alongside existing Terraform content.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

<details>
<summary>v1.0 Terraform + Shell Foundation (Phases 1-9) - COMPLETE</summary>

- [x] **Phase 1: Shared Governance Foundation** - Shared module library, schema CI validation, externalized config, and architectural decision records
- [x] **Phase 2: CC Multi-Cloud Scenarios** - Self-contained CC scenario directories for AWS and GCP with parameterized backends and post-apply validation
- [x] **Phase 3: Access Control and Compliance** - Cross-deployment RBAC parity, OAuth authentication, credential rotation, compliance retention tiers, and audit trails
- [x] **Phase 4: DR Automation Framework** - Pluggable DR CLI with Cluster Linking adapter, orchestrated failover/failback, dry-run, rollback, and mirror lag monitoring
- [x] **Phase 5: Observability Templates** - Per-provider dashboard templates (6 providers), SLA-tier alerting, auto-discovery, and metrics export per deployment model
- [x] **Phase 6: Flink on Confluent Cloud** - CC Flink compute pool deployment, SQL reference templates, SR integration, observability, and dead letter handling
- [x] **Phase 7: Onboarding and Developer Experience** - Intake form, C4E review automation, Python reference client, error-path tests, local dev with Flink, and DLQ patterns
- [x] **Phase 8: CFK on OpenShift** - Confluent for Kubernetes operator manifests, MM2 DR adapter, and Flink Kubernetes Operator deployment
- [x] **Phase 9: CP on RHEL and Private Cloud** - Ansible/systemd deployment, Private Cloud scenario, MRC RPO=0, standalone Flink, and FIPS 140-2 compliance

</details>

### v2.0 Ansible Based Automation (Phases 10-15)

- [ ] **Phase 10: Ansible Foundation and Governance Scaffolding** - Directory structure, version pinning, shared governance constants, filter plugins, and ansible-lint config
- [ ] **Phase 11: Core Governance Roles** - Topic lifecycle, schema registration, and RBAC provisioning roles with molecule tests
- [ ] **Phase 12: Orchestration Pipeline, Observability, and CI/CD** - End-to-end deployment playbook, connector and observability roles, and GitHub Actions for Ansible content
- [ ] **Phase 13: DR Automation Playbooks (MM2)** - MM2 failover/failback playbooks with dry-run, state validation, and audit-ready output
- [ ] **Phase 14: CFK on OpenShift Governance** - CFK operator and CR deployment via kubernetes.core with governance parity to CP roles
- [ ] **Phase 15: MRC Failover and DR Drill** - MRC observer promotion playbook and quarterly DR drill automation with compliance reporting

## Phase Details

<details>
<summary>v1.0 Phase Details (Phases 1-9) - COMPLETE</summary>

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
**Plans**: 3 plans

Plans:
- [x] 04-01-PLAN.md -- Core CLI framework with backend dispatch, state management, SLA tier thresholds, and unit tests
- [x] 04-02-PLAN.md -- Failover orchestration with 6-step sequence, dry-run mode, and rollback guidance
- [x] 04-03-PLAN.md -- Failback orchestration with reverse sequence and standalone DR runbook

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
**Plans**: 3 plans

Plans:
- [x] 05-01-PLAN.md -- Cross-provider metrics mapping and Grafana/Prometheus dashboard templates (reference implementation)
- [x] 05-02-PLAN.md -- Dynatrace, Datadog, and Splunk dashboard templates with alerts and metrics export
- [x] 05-03-PLAN.md -- New Relic and IBM Instana templates with .env.example updates

### Phase 6: Flink on Confluent Cloud
**Goal**: FSI teams can deploy a CC Flink compute pool via Terraform and use reference SQL templates for common stream processing patterns -- with SR integration and observability
**Depends on**: Phase 2, Phase 5
**Requirements**: FLINK-01, FLINK-04, FLINK-05, FLINK-06, FLINK-07
**Success Criteria** (what must be TRUE):
  1. Operator can provision a CC Flink compute pool and submit Flink SQL statements via Terraform
  2. Reference SQL templates exist for tumbling window aggregation, stream-table join enrichment, and filter-and-route patterns
  3. Flink auto-discovers Schema Registry subjects for Avro serde in CC deployments
  4. Flink job metrics (pending records for backpressure, records throughput) appear in observability provider dashboards
  5. Deserialization failures route to `{topic}.dlq` topics via CC Flink error-handling.mode table properties
**Plans**: 3 plans

Plans:
- [x] 06-01-PLAN.md -- Flink Terraform module (compute pool + SQL statements) and CC scenario wiring
- [x] 06-02-PLAN.md -- Flink SQL reference templates (tumbling window, stream-table join, filter-route, DLQ)
- [x] 06-03-PLAN.md -- Observability dashboard wiring (6 providers) with real CC Flink metrics and .env.example

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
**Plans**: 3 plans

Plans:
- [x] 07-01-PLAN.md -- Intake form YAML conversion and C4E pre-check automation suite
- [x] 07-02-PLAN.md -- Python reference producer/consumer and DLQ pattern across all three languages
- [x] 07-03-PLAN.md -- Error-path integration tests and local dev Docker Compose with Flink

### Phase 8: CFK on OpenShift
**Goal**: Operators can deploy a fully governed Kafka environment on OpenShift using CFK operator manifests -- with identical governance to CC scenarios, MM2 DR, and Flink Kubernetes Operator
**Depends on**: Phase 1, Phase 4, Phase 6
**Requirements**: IAC-03, DR-05, FLINK-02
**Success Criteria** (what must be TRUE):
  1. Operator can deploy KafkaCluster, SchemaRegistry, Connect, and KafkaTopic CRDs on OpenShift via CFK operator with governance parity to CC scenarios
  2. MirrorMaker 2 adapter handles CFK failover/failback with topic replication using the same `fsi-dr` CLI interface as Cluster Linking
  3. Flink Kubernetes Operator is deployed via Helm chart on OpenShift with Flink SR integration and job metrics export
**Plans**: 3 plans

Plans:
- [x] 08-01-PLAN.md -- CFK scenario directory with Helm values, topic CRDs, ACLs, MM2 connectors, and CI validation extension
- [x] 08-02-PLAN.md -- MM2 backend for fsi-dr.sh (5 functions), unit tests, and DR runbook extension
- [x] 08-03-PLAN.md -- Flink Kubernetes Operator deployment, FlinkDeployment examples, JMX observability, and .env.example

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
**Plans**: 4 plans

Plans:
- [x] 09-01-PLAN.md -- CP-RHEL Ansible scenario directory with inventory, playbook, and CPTopic definitions
- [x] 09-02-PLAN.md -- Private Cloud Terraform scenario and C4E precheck extension for CPTopic format
- [x] 09-03-PLAN.md -- MRC backend for fsi-dr.sh (5 functions), unit tests, and DR runbook extension
- [x] 09-04-PLAN.md -- Standalone Flink Ansible role, FIPS 140-2 validation, and .env.example extension

</details>

### Phase 10: Ansible Foundation and Governance Scaffolding
**Goal**: The `ansible/` directory is fully scaffolded with pinned dependencies, shared governance constants that mirror Terraform, filter plugins, multi-environment inventories, and lint rules -- establishing the foundation every subsequent role depends on
**Depends on**: Phase 9 (v1.0 complete -- existing CP-RHEL scenario and governance artifacts exist)
**Requirements**: AFOUND-01, AFOUND-02, AFOUND-03, AFOUND-04, AFOUND-05
**Success Criteria** (what must be TRUE):
  1. Running `ansible-galaxy collection install -r ansible/requirements.yml` installs cp-ansible 7.7.x and all required collections with pinned versions
  2. SLA-tier lookups in `ansible/vars/sla_tiers.yml` produce identical partition counts, retention values, and compatibility modes as Terraform module locals
  3. Topic name assembly using the `fsi_governance` filter plugin produces names matching the Terraform `{domain}.{application}.{version}.{entity}` regex
  4. `ansible-lint` with the project config passes on the scaffolded directory with zero violations
  5. Inventory skeletons exist for dev, staging, prod, and dr environments with documented host group patterns
**Plans**: 2 plans

Plans:
- [x] 10-01-PLAN.md -- Directory scaffolding, requirements.yml, ansible.cfg, inventories, and ansible-lint config
- [x] 10-02-PLAN.md -- Shared governance constants (sla_tiers.yml, naming_rules.yml), filter plugin, and parity tests

### Phase 11: Core Governance Roles
**Goal**: Operators can create topics, register schemas, and provision RBAC bindings on a Confluent Platform cluster using Ansible roles -- with identical governance rules to Terraform and full idempotency
**Depends on**: Phase 10
**Requirements**: ATOPIC-01, ATOPIC-02, ATOPIC-03, ATOPIC-04, ATOPIC-05, ATOPIC-06, ATOPIC-07, ASCHEMA-01, ASCHEMA-02, ASCHEMA-03, ASCHEMA-04, ASCHEMA-05, ARBAC-01, ARBAC-02, ARBAC-03, ARBAC-04, ARBAC-05
**Success Criteria** (what must be TRUE):
  1. Operator runs the topic role against a CP cluster and topics are created with SLA-tier-derived config (partitions, retention, min.insync.replicas) -- re-running the same playbook produces no changes
  2. Operator runs the schema role and Avro schemas are registered with compatibility pre-checked before any registration -- incompatible schemas fail with a clear message before any mutation
  3. Operator runs the RBAC role and MDS bindings (DeveloperWrite, DeveloperRead, consumer group, SR subject) are created for each principal -- stale bindings from removed principals are cleaned up
  4. All three roles support `--check` mode, showing what would change without making mutations
  5. Molecule tests for each role pass with idempotency verification (second run reports zero changes)
**Plans**: 3 plans

Plans:
- [x] 11-01-PLAN.md -- cp_topic role: Admin REST v3 CRUD, SLA-tier defaults, CPTopic YAML consumption, check mode, unit tests
- [x] 11-02-PLAN.md -- cp_schema role: SR REST API, two-pass validate-then-register, compatibility modes, PII metadata, unit tests
- [x] 11-03-PLAN.md -- cp_rbac role: MDS REST API, token refresh, LIST/DIFF/ADD/REMOVE reconciliation, unit tests

### Phase 12: Orchestration Pipeline, Observability, and CI/CD
**Goal**: Governance roles are composed into an end-to-end deployment pipeline with connector management, observability deployment, tag-based selective execution, and CI quality gates for all Ansible content
**Depends on**: Phase 11
**Requirements**: APIPE-01, APIPE-02, APIPE-03, APIPE-04, AOBS-01, AOBS-02, AOBS-03, AOBS-04, ACI-01, ACI-02, ACI-03
**Success Criteria** (what must be TRUE):
  1. Operator runs `ansible-playbook site.yml` and it chains cp-ansible cluster deployment with topic creation, schema registration, RBAC provisioning, connector deployment, and observability setup in a single run
  2. Operator runs `ansible-playbook site.yml --tags topics` and only topic-related tasks execute -- same for `--tags rbac`, `--tags observability`, and other tags
  3. After connector deployment, all connectors and tasks are verified in RUNNING state -- failures trigger retry with backoff and report which connectors failed
  4. Prometheus scrape config is auto-generated from inventory host groups and updates when nodes are added without manual config editing
  5. GitHub Actions CI runs ansible-lint, yamllint, and molecule tests on every PR touching `ansible/` -- failing lint or tests blocks merge
**Plans**: 3 plans

Plans:
- [x] 12-01-PLAN.md -- Orchestration playbooks (site.yml, deploy-governance.yml) with tag-based execution and cp_connect role
- [x] 12-02-PLAN.md -- cp_observability role: JMX exporter configs, Prometheus scrape generation, Grafana dashboard import, SLA-tier alerts
- [x] 12-03-PLAN.md -- GitHub Actions CI workflow (ansible-lint, yamllint, molecule matrix, governance parity validation)

### Phase 13: DR Automation Playbooks (MM2)
**Goal**: Operators can execute MM2 failover and failback operations via Ansible playbooks with dry-run mode, state validation, and audit-ready output -- replacing manual shell script execution
**Depends on**: Phase 11
**Requirements**: ADR-01, ADR-02, ADR-03, ADR-04
**Success Criteria** (what must be TRUE):
  1. Operator runs the failover playbook and connectors are paused, source MM2 stopped, topics promoted, Consul updated, state validated, and connectors resumed on the target cluster -- all in sequence with validation between steps
  2. Operator runs the failback playbook and replication direction is reversed, mirrors re-established, data sync validated, and traffic cut back to primary
  3. Running either playbook with `--check` generates audit-ready output showing every step without executing any mutations
  4. DR state validation checks mirror lag against SLA-tier thresholds, cluster health, and topic writability before and after failover -- failing validation halts the playbook with clear diagnostics
**Plans**: 2 plans

Plans:
- [x] 13-01-PLAN.md -- cp_dr_mm2 role with failover tasks, state validation, Consul integration, check mode audit, and unit tests
- [x] 13-02-PLAN.md -- cp_dr_mm2 failback tasks, reverse replication, audit report extension, and failback playbook

### Phase 14: CFK on OpenShift Governance
**Goal**: Operators can deploy the CFK operator and apply governed Kafka custom resources on OpenShift using Ansible -- with the same SLA-tier defaults and governance rules as CP REST API roles
**Depends on**: Phase 10
**Requirements**: ACFK-01, ACFK-02, ACFK-03
**Success Criteria** (what must be TRUE):
  1. Operator runs the CFK playbook and the CFK operator is deployed on OpenShift via Helm with configurable chart version and namespace
  2. KafkaCluster, SchemaRegistry, and Connect custom resources are applied with readiness gates -- governance tasks do not begin until CRDs report ready
  3. KafkaTopic CRDs generated from CPTopic YAML definitions produce identical SLA-tier defaults (partitions, retention, compatibility) as the CP topic role
**Plans**: TBD

Plans:
- [ ] 14-01: CFK deployment playbook -- kubernetes.core.helm operator install, CR application, readiness gates
- [ ] 14-02: KafkaTopic CRD generation from CPTopic YAML with governance parity validation

### Phase 15: MRC Failover and DR Drill
**Goal**: Operators can execute MRC observer promotion for RPO=0 scenarios and run quarterly DR drills that produce compliance evidence reports -- building on proven MM2 playbooks from Phase 13
**Depends on**: Phase 13
**Requirements**: ADR-05, ADR-06
**Success Criteria** (what must be TRUE):
  1. Operator runs the MRC failover playbook and the observer replica is promoted to leader via Confluent CLI for RPO=0 scenarios
  2. Operator runs the DR drill playbook and it executes the full cycle (failover, validate, failback, validate) and generates a timestamped compliance report suitable for regulatory submission
**Plans**: TBD

Plans:
- [ ] 15-01: cp_dr_mrc role -- observer promotion via Confluent CLI, state validation
- [ ] 15-02: DR drill playbook -- full cycle orchestration and compliance report generation

## Progress

**Execution Order:**
Phases execute in numeric order: 10 -> 11 -> 12 -> 13 -> 14 -> 15
Note: Phase 13 (DR) depends on Phase 11, not Phase 12. Phase 14 (CFK) depends on Phase 10, not Phase 11. Phase 15 depends on Phase 13.

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Shared Governance Foundation | v1.0 | 3/3 | Complete | 2026-03-22 |
| 2. CC Multi-Cloud Scenarios | v1.0 | 2/2 | Complete | - |
| 3. Access Control and Compliance | v1.0 | 4/4 | Complete | - |
| 4. DR Automation Framework | v1.0 | 3/3 | Complete | - |
| 5. Observability Templates | v1.0 | 3/3 | Complete | - |
| 6. Flink on Confluent Cloud | v1.0 | 3/3 | Complete | - |
| 7. Onboarding and Developer Experience | v1.0 | 3/3 | Complete | - |
| 8. CFK on OpenShift | v1.0 | 3/3 | Complete | - |
| 9. CP on RHEL and Private Cloud | v1.0 | 4/4 | Complete | 2026-03-27 |
| 10. Ansible Foundation and Governance Scaffolding | v2.0 | 2/2 | Complete    | 2026-04-08 |
| 11. Core Governance Roles | v2.0 | 3/3 | Complete    | 2026-04-09 |
| 12. Orchestration Pipeline, Observability, and CI/CD | v2.0 | 3/3 | Complete    | 2026-04-09 |
| 13. DR Automation Playbooks (MM2) | v2.0 | 2/2 | Complete    | 2026-04-10 |
| 14. CFK on OpenShift Governance | v2.0 | 0/2 | Not started | - |
| 15. MRC Failover and DR Drill | v2.0 | 0/2 | Not started | - |

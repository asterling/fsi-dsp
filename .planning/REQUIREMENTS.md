# Requirements: FSI Kafka Platform

**Defined:** 2026-03-21
**Core Value:** Any FSI team can stand up a fully governed, observable, DR-ready Kafka/Flink/SR cluster in their deployment model of choice with a single automation run -- and onboard their first topic in under a day.

## v1 Requirements (Complete)

All 60 v1 requirements completed in milestone v1.0. See traceability section below.

### Infrastructure as Code

- [x] **IAC-01**: Operator can deploy CC on AWS with Terraform (topic, schema, RBAC, DR mirror) via self-contained scenario directory
- [x] **IAC-02**: Operator can deploy CC on GCP with Terraform (topic, schema, RBAC, DR mirror) via self-contained scenario directory
- [x] **IAC-03**: Operator can deploy CFK on OpenShift with Helm/operator manifests (KafkaCluster, SchemaRegistry, Connect, KafkaTopic CRDs)
- [x] **IAC-04**: Operator can deploy Confluent Platform on RHEL with Ansible roles (Kafka, SR, Connect, MDS RBAC)
- [x] **IAC-05**: Operator can deploy Confluent Private Cloud scenario with Terraform modules
- [x] **IAC-06**: Each scenario directory is self-contained with README, IaC files, variable examples, and quickstart instructions
- [x] **IAC-07**: Shared module library enforces identical topic naming, schema compatibility, RBAC, and SLA-tier defaults across all deployment models
- [x] **IAC-08**: Terraform state backend is parameterized per cloud provider (S3 for AWS, Azure Blob for Azure, GCS for GCP)
- [x] **IAC-09**: Cluster IDs, REST endpoints, and CRNs are externalized to centralized config instead of hardcoded locals
- [x] **IAC-10**: Post-apply validation confirms topic exists, schema registered, RBAC applied, and mirror created (Terraform test blocks or smoke script)

### Schema Governance

- [x] **SCHEMA-01**: CI pipeline validates schema compatibility before merge using SR compatibility API (not just at registration time)
- [x] **SCHEMA-02**: CI prevents namespace collisions by validating `.avsc` namespace matches `org.fsi.{domain}.{application}.{entity}` and subject does not already exist
- [x] **SCHEMA-03**: CI blocks `compatibility_override` unless paired with documented exception reference (ADR or JIRA link)
- [x] **SCHEMA-04**: Breaking change runbook in schema-guide.md walks teams through multi-topic migration for incompatible schema changes

### Access Control

- [x] **RBAC-01**: Service accounts provisioned via IaC alongside topic creation (CC: `confluent_service_account`, CFK: LDAP/AD bindings, CP: MDS)
- [x] **RBAC-02**: RBAC binding patterns produce identical permissions across CC (Confluent RBAC), CFK (operator RBAC), and CP (MDS RBAC)
- [x] **RBAC-03**: OAuth/OAUTHBEARER authentication documented and configured for CC deployments (Azure AD for Azure, AWS IAM for AWS)
- [x] **RBAC-04**: Credential rotation automation supports zero-downtime dual-credential window via Vault integration

### Disaster Recovery

- [x] **DR-01**: Single-command failover orchestrates all DR steps (pause connectors, promote mirrors, flip Consul, validate, resume, verify)
- [x] **DR-02**: Single-command failback automates reverse replication setup, mirror re-establishment, and cutover to primary
- [x] **DR-03**: Pluggable DR backend abstraction provides unified CLI (`fsi-dr failover/failback`) regardless of deployment model
- [x] **DR-04**: Cluster Linking adapter handles CC-native failover/failback with mirror topic promotion
- [x] **DR-05**: MirrorMaker 2 adapter handles CFK/CP failover/failback with topic replication
- [x] **DR-06**: MRC with automatic observer promotion (2.5-cluster pattern) provides RPO=0 for critical CP workloads
- [x] **DR-07**: Mirror lag monitoring exposes per-topic replication lag with SLA-tier-based alert thresholds
- [x] **DR-08**: State validation between failover steps verifies preconditions before proceeding (prevents partial failover)
- [x] **DR-09**: Dry-run mode previews all DR operations without executing (audit-ready output)
- [x] **DR-10**: Rollback capability reverts partial failover to safe state if intermediate step fails
- [x] **DR-11**: Unified DR runbook with decision trees, success/abort criteria per step, and rollback guidance
- [x] **DR-12**: Connect state tracking records which connectors were paused, enables correct resume after DR events

### Observability

- [x] **OBS-01**: Dynatrace dashboard templates covering cluster health, consumer lag, Connect status, DR readiness, and Flink job health
- [x] **OBS-02**: Prometheus/Grafana dashboard templates covering cluster health, consumer lag, Connect status, DR readiness, and Flink job health
- [x] **OBS-03**: Datadog dashboard templates covering cluster health, consumer lag, Connect status, DR readiness, and Flink job health
- [x] **OBS-04**: Splunk dashboard templates covering cluster health, consumer lag, Connect status, DR readiness, and Flink job health
- [x] **OBS-05**: New Relic dashboard templates covering cluster health, consumer lag, Connect status, DR readiness, and Flink job health
- [x] **OBS-06**: IBM Instana dashboard templates covering cluster health, consumer lag, Connect status, DR readiness, and Flink job health
- [x] **OBS-07**: Alert threshold configuration varies by SLA tier (critical: tight thresholds, standard: moderate, best-effort: relaxed)
- [x] **OBS-08**: Auto-discovery rules surface new topics in dashboards by domain prefix pattern without manual config
- [x] **OBS-09**: Metrics export configured per deployment model (CC Metrics API for cloud, JMX exporter for CFK/CP)
- [x] **OBS-10**: Connect connector status monitoring alerts on FAILED task state across all deployment models

### Flink

- [x] **FLINK-01**: CC Flink compute pool provisioned via Terraform (`confluent_flink_compute_pool`, `confluent_flink_statement`)
- [x] **FLINK-02**: CFK Flink deployed via Flink Kubernetes Operator Helm chart on OpenShift
- [x] **FLINK-03**: CP standalone Flink deployed via Ansible roles with systemd service management
- [x] **FLINK-04**: Flink SQL reference templates for tumbling window aggregation, stream-table join enrichment, and filter-and-route patterns
- [x] **FLINK-05**: Flink integrates with Schema Registry for Avro serde (CC Flink auto-discovers SR subjects; CFK/CP uses Flink Avro format connector)
- [x] **FLINK-06**: Flink job metrics (checkpoint duration, backpressure, throughput) exported to each provider's dashboard templates
- [x] **FLINK-07**: Flink dead letter handling routes deserialization failures to `{topic}.dlq` topics via CC Flink error-handling.mode table properties

### Onboarding

- [x] **ONBOARD-01**: Generic FSI intake form template includes deployment model selection field and removes all client-specific references
- [x] **ONBOARD-02**: C4E review automation in CI validates naming, schema compat, RBAC completeness, and SLA tier before human review gate
- [x] **ONBOARD-03**: Python reference producer/consumer using confluent-kafka-python added alongside existing Java and .NET
- [x] **ONBOARD-04**: Integration test suite covers error paths: serialization failure, RBAC denial, schema incompatibility, and broker failure
- [x] **ONBOARD-05**: Local dev Docker Compose extended to include Flink for stream processing development and testing
- [x] **ONBOARD-06**: DLQ pattern in reference producers (Java, .NET, Python) with exponential backoff retry, error categorization, and JMX metrics

### Compliance

- [x] **COMP-01**: Compliance SLA tier added with configurable retention up to 7 years for OFAC/AML/CFT topics
- [x] **COMP-02**: Data classification enforcement ensures `confidential` topics receive encryption rules, restricted consumer list, and enhanced logging
- [x] **COMP-03**: FIPS 140-2 compliance automated for CP on RHEL (FIPS-validated JVM, TLS libraries, CFK on FIPS-enabled OpenShift)
- [x] **COMP-04**: Audit trail documentation maps PR -> review -> merge -> apply -> verify for regulatory examiner consumption

### Governance Documentation

- [x] **GOV-01**: ADR for OAuth vs API keys authentication decision with deployment-model-specific guidance
- [x] **GOV-02**: ADR for topic naming rationale explaining `{domain}.{application}.{version}.{entity}` convention
- [x] **GOV-03**: ADR for DR tier classification (RPO/RTO targets per SLA tier, backend selection criteria)

## v2 Requirements

Requirements for milestone v2.0: Ansible Based Automation. Each maps to roadmap phases.

### Ansible Foundation

- [x] **AFOUND-01**: `ansible/` directory contains `requirements.yml` with pinned cp-ansible 7.7.x collection, `ansible.cfg`, and multi-environment inventory skeletons (dev/staging/prod/dr)
- [x] **AFOUND-02**: Shared governance constants in `ansible/vars/sla_tiers.yml` mirror Terraform module SLA-tier mappings (partitions, retention, compatibility per tier) and CI validates parity
- [x] **AFOUND-03**: Topic naming validation regex in `ansible/vars/naming_rules.yml` matches Terraform `variables.tf` regex and CI validates parity
- [x] **AFOUND-04**: Filter plugin (`filter_plugins/fsi_governance.py`) provides Jinja2 filters for SLA-tier lookups and topic name assembly usable by all roles
- [x] **AFOUND-05**: `.ansible-lint` config with `shared` profile enforces FQCN, Galaxy metadata, and documentation standards on all roles

### Ansible Topic Lifecycle

- [x] **ATOPIC-01**: Operator can create topics on CP cluster via Ansible role using Admin REST v3 API with idempotent GET-before-POST pattern
- [x] **ATOPIC-02**: Topic configuration (partitions, retention, min.insync.replicas, cleanup policy) is automatically derived from SLA tier using shared governance constants
- [x] **ATOPIC-03**: Role consumes existing CPTopic YAML format from `scenarios/cp-rhel/topics/*.yml` without requiring a new input format
- [x] **ATOPIC-04**: Role validates topic names against `{domain}.{application}.{version}.{entity}` regex before API calls, failing fast with clear error message
- [x] **ATOPIC-05**: Topic config updates (retention, cleanup, min.insync.replicas) converge to declared state without recreating topics
- [x] **ATOPIC-06**: Running the playbook in `--check` mode shows what would change without making any mutations (dry-run for CAB approval)
- [x] **ATOPIC-07**: Topic deletion requires explicit `state: absent` plus `confirm_deletion: true` and refuses to delete critical/compliance tier topics without override

### Ansible Schema Registration

- [x] **ASCHEMA-01**: Operator can register Avro schemas to CP Schema Registry via Ansible role using SR REST API
- [x] **ASCHEMA-02**: Role runs compatibility pre-check against existing versions before registration and fails with clear message if incompatible (two-pass: validate all, then register all)
- [x] **ASCHEMA-03**: Schema compatibility mode per subject is set from SLA tier (critical/compliance=FULL_TRANSITIVE, standard=BACKWARD_TRANSITIVE, best-effort=BACKWARD)
- [x] **ASCHEMA-04**: Role reuses existing `ci/scripts/validate-schemas.py` for structural validation before SR API calls
- [x] **ASCHEMA-05**: PII metadata properties (owner, sla-tier, data-classification, pii-fields) are applied to SR subjects matching Terraform module metadata pattern

### Ansible RBAC Provisioning

- [x] **ARBAC-01**: Operator can provision per-topic RBAC bindings (DeveloperWrite for producers, DeveloperRead for consumers) via MDS REST API
- [x] **ARBAC-02**: Role acquires MDS bearer token with automatic refresh handling for playbook runs exceeding 15-minute token TTL
- [x] **ARBAC-03**: Consumer group bindings (`DeveloperRead` on `{principal}-*` prefixed group pattern) are created alongside topic bindings
- [x] **ARBAC-04**: Schema Registry subject bindings (DeveloperWrite for producers, DeveloperRead for all) are created alongside topic bindings
- [x] **ARBAC-05**: Role uses LIST/DIFF/ADD/REMOVE reconciliation pattern to remove stale bindings, not just add new ones (prevents RBAC drift)

### Ansible Deployment Pipeline

- [x] **APIPE-01**: Orchestration playbook (`site.yml`) chains cp-ansible cluster deployment with topic -> schema -> RBAC -> connectors -> observability in a single run
- [x] **APIPE-02**: Ansible tags allow selective execution (e.g., `--tags topics`, `--tags rbac`, `--tags observability`) for Day-2 operations without full pipeline re-run
- [x] **APIPE-03**: Connector deployment role creates/updates connectors via Connect REST API with idempotent create-if-absent, update-if-different pattern
- [x] **APIPE-04**: Connector health validation after deployment verifies all connectors and tasks are in RUNNING state with retry and backoff

### Ansible DR Automation

- [x] **ADR-01**: MM2 failover playbook orchestrates: pause connectors -> stop source MM2 -> promote topics -> update Consul -> validate -> resume on target
- [x] **ADR-02**: MM2 failback playbook reverses replication direction, re-establishes mirrors, validates data sync, and cuts back to primary
- [x] **ADR-03**: DR playbooks support `--check` mode (dry-run) generating audit-ready output showing every step without executing
- [x] **ADR-04**: DR state validation tasks check mirror lag against SLA-tier thresholds, cluster health, and topic writability before and after failover
- [x] **ADR-05**: MRC failover playbook promotes observer replica to leader for RPO=0 scenarios using Confluent CLI
- [ ] **ADR-06**: DR drill playbook runs full cycle (failover -> validate -> failback -> validate -> generate compliance report) for quarterly regulatory requirements

### Ansible Observability Deployment

- [x] **AOBS-01**: Observability role deploys JMX exporter configs from existing `observability/` templates to CP cluster nodes
- [x] **AOBS-02**: Prometheus scrape config is generated from inventory (broker, SR, Connect host groups) and updates automatically when nodes are added
- [x] **AOBS-03**: Grafana dashboards from `observability/grafana/` are imported via `community.grafana.grafana_dashboard` module or file provisioning
- [x] **AOBS-04**: Alert rules with SLA-tier-aware thresholds are deployed to the monitoring provider matching existing `alerts.yaml` definitions

### Ansible CFK on OpenShift

- [x] **ACFK-01**: Operator can deploy CFK operator on OpenShift via Ansible using `kubernetes.core.helm` module
- [x] **ACFK-02**: CFK custom resources (KafkaCluster, SchemaRegistry, Connect) are applied via `kubernetes.core.k8s` with readiness gates before governance tasks
- [x] **ACFK-03**: KafkaTopic CRDs are generated from CPTopic YAML definitions with governance parity (same SLA-tier defaults as CP REST API roles)

### Ansible CI/CD

- [x] **ACI-01**: GitHub Actions workflow runs ansible-lint and yamllint on every PR touching `ansible/` directory
- [x] **ACI-02**: Molecule test scenarios exist for each governance role (cp_topic, cp_schema, cp_rbac) with delegated driver
- [x] **ACI-03**: CI job validates governance constant parity between `ansible/vars/sla_tiers.yml` and Terraform `modules/topic/main.tf` locals

## v3 Requirements

Deferred to future milestone. Tracked but not in current roadmap.

### Advanced Governance

- **ADVGOV-01**: Data contract enforcement via Confluent Stream Governance (CEL-based field rules for encryption, validation, migration)
- **ADVGOV-03**: Schema catalog integration exporting SR subjects + metadata to Alation/Collibra/DataHub
- **ADVGOV-04**: Cost optimization reporting per domain/team via Confluent Cloud billing API

### Developer Experience

- **DX-01**: Golden path CLI scaffolds new topic from intake form answers (`fsi-kafka create-topic --domain X --entity Y --tier Z`)
- **DX-02**: Schema authoring assistant generates `.avsc` from JSON sample or table DDL with logical type inference
- **DX-03**: Topic topology visualization generates Mermaid diagrams from Terraform state or SR metadata

### Advanced DR

- **ADVDR-02**: Partial failover (per-domain topic-level mirror promotion) to reduce blast radius
- **ADVDR-03**: Cross-scenario integration testing validates same topic spec produces equivalent results across CC, CFK, and CP

### Cross-Deployment

- **XDEPLOY-01**: Deployment model migration tooling (export configs from source, generate IaC for target, migrate schemas)

### KRaft Migration

- **KRAFT-01**: cp-ansible 8.x migration playbook for ZooKeeper-to-KRaft transition on existing CP clusters

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Flink business logic (fraud scoring, compliance windowing) | Teams own business logic; C4E provides runtime and templates only |
| Web UI / portal for topic management | GitOps via PR is the governance model; UI bypasses audit trail |
| Multi-tenancy within single cluster | RBAC-only isolation is fragile; recommend dedicated clusters per environment |
| Custom Kafka distribution or fork | Confluent provides the distribution; C4E provides the governance wrapper |
| Confluent Cloud account/org provisioning | Account-level automation is platform team responsibility, not C4E |
| Real-time alerting engine | C4E provides alert definitions/thresholds; teams import into existing alerting stack |
| Data mesh / catalog platform | Catalog integration (export) is v3; building a catalog is out of scope |
| ChatOps / Slack bot | PR-based workflow is more auditable; document commands as informational only |
| Auto-scaling / capacity planning | Partition count is an architecture decision; CC auto-scales brokers; CFK/CP require manual sizing |
| Ansible for Confluent Cloud | No native Ansible provider; CC stays Terraform-only |
| Apache Kafka (non-Confluent) support | Roles target CP with MDS/Confluent CLI; vanilla Kafka lacks MDS |
| cp-ansible 8.x / KRaft migration | ZooKeeper removal is a separate milestone; v2.0 targets CP 7.7.x |
| Ansible Galaxy collection packaging | Roles are tightly coupled to repo governance data; distribution via Galaxy adds overhead with no consumer outside this repo |
| Custom Python Ansible modules | ansible.builtin.uri covers all REST API needs; custom modules add maintenance burden |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

### v1 Traceability (Complete)

| Requirement | Phase | Status |
|-------------|-------|--------|
| IAC-01 | Phase 2 | Complete |
| IAC-02 | Phase 2 | Complete |
| IAC-03 | Phase 8 | Complete |
| IAC-04 | Phase 9 | Complete |
| IAC-05 | Phase 9 | Complete |
| IAC-06 | Phase 2 | Complete |
| IAC-07 | Phase 1 | Complete |
| IAC-08 | Phase 2 | Complete |
| IAC-09 | Phase 1 | Complete |
| IAC-10 | Phase 2 | Complete |
| SCHEMA-01 | Phase 1 | Complete |
| SCHEMA-02 | Phase 1 | Complete |
| SCHEMA-03 | Phase 1 | Complete |
| SCHEMA-04 | Phase 1 | Complete |
| RBAC-01 | Phase 3 | Complete |
| RBAC-02 | Phase 3 | Complete |
| RBAC-03 | Phase 3 | Complete |
| RBAC-04 | Phase 3 | Complete |
| DR-01 | Phase 4 | Complete |
| DR-02 | Phase 4 | Complete |
| DR-03 | Phase 4 | Complete |
| DR-04 | Phase 4 | Complete |
| DR-05 | Phase 8 | Complete |
| DR-06 | Phase 9 | Complete |
| DR-07 | Phase 4 | Complete |
| DR-08 | Phase 4 | Complete |
| DR-09 | Phase 4 | Complete |
| DR-10 | Phase 4 | Complete |
| DR-11 | Phase 4 | Complete |
| DR-12 | Phase 4 | Complete |
| OBS-01 | Phase 5 | Complete |
| OBS-02 | Phase 5 | Complete |
| OBS-03 | Phase 5 | Complete |
| OBS-04 | Phase 5 | Complete |
| OBS-05 | Phase 5 | Complete |
| OBS-06 | Phase 5 | Complete |
| OBS-07 | Phase 5 | Complete |
| OBS-08 | Phase 5 | Complete |
| OBS-09 | Phase 5 | Complete |
| OBS-10 | Phase 5 | Complete |
| FLINK-01 | Phase 6 | Complete |
| FLINK-02 | Phase 8 | Complete |
| FLINK-03 | Phase 9 | Complete |
| FLINK-04 | Phase 6 | Complete |
| FLINK-05 | Phase 6 | Complete |
| FLINK-06 | Phase 6 | Complete |
| FLINK-07 | Phase 6 | Complete |
| ONBOARD-01 | Phase 7 | Complete |
| ONBOARD-02 | Phase 7 | Complete |
| ONBOARD-03 | Phase 7 | Complete |
| ONBOARD-04 | Phase 7 | Complete |
| ONBOARD-05 | Phase 7 | Complete |
| ONBOARD-06 | Phase 7 | Complete |
| COMP-01 | Phase 3 | Complete |
| COMP-02 | Phase 3 | Complete |
| COMP-03 | Phase 9 | Complete |
| COMP-04 | Phase 3 | Complete |
| GOV-01 | Phase 1 | Complete |
| GOV-02 | Phase 1 | Complete |
| GOV-03 | Phase 1 | Complete |

### v2 Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| AFOUND-01 | Phase 10 | Complete |
| AFOUND-02 | Phase 10 | Complete |
| AFOUND-03 | Phase 10 | Complete |
| AFOUND-04 | Phase 10 | Complete |
| AFOUND-05 | Phase 10 | Complete |
| ATOPIC-01 | Phase 11 | Complete |
| ATOPIC-02 | Phase 11 | Complete |
| ATOPIC-03 | Phase 11 | Complete |
| ATOPIC-04 | Phase 11 | Complete |
| ATOPIC-05 | Phase 11 | Complete |
| ATOPIC-06 | Phase 11 | Complete |
| ATOPIC-07 | Phase 11 | Complete |
| ASCHEMA-01 | Phase 11 | Complete |
| ASCHEMA-02 | Phase 11 | Complete |
| ASCHEMA-03 | Phase 11 | Complete |
| ASCHEMA-04 | Phase 11 | Complete |
| ASCHEMA-05 | Phase 11 | Complete |
| ARBAC-01 | Phase 11 | Complete |
| ARBAC-02 | Phase 11 | Complete |
| ARBAC-03 | Phase 11 | Complete |
| ARBAC-04 | Phase 11 | Complete |
| ARBAC-05 | Phase 11 | Complete |
| APIPE-01 | Phase 12 | Complete |
| APIPE-02 | Phase 12 | Complete |
| APIPE-03 | Phase 12 | Complete |
| APIPE-04 | Phase 12 | Complete |
| ADR-01 | Phase 13 | Complete |
| ADR-02 | Phase 13 | Complete |
| ADR-03 | Phase 13 | Complete |
| ADR-04 | Phase 13 | Complete |
| ADR-05 | Phase 15 | Complete |
| ADR-06 | Phase 15 | Pending |
| AOBS-01 | Phase 12 | Complete |
| AOBS-02 | Phase 12 | Complete |
| AOBS-03 | Phase 12 | Complete |
| AOBS-04 | Phase 12 | Complete |
| ACFK-01 | Phase 14 | Complete |
| ACFK-02 | Phase 14 | Complete |
| ACFK-03 | Phase 14 | Complete |
| ACI-01 | Phase 12 | Complete |
| ACI-02 | Phase 12 | Complete |
| ACI-03 | Phase 12 | Complete |

**Coverage:**
- v1 requirements: 60 total (all complete)
- v2 requirements: 42 total
- Mapped to phases: 42/42
- Unmapped: 0

---
*Requirements defined: 2026-03-21*
*Last updated: 2026-04-07 after v2.0 roadmap creation -- all 42 requirements mapped to Phases 10-15*

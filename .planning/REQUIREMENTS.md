# Requirements: FSI Kafka Platform

**Defined:** 2026-03-21
**Core Value:** Any FSI team can stand up a fully governed, observable, DR-ready Kafka/Flink/SR cluster in their deployment model of choice with a single automation run -- and onboard their first topic in under a day.

## v1 Requirements

Requirements for initial milestone. Each maps to roadmap phases.

### Infrastructure as Code

- [x] **IAC-01**: Operator can deploy CC on AWS with Terraform (topic, schema, RBAC, DR mirror) via self-contained scenario directory
- [x] **IAC-02**: Operator can deploy CC on GCP with Terraform (topic, schema, RBAC, DR mirror) via self-contained scenario directory
- [ ] **IAC-03**: Operator can deploy CFK on OpenShift with Helm/operator manifests (KafkaCluster, SchemaRegistry, Connect, KafkaTopic CRDs)
- [ ] **IAC-04**: Operator can deploy Confluent Platform on RHEL with Ansible roles (Kafka, SR, Connect, MDS RBAC)
- [ ] **IAC-05**: Operator can deploy Confluent Private Cloud scenario with Terraform modules
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

- [ ] **RBAC-01**: Service accounts provisioned via IaC alongside topic creation (CC: `confluent_service_account`, CFK: LDAP/AD bindings, CP: MDS)
- [ ] **RBAC-02**: RBAC binding patterns produce identical permissions across CC (Confluent RBAC), CFK (operator RBAC), and CP (MDS RBAC)
- [ ] **RBAC-03**: OAuth/OAUTHBEARER authentication documented and configured for CC deployments (Azure AD for Azure, AWS IAM for AWS)
- [ ] **RBAC-04**: Credential rotation automation supports zero-downtime dual-credential window via Vault integration

### Disaster Recovery

- [ ] **DR-01**: Single-command failover orchestrates all DR steps (pause connectors, promote mirrors, flip Consul, validate, resume, verify)
- [ ] **DR-02**: Single-command failback automates reverse replication setup, mirror re-establishment, and cutover to primary
- [ ] **DR-03**: Pluggable DR backend abstraction provides unified CLI (`fsi-dr failover/failback`) regardless of deployment model
- [ ] **DR-04**: Cluster Linking adapter handles CC-native failover/failback with mirror topic promotion
- [ ] **DR-05**: MirrorMaker 2 adapter handles CFK/CP failover/failback with topic replication
- [ ] **DR-06**: MRC with automatic observer promotion (2.5-cluster pattern) provides RPO=0 for critical CP workloads
- [ ] **DR-07**: Mirror lag monitoring exposes per-topic replication lag with SLA-tier-based alert thresholds
- [ ] **DR-08**: State validation between failover steps verifies preconditions before proceeding (prevents partial failover)
- [ ] **DR-09**: Dry-run mode previews all DR operations without executing (audit-ready output)
- [ ] **DR-10**: Rollback capability reverts partial failover to safe state if intermediate step fails
- [ ] **DR-11**: Unified DR runbook with decision trees, success/abort criteria per step, and rollback guidance
- [ ] **DR-12**: Connect state tracking records which connectors were paused, enables correct resume after DR events

### Observability

- [ ] **OBS-01**: Dynatrace dashboard templates covering cluster health, consumer lag, Connect status, DR readiness, and Flink job health
- [ ] **OBS-02**: Prometheus/Grafana dashboard templates covering cluster health, consumer lag, Connect status, DR readiness, and Flink job health
- [ ] **OBS-03**: Datadog dashboard templates covering cluster health, consumer lag, Connect status, DR readiness, and Flink job health
- [ ] **OBS-04**: Splunk dashboard templates covering cluster health, consumer lag, Connect status, DR readiness, and Flink job health
- [ ] **OBS-05**: New Relic dashboard templates covering cluster health, consumer lag, Connect status, DR readiness, and Flink job health
- [ ] **OBS-06**: IBM Instana dashboard templates covering cluster health, consumer lag, Connect status, DR readiness, and Flink job health
- [ ] **OBS-07**: Alert threshold configuration varies by SLA tier (critical: tight thresholds, standard: moderate, best-effort: relaxed)
- [ ] **OBS-08**: Auto-discovery rules surface new topics in dashboards by domain prefix pattern without manual config
- [ ] **OBS-09**: Metrics export configured per deployment model (CC Metrics API for cloud, JMX exporter for CFK/CP)
- [ ] **OBS-10**: Connect connector status monitoring alerts on FAILED task state across all deployment models

### Flink

- [ ] **FLINK-01**: CC Flink compute pool provisioned via Terraform (`confluent_flink_compute_pool`, `confluent_flink_statement`)
- [ ] **FLINK-02**: CFK Flink deployed via Flink Kubernetes Operator Helm chart on OpenShift
- [ ] **FLINK-03**: CP standalone Flink deployed via Ansible roles with systemd service management
- [ ] **FLINK-04**: Flink SQL reference templates for tumbling window aggregation, stream-table join enrichment, and filter-and-route patterns
- [ ] **FLINK-05**: Flink integrates with Schema Registry for Avro serde (CC Flink auto-discovers SR subjects; CFK/CP uses Flink Avro format connector)
- [ ] **FLINK-06**: Flink job metrics (checkpoint duration, backpressure, throughput) exported to each provider's dashboard templates
- [ ] **FLINK-07**: Flink dead letter handling routes deserialization/processing failures to `{topic}.dlq` topics via side output pattern

### Onboarding

- [ ] **ONBOARD-01**: Generic FSI intake form template includes deployment model selection field and removes all client-specific references
- [ ] **ONBOARD-02**: C4E review automation in CI validates naming, schema compat, RBAC completeness, and SLA tier before human review gate
- [ ] **ONBOARD-03**: Python reference producer/consumer using confluent-kafka-python added alongside existing Java and .NET
- [ ] **ONBOARD-04**: Integration test suite covers error paths: serialization failure, RBAC denial, schema incompatibility, and broker failure
- [ ] **ONBOARD-05**: Local dev Docker Compose extended to include Flink for stream processing development and testing
- [ ] **ONBOARD-06**: DLQ pattern in reference producers (Java, .NET, Python) with exponential backoff retry, error categorization, and JMX metrics

### Compliance

- [ ] **COMP-01**: Compliance SLA tier added with configurable retention up to 7 years for OFAC/AML/CFT topics
- [ ] **COMP-02**: Data classification enforcement ensures `confidential` topics receive encryption rules, restricted consumer list, and enhanced logging
- [ ] **COMP-03**: FIPS 140-2 compliance automated for CP on RHEL (FIPS-validated JVM, TLS libraries, CFK on FIPS-enabled OpenShift)
- [ ] **COMP-04**: Audit trail documentation maps PR -> review -> merge -> apply -> verify for regulatory examiner consumption

### Governance Documentation

- [x] **GOV-01**: ADR for OAuth vs API keys authentication decision with deployment-model-specific guidance
- [x] **GOV-02**: ADR for topic naming rationale explaining `{domain}.{application}.{version}.{entity}` convention
- [x] **GOV-03**: ADR for DR tier classification (RPO/RTO targets per SLA tier, backend selection criteria)

## v2 Requirements

Deferred to future milestone. Tracked but not in current roadmap.

### Advanced Governance

- **ADVGOV-01**: Data contract enforcement via Confluent Stream Governance (CEL-based field rules for encryption, validation, migration)
- **ADVGOV-02**: Topic lifecycle management (created -> active -> deprecated -> decommissioned) with consumer migration workflow
- **ADVGOV-03**: Schema catalog integration exporting SR subjects + metadata to Alation/Collibra/DataHub
- **ADVGOV-04**: Cost optimization reporting per domain/team via Confluent Cloud billing API

### Developer Experience

- **DX-01**: Golden path CLI scaffolds new topic from intake form answers (`fsi-kafka create-topic --domain X --entity Y --tier Z`)
- **DX-02**: Schema authoring assistant generates `.avsc` from JSON sample or table DDL with logical type inference
- **DX-03**: Topic topology visualization generates Mermaid diagrams from Terraform state or SR metadata

### Advanced DR

- **ADVDR-01**: DR drill automation (failover, validate, failback, compliance report) for quarterly regulatory requirements
- **ADVDR-02**: Partial failover (per-domain topic-level mirror promotion) to reduce blast radius
- **ADVDR-03**: Cross-scenario integration testing validates same topic spec produces equivalent results across CC, CFK, and CP

### Cross-Deployment

- **XDEPLOY-01**: Deployment model migration tooling (export configs from source, generate IaC for target, migrate schemas)

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
| Data mesh / catalog platform | Catalog integration (export) is v2; building a catalog is out of scope |
| ChatOps / Slack bot | PR-based workflow is more auditable; document commands as informational only |
| Auto-scaling / capacity planning | Partition count is an architecture decision; CC auto-scales brokers; CFK/CP require manual sizing |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| IAC-01 | Phase 2 | Complete |
| IAC-02 | Phase 2 | Complete |
| IAC-03 | Phase 8 | Pending |
| IAC-04 | Phase 9 | Pending |
| IAC-05 | Phase 9 | Pending |
| IAC-06 | Phase 2 | Complete |
| IAC-07 | Phase 1 | Complete |
| IAC-08 | Phase 2 | Complete |
| IAC-09 | Phase 1 | Complete |
| IAC-10 | Phase 2 | Complete |
| SCHEMA-01 | Phase 1 | Complete |
| SCHEMA-02 | Phase 1 | Complete |
| SCHEMA-03 | Phase 1 | Complete |
| SCHEMA-04 | Phase 1 | Complete |
| RBAC-01 | Phase 3 | Pending |
| RBAC-02 | Phase 3 | Pending |
| RBAC-03 | Phase 3 | Pending |
| RBAC-04 | Phase 3 | Pending |
| DR-01 | Phase 4 | Pending |
| DR-02 | Phase 4 | Pending |
| DR-03 | Phase 4 | Pending |
| DR-04 | Phase 4 | Pending |
| DR-05 | Phase 8 | Pending |
| DR-06 | Phase 9 | Pending |
| DR-07 | Phase 4 | Pending |
| DR-08 | Phase 4 | Pending |
| DR-09 | Phase 4 | Pending |
| DR-10 | Phase 4 | Pending |
| DR-11 | Phase 4 | Pending |
| DR-12 | Phase 4 | Pending |
| OBS-01 | Phase 5 | Pending |
| OBS-02 | Phase 5 | Pending |
| OBS-03 | Phase 5 | Pending |
| OBS-04 | Phase 5 | Pending |
| OBS-05 | Phase 5 | Pending |
| OBS-06 | Phase 5 | Pending |
| OBS-07 | Phase 5 | Pending |
| OBS-08 | Phase 5 | Pending |
| OBS-09 | Phase 5 | Pending |
| OBS-10 | Phase 5 | Pending |
| FLINK-01 | Phase 6 | Pending |
| FLINK-02 | Phase 8 | Pending |
| FLINK-03 | Phase 9 | Pending |
| FLINK-04 | Phase 6 | Pending |
| FLINK-05 | Phase 6 | Pending |
| FLINK-06 | Phase 6 | Pending |
| FLINK-07 | Phase 6 | Pending |
| ONBOARD-01 | Phase 7 | Pending |
| ONBOARD-02 | Phase 7 | Pending |
| ONBOARD-03 | Phase 7 | Pending |
| ONBOARD-04 | Phase 7 | Pending |
| ONBOARD-05 | Phase 7 | Pending |
| ONBOARD-06 | Phase 7 | Pending |
| COMP-01 | Phase 3 | Pending |
| COMP-02 | Phase 3 | Pending |
| COMP-03 | Phase 9 | Pending |
| COMP-04 | Phase 3 | Pending |
| GOV-01 | Phase 1 | Complete |
| GOV-02 | Phase 1 | Complete |
| GOV-03 | Phase 1 | Complete |

**Coverage:**
- v1 requirements: 60 total
- Mapped to phases: 60
- Unmapped: 0

---
*Requirements defined: 2026-03-21*
*Last updated: 2026-03-21 after roadmap creation*

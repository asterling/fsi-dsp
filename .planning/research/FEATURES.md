# Feature Landscape

**Domain:** FSI Multi-Deployment Kafka/Flink C4E Platform
**Researched:** 2026-03-21
**Confidence:** MEDIUM (based on codebase analysis, Confluent ecosystem training data, FSI domain knowledge; no live web verification available)

## Table Stakes

Features FSI teams expect from a C4E platform. Missing any of these and teams either build their own (shadow platform) or leave for a vendor-managed alternative.

### Infrastructure as Code (Multi-Deployment)

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Confluent Cloud Terraform modules (AWS, Azure, GCP) | Teams on CC expect IaC for topic/schema/RBAC provisioning. Azure already exists; AWS and GCP are the same Confluent provider with different networking/backend configs. | Medium | Existing CC-Azure module is the template. AWS/GCP need provider-specific networking (PrivateLink, PSC), backend (S3, GCS), and auth (IAM, Workload Identity). Core topic module is cloud-agnostic. |
| CFK on OpenShift operator manifests + Helm | FSI shops running on-prem OCP expect Kubernetes-native deployment. CFK operator is the standard path. | High | CFK has its own CRD model (KafkaCluster, SchemaRegistry, Connect, KafkaTopic). Not a simple port of Terraform -- different IaC paradigm entirely. Requires OLM (Operator Lifecycle Manager) integration. |
| Confluent Platform on RHEL via Ansible | Legacy FSI deployments on bare metal/VM expect systemd-based automation. Still common at banks with air-gapped environments. | High | Confluent provides cp-ansible but it needs customization for FSI security (mTLS, LDAP/Kerberos, FIPS 140-2 compliance). Least cloud-native path but still required. |
| Scenario directory structure | Teams browse, pick their deployment model, copy-paste. Lower barrier than a CLI generator. | Low | Already decided (PROJECT.md). Each scenario is self-contained with README, IaC, and variable examples. |
| Shared module library across scenarios | Core governance (topic naming, schema compat, RBAC patterns) must be identical regardless of deployment model. Drift between scenarios is a governance failure. | Medium | The abstraction challenge: Terraform for CC, CRDs for CFK, Ansible roles for CP. Need a common "topic specification" format that renders to each target. |
| Terraform state backend per cloud provider | Each cloud has its own state backend (azurerm, s3, gcs). Teams expect this to work out of the box. | Low | Parameterize backend selection. Document that backend migration requires `terraform init -migrate-state`. |

### Schema Governance

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Schema registration with compatibility enforcement | Already exists. SLA-tier-based compatibility modes (FULL_TRANSITIVE, BACKWARD_TRANSITIVE, BACKWARD) are table stakes for FSI data contracts. | Low | Validated in existing codebase. Works across all deployment models since SR is the same API regardless of deployment. |
| Schema evolution CI validation | Teams expect the CI pipeline to catch breaking schema changes before merge, not after apply. Schema Registry compatibility checks at registration time are too late -- feedback must be in the PR. | Medium | Use `confluent schema-registry compatibility validate` or SR REST API `/compatibility/subjects/{subject}/versions/{version}` in CI. Needs SR credentials in CI context. |
| Schema namespace collision prevention | When 50+ teams share one SR, accidental subject name collisions corrupt data contracts. Namespace enforcement is not optional at FSI scale. | Medium | CI check: validate that `.avsc` namespace matches `{org}.{domain}.{app}.{version}` and that subject does not already exist (unless version bump). Identified in CONCERNS.md. |
| PII field tagging and metadata | Regulators (OCC, CFPB, GDPR/CCPA) require knowing where PII flows. Schema metadata must declare PII fields. | Low | Already exists via `pii_fields` variable and schema metadata tags. Extend to support Confluent Stream Governance data contracts for field-level encryption rules. |
| Compatibility override governance | Override of C4E-mandated compatibility must require documented justification. Convention-only enforcement is insufficient. | Low | CI lint that blocks `compatibility_override != null` unless paired with ADR or exception ticket reference. Identified in CONCERNS.md. |

### RBAC and Access Control

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Per-topic RBAC via IaC | Already exists. Producer/consumer service account bindings are provisioned alongside the topic. This is non-negotiable for FSI. | Low | Validated. Works for CC via Confluent RBAC. CFK uses Confluent RBAC or Kubernetes RBAC. CP uses MDS (Metadata Service) RBAC. Need adapter per deployment model. |
| Service account provisioning | Teams expect to request a service account and get credentials as part of onboarding. Manual provisioning is a bottleneck. | Medium | Current model assumes SA already exists. Extending to provision SAs via Terraform (`confluent_service_account`) eliminates a manual step. For CFK/CP, this maps to LDAP/AD group bindings. |
| OAuth/OAUTHBEARER authentication | API key rotation is operationally expensive. FSI teams on Azure expect Azure AD (Entra ID) OAUTHBEARER. AWS teams expect IAM auth. | Medium | Already noted in cloud-providers.md. OAuth eliminates credential rotation for DR failover (tokens work against both clusters). Critical path for operational maturity. |
| Credential rotation automation | If sticking with API keys, zero-downtime rotation must be automated. Manual rotation at 90-day cadence across 100+ topics is untenable. | High | Requires dual-credential support during rotation window. Vault integration (already in FSI stack per ADR-003) is the path. |

### Disaster Recovery

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Automated DR failover (single command) | 6 manual steps during a crisis is unacceptable for production FSI. OCC expects documented, tested, repeatable DR procedures. | High | Orchestration script wrapping: pause connectors, promote mirrors, flip Consul, validate state, resume connectors, verify. Dry-run mode mandatory. Identified as top concern. |
| DR failback automation | Getting back to primary after incident must be equally automated. Many platforms automate failover but forget failback. | High | Failback is harder than failover: must re-establish mirror links, reverse replication direction, verify data consistency, then cut over. |
| Pluggable DR backend abstraction | Same CLI/UX regardless of deployment model. CC uses Cluster Linking, CFK/CP uses MirrorMaker 2. Teams should not care which. | High | Unified interface: `fsi-dr failover --cluster prod-east --target prod-west --dry-run`. Backend adapters for Cluster Linking (CC), MM2 (CFK/CP), MRC (CP RPO=0). |
| Mirror lag monitoring with alerting | FSI regulators ask "what is your data loss window?" Must have real-time answer per topic. | Medium | CC: Confluent Cloud Metrics API (mirror lag metric). CFK/CP: JMX metrics from MM2. Alert thresholds by SLA tier. |
| DR state validation between steps | Each failover step must verify preconditions before proceeding. Partial failover is worse than no failover. | Medium | State machine pattern: each step checks exit conditions of previous step. Rollback if any validation fails. |
| Dry-run mode for all DR operations | Preview what will happen before committing. Regulators love this for audit evidence. | Low | Print what each step would do without executing. Log output identical to real run for review. |
| Unified DR runbook with decision trees | Operators need a single document, not scattered script comments. | Low | Markdown document with decision trees: "Is mirror lag < threshold? YES -> proceed. NO -> abort and investigate." |

### Observability

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Per-provider dashboard templates | FSI shops are locked into their APM vendor. Providing Datadog templates to a Dynatrace shop is useless. Must cover the FSI observability landscape. | High (breadth) | Dynatrace, Datadog, Splunk, New Relic, Grafana/Prometheus, IBM Instana. Each needs: cluster health, consumer lag, Connect status, DR mirror lag, Flink job health. Templates, not integrations -- teams import and customize. |
| Consumer lag monitoring and alerting | The single most important Kafka operational metric. Teams expect it visible day one. | Medium | CC: Confluent Cloud Metrics API or Confluent Health+ (exports to monitoring). CFK/CP: JMX exporter -> Prometheus -> provider. Alert thresholds by SLA tier. |
| Cluster health dashboards | Broker status, partition leadership, ISR count, rebalance events. Ops teams expect to see this without building it. | Medium | Per deployment model: CC uses Cloud Metrics API, CFK/CP use JMX. Dashboard template per observability provider. |
| Connect connector status monitoring | Connector failures are silent unless monitored. Failed tasks do not auto-restart (depends on config). | Medium | Connect REST API polling or JMX metrics. Alert on FAILED task state. Include in DR readiness dashboard. |
| Alert threshold configuration per SLA tier | Critical topics need tighter alert thresholds than best-effort. One-size-fits-all alerts create noise. | Low | Configuration layer: `critical` -> lag > 1000 records alert, `standard` -> lag > 10000, `best-effort` -> lag > 100000. |
| Auto-discovery for new topics | When a new topic is onboarded, observability should pick it up automatically (by domain prefix pattern). | Medium | Metrics API wildcard queries or label-based Prometheus scraping. New topics appear in dashboards without manual config. |

### Onboarding and Self-Service

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Intake form template (generic FSI) | Current form works but references client-specific details. Must be genericized for any FSI adopter. | Low | Already exists as GitHub issue template. Remove client-specific names, add deployment model selection field. |
| C4E review automation in CI | Human review is the bottleneck. CI should lint and validate (naming, schema compat, RBAC completeness) before human review. | Medium | Terraform validate + custom lint rules (topic name format, required metadata, SLA tier matches schema compat). Human review remains as gate for architecture decisions. |
| Reference implementations (Java, .NET, Python) | Teams expect copy-paste-ready producer/consumer code in their language. Java and .NET exist. Python is expected by data engineering teams. | Medium | Python reference using confluent-kafka-python. Flink SQL examples also serve as "reference implementations" for stream processing. |
| Local development environment | Teams need to develop and test locally before deploying to CC/CFK/CP. Docker Compose exists. | Low | Already validated. Extend to include Flink for stream processing local dev. |
| Integration test suite | Teams expect to validate their topic/schema/RBAC config in CI before production apply. | Medium | Extend existing roundtrip test with error path tests (serialization failure, RBAC denial, schema incompatibility). |

### Compliance

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Compliance-tier retention (up to 7 years) | OFAC/AML/CFT regulations mandate long retention for transaction records. Current 7-day max for critical topics is insufficient. | Low | Add `compliance` SLA tier or `retention_ms_override` guidance. Document that long-term retention should use tiered storage (CC) or archival to object storage, not infinite Kafka retention. |
| Audit trail for infrastructure changes | OCC examiners want to see who changed what, when, and why. Git history + Terraform state + CI logs provide this. | Low | Already exists via GitOps workflow (PR -> review -> merge -> apply). Document the audit trail path for examiners. |
| Data classification enforcement | Topics with `confidential` classification need additional controls (encryption at rest, restricted access, audit logging). | Medium | Enforce that `data_classification = "confidential"` triggers: encryption rules in schema, restricted consumer list, enhanced logging. |
| FIPS 140-2 compliance for on-prem | Federal FSI (credit unions, banks with federal charters) may require FIPS-validated cryptography. | High | Affects CP on RHEL scenario: must use FIPS-validated JVM, TLS libraries. CFK on FIPS-enabled OpenShift. CC handles this server-side. |

## Differentiators

Features that set this platform apart from "just another Kafka deployment." Not expected, but valued. These justify C4E investment.

### Cross-Deployment Parity

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Unified topic specification format | Define a topic once in a declarative format (YAML/HCL), render to Terraform (CC), CRD (CFK), or Ansible (CP). Teams switching deployment models keep the same governance. | High | This is the core differentiator. Most C4E platforms are single-deployment. A cross-deployment spec that guarantees naming, schema compat, RBAC, and SLA-tier behavior is identical is rare. |
| Deployment model migration path | Document and automate migrating from CC to CFK or CP to CC. FSI acquisitions and strategy changes cause deployment model shifts. | High | Migration tooling: export topic configs from source, generate IaC for target, migrate schemas, re-establish DR. This is aspirational but extremely valuable. |
| Cross-scenario integration testing | CI validates that the same topic spec produces equivalent results across CC, CFK, and CP. | High | Requires test environments for each deployment model. Start with CC + local-dev (Docker Compose simulating CFK/CP). |

### Flink Integration

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Flink SQL reference job templates | Provide windowing, enrichment, and filtering templates that teams customize. Accelerates stream processing adoption. | Medium | Templates: tumbling window aggregation, stream-table join (enrichment), filter-and-route. All use SR Avro serde. CC Flink, CFK Flink (KafkaFlink CRD), standalone Flink. |
| Flink cluster deployment per scenario | Each deployment model has its own Flink runtime. CC uses managed Flink. CFK can run Flink on K8s (Flink Kubernetes Operator). CP runs standalone Flink. | High | CC Flink: Terraform resources (`confluent_flink_compute_pool`, `confluent_flink_statement`). CFK: Flink Kubernetes Operator Helm chart. CP: Ansible role for standalone Flink. Three different IaC paths. |
| Flink observability integration | Flink job metrics (checkpoint duration, backpressure, throughput) exported to the team's observability provider. | Medium | CC Flink: Confluent Cloud Metrics API includes Flink metrics. CFK/standalone: Flink metrics reporter -> Prometheus -> provider. Dashboard template per provider. |
| Flink-Schema Registry integration | Flink SQL reads/writes Avro via SR. Schema evolution in SR is automatically picked up by Flink jobs. | Low | Flink's Confluent Avro format connector handles this natively. Document the catalog/database/table mapping for CC Flink (which auto-discovers SR subjects). |
| Flink dead letter handling | Flink jobs that encounter deserialization errors or processing failures route bad records to DLQ topics. | Medium | Flink's side output pattern for error records. Template includes DLQ topic creation and routing logic. |

### Advanced DR

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| MRC with observer promotion (2.5-cluster) for RPO=0 | For the most critical FSI workloads (wire transfers, OFAC screening), zero data loss is a regulatory requirement. MRC provides synchronous replication with automatic observer promotion. | Very High | Requires Confluent Platform (not CC). The "2.5-cluster" pattern: 2 sync replicas (East/West) + 1 async observer (for reads during normal operation). Observer auto-promotes to leader on region failure. This is the gold standard for FSI DR. |
| DR drill automation | Quarterly DR drills are required by regulators. Automating the drill (failover, validate, failback, report) saves days of manual effort. | Medium | Script: execute failover in non-prod, run validation suite, execute failback, generate compliance report (timestamps, lag, data validation). |
| Partial failover (per-domain) | Fail over only the affected domain's topics, not the entire cluster. Reduces blast radius. | High | Requires topic-level mirror promotion rather than cluster-level. More complex orchestration but significantly reduces DR risk. |

### Advanced Governance

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Data contract enforcement (Confluent Stream Governance) | Field-level rules (encryption, validation, migration) enforced at the broker/SR level. Goes beyond schema compatibility to enforce business rules on data shape. | High | Requires Confluent Advanced Stream Governance license. CEL-based rules for field encryption (PII masking), field validation (e.g., `amount > 0`), and migration rules. Already referenced in existing schema-guide.md. |
| Topic lifecycle management | Topics have a lifecycle: created, active, deprecated, decommissioned. Most platforms only handle creation. Managing the full lifecycle (including safe decommission with consumer migration) is differentiating. | Medium | Terraform lifecycle + metadata tags for status. Decommission workflow: mark deprecated, notify consumers, wait for migration, reduce retention, delete. |
| Schema catalog integration | Schemas feed into a data catalog (Alation, Collibra, DataHub) for discoverability. Teams find existing topics/schemas before creating new ones. | Medium | Already hinted in schema-guide.md (`doc` fields "feed into Alation"). Formalize: export SR subjects + metadata to catalog via API. Out of scope for initial milestone per PROJECT.md but valuable for roadmap. |
| Cost optimization reporting | CC cluster costs by domain/team. Helps C4E justify platform investment and charge back to lines of business. | Low | Confluent Cloud billing API or cost reports grouped by topic prefix (domain). Dashboard template for finance teams. |

### Developer Experience

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Golden path CLI (optional) | Beyond scenario directories, a CLI that scaffolds a new topic from intake form answers. `fsi-kafka create-topic --domain cncb --entity account-tx --tier critical` generates the Terraform module call, schema stub, and PR. | Medium | Nice-to-have on top of scenario directories. Reduces onboarding from "read docs and copy-paste" to "run one command." Not critical for launch. |
| Schema authoring assistant | Generate an Avro schema from a JSON sample or a table DDL. Reduces the Avro learning curve. | Low | Script: input JSON -> output .avsc with inferred types. Logical type hints (timestamp fields -> timestamp-millis, decimal fields -> decimal). |
| Topic topology visualization | Visual map of topics, producers, consumers, and data flow per domain. Helps architecture review and onboarding. | Medium | Generate Mermaid diagrams from Terraform state or SR metadata. Shows: Topic A -> Consumer Group B -> Topic C (enriched). |

## Anti-Features

Features to explicitly NOT build. Including them would increase scope, maintenance burden, or conflict with C4E philosophy.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Flink business logic (fraud scoring, compliance windowing) | Teams own their business logic. C4E provides the runtime and templates, not the jobs. Building business logic creates coupling and maintenance burden. | Provide Flink SQL templates (windowing, enrichment, filtering) and let teams compose their own jobs. Reference implementations show the pattern; teams own the logic. |
| Web UI / portal for topic management | UI adds massive maintenance surface (frontend framework, auth, RBAC, state management). GitOps via PR is the governance model. A UI bypasses the audit trail. | Keep GitOps as the primary interface. If visualization is needed, point teams to Confluent Cloud Console, Control Center (CP/CFK), or the topology visualization differentiator above. |
| Multi-tenancy within a single cluster | Sharing a Kafka cluster across domains with RBAC-only isolation is fragile. Noisy neighbor, quota management, and blast radius problems. | Recommend dedicated clusters per environment/domain for critical workloads. Use RBAC for access control within a cluster, not for isolation. |
| Custom Kafka distribution or fork | Maintaining a custom Kafka build is unsustainable. Confluent provides the distribution; C4E provides the governance wrapper. | Use Confluent's distribution (CC, CFK operator, CP packages) as-is. Customize via configuration, not code. |
| Confluent Cloud account/org provisioning | Account-level automation is a different concern (cloud platform team, not C4E). Mixing account provisioning with topic provisioning conflates responsibilities. | Assume org, environment, and cluster exist. Document prerequisites. Provide a separate "cluster bootstrap" guide for platform teams. |
| Real-time alerting engine | Building a custom alerting system duplicates what Dynatrace/Datadog/etc. already do. C4E provides alert definitions (thresholds), not alert infrastructure. | Provide alert rule templates per observability provider. Teams import into their existing alerting stack. |
| Data mesh / catalog platform | Data mesh is an organizational pattern, not a C4E feature. Catalog integration (export metadata) is in scope; building a catalog is not. | Export schema metadata to existing catalogs (Alation, Collibra, DataHub). Do not build a catalog. |
| ChatOps / Slack bot for topic management | Adds integration surface, auth complexity, and audit trail gaps. PR-based workflow is more auditable and governed. | Document commands for Teams/Slack channels as informational. All changes go through Git PRs. |
| Automated capacity planning / auto-scaling | Partition count and cluster sizing are architecture decisions, not automation candidates. Auto-scaling partitions is irreversible and can cause rebalance storms. | Provide sizing guidance per SLA tier. Partition count is set at creation and reviewed at architecture review. CC auto-scales brokers (managed), CFK/CP require manual scaling decisions. |

## Feature Dependencies

```
Scenario Directory Structure
  |-> CC-AWS Terraform Modules
  |-> CC-Azure Terraform Modules (exists)
  |-> CC-GCP Terraform Modules
  |-> CFK OpenShift Manifests
  |-> CP RHEL Ansible Roles
  |-> Shared Module Library (consumed by all above)
       |-> Topic Naming Validation
       |-> Schema Compatibility Enforcement
       |-> RBAC Binding Patterns
       |-> SLA Tier Defaults

Schema Governance (CI Validation)
  |-> Schema Evolution CI Check (requires SR credentials in CI)
  |-> Namespace Collision Prevention (requires subject registry query)
  |-> Compatibility Override Governance (requires CI lint rules)

DR Framework
  |-> Pluggable Backend Abstraction
       |-> Cluster Linking Adapter (CC)
       |-> MirrorMaker 2 Adapter (CFK/CP)
       |-> MRC Adapter (CP RPO=0) -- depends on CP scenario being built first
  |-> Orchestrated Failover CLI
       |-> State Validation Between Steps
       |-> Dry-Run Mode
       |-> Rollback Capability
  |-> Mirror Lag Monitoring
       |-> Per-Provider Alert Templates

Observability Templates
  |-> Metrics Export per Deployment Model
       |-> CC Metrics API Integration
       |-> JMX Exporter Config (CFK/CP)
  |-> Dashboard Templates per Provider (6 providers)
       |-> Cluster Health
       |-> Consumer Lag
       |-> Connect Status
       |-> DR Mirror Lag
       |-> Flink Job Health (depends on Flink integration)
  |-> Auto-Discovery Rules

Flink Integration
  |-> Flink Cluster Deployment per Scenario
       |-> CC Flink Compute Pool (Terraform)
       |-> CFK Flink on K8s (Flink K8s Operator)
       |-> CP Standalone Flink (Ansible)
  |-> Flink SQL Reference Templates (depends on SR integration)
  |-> Flink Observability (depends on observability templates)

Onboarding
  |-> Generic Intake Form (no dependencies)
  |-> C4E Review Automation (depends on schema CI validation + TF validate)
  |-> Reference Implementations (Java exists, .NET exists, add Python)
  |-> Integration Test Suite (depends on local dev environment)

Compliance
  |-> Compliance-Tier Retention (depends on topic module update)
  |-> FIPS 140-2 (depends on CP RHEL scenario)
  |-> Data Classification Enforcement (depends on schema metadata)
  |-> Audit Trail Documentation (depends on GitOps workflow -- already exists)
```

## MVP Recommendation

Prioritize for the multi-deployment milestone:

### Must Ship (Table Stakes)

1. **Scenario directory structure with CC-AWS and CC-GCP modules** -- Unlocks multi-cloud. CC-Azure already exists. Reuse existing topic module with cloud-specific networking/backend.
2. **Shared module library abstraction** -- Without this, governance drifts between scenarios from day one.
3. **Schema evolution CI validation** -- The #1 governance gap identified in CONCERNS.md. Teams will override compatibility without guardrails.
4. **Automated DR failover (single command)** -- The #1 operational risk. 6 manual steps during a crisis is unacceptable for production FSI.
5. **Consumer lag monitoring with per-provider templates** -- Start with Dynatrace + Grafana/Prometheus (highest FSI adoption). Expand to other providers.
6. **Generic FSI intake form + C4E review automation** -- Enables self-service onboarding at scale.

### Should Ship (Table Stakes, Lower Risk)

7. **CFK on OpenShift scenario** -- High complexity but required for on-prem FSI. Can ship slightly after CC scenarios.
8. **Flink SQL reference templates + CC Flink deployment** -- Flink is a strategic differentiator. CC Flink is simplest to deploy.
9. **DR dry-run mode and state validation** -- Foundational for DR drills and compliance evidence.
10. **Compliance-tier retention** -- Low complexity, high regulatory value.

### Defer

- **CP on RHEL via Ansible** -- Highest complexity scenario. Ship after CC and CFK are proven. Many FSI shops are migrating away from bare metal anyway.
- **MRC with observer promotion** -- Requires CP, which is deferred. Document as future-state for RPO=0 requirements.
- **Data contract enforcement (Stream Governance)** -- Requires license upgrade. Table stakes governance covers 90% of needs.
- **Schema catalog integration** -- Explicitly out of scope per PROJECT.md. Valuable but separate milestone.
- **Deployment model migration tooling** -- Aspirational. Ship the scenarios first, migration second.
- **All 6 observability providers** -- Start with Dynatrace + Grafana. Add Datadog and Splunk next. New Relic and Instana are lower priority.

## Sources

- Existing codebase analysis: `modules/topic/main.tf`, `modules/topic/variables.tf`, all 5 ADRs, `docs/schema-guide.md`, `docs/onboarding.md`, `docs/cloud-providers.md`
- Project context: `.planning/PROJECT.md` (active requirements, constraints, key decisions)
- Known gaps: `.planning/codebase/CONCERNS.md` (14 documented technical concerns)
- Confluent ecosystem knowledge: training data (MEDIUM confidence -- Confluent Terraform provider v2.x, CFK operator, Flink on CC, Stream Governance features are well-documented in training data but version-specific details may have shifted)
- FSI regulatory domain: training data (MEDIUM confidence -- OCC examination procedures, FFIEC guidance on IT risk, AML/CFT retention requirements are stable regulatory frameworks unlikely to have changed materially)
- Observability vendor landscape: training data (LOW confidence for specific feature availability -- vendor capabilities evolve rapidly; dashboard template formats should be verified against current provider APIs)

# Architecture Patterns

**Domain:** Multi-deployment FSI Kafka/Flink platform
**Researched:** 2026-03-21
**Overall Confidence:** MEDIUM (training data + codebase evidence; no live web verification available)

## Recommended Architecture

The platform evolves from a single-scenario CC-on-Azure monolith into a **scenario-rooted, shared-module architecture** where each deployment model (CC-AWS, CC-Azure, CC-GCP, CFK-on-OCP, CP-on-RHEL, CPC) gets its own self-contained scenario directory that composes shared governance modules. A pluggable DR framework sits alongside as a cross-cutting CLI tool.

```
fsi-kafka-platform/
|
|-- scenarios/                          # <-- NEW: Each deployment model is a scenario
|   |-- cc-aws/                         #     Confluent Cloud on AWS
|   |-- cc-azure/                       #     Confluent Cloud on Azure (migrated from environments/prod/)
|   |-- cc-gcp/                         #     Confluent Cloud on GCP
|   |-- cfk-openshift/                  #     Confluent for Kubernetes on OCP 4.x
|   |-- cp-rhel/                        #     Confluent Platform on RHEL (Ansible)
|   |-- cpc/                            #     Confluent Private Cloud
|   +-- _template/                      #     Scaffold for new scenarios
|
|-- modules/                            # <-- EXTENDED: Shared Terraform modules
|   |-- topic/                          #     Existing topic governance (unchanged interface)
|   |-- schema/                         #     Extracted: schema registration + compat enforcement
|   |-- rbac/                           #     Extracted: role binding patterns
|   |-- observability/                  #     NEW: per-provider dashboard/alert templates
|   |-- networking/                     #     NEW: PrivateLink/PSC/VPC peering per cloud
|   +-- flink/                          #     NEW: Flink deployment abstraction
|
|-- dr/                                 # <-- NEW: Pluggable DR framework
|   |-- cli/                            #     Unified failover CLI (fsi-dr)
|   |-- backends/                       #     Backend adapters
|   |   |-- cluster-linking/            #     CC Cluster Linking adapter
|   |   |-- mirrormaker2/              #     MM2 adapter (CFK/CP)
|   |   +-- mrc/                        #     MRC observer-promotion adapter (CP)
|   |-- state/                          #     State machine for failover steps
|   +-- tests/                          #     DR framework integration tests
|
|-- reference/                          # <-- EXISTING: Reference implementations (unchanged)
|-- schemas/                            # <-- EXISTING: Avro schema library (unchanged)
|-- docs/                               # <-- EXISTING: ADRs, guides (extended)
+-- scripts/                            # <-- DEPRECATED: Migrated into dr/ framework
```

### Component Boundaries

| Component | Responsibility | Communicates With | IaC Tool |
|-----------|---------------|-------------------|----------|
| **Scenario Directory** | Self-contained deployment for one model. Contains provider config, backend config, environment tfvars, topic declarations, and a README | Consumes shared modules; invokes DR CLI | Terraform (CC/CPC), Helm+Kustomize (CFK), Ansible (CP-RHEL) |
| **Shared Topic Module** | Topic creation, schema registration, RBAC, DR mirror. Unchanged interface from current `modules/topic/` | Called by every scenario's Terraform root | Terraform |
| **Shared Schema Module** | Schema registration, compatibility enforcement, metadata tagging. Extracted from topic module for scenarios where schema lifecycle differs (CFK uses operator CRDs) | Called by topic module or directly by CFK scenario | Terraform or CFK SchemaRegistry CRD |
| **Shared RBAC Module** | Role bindings for producers, consumers, consumer groups, SR subjects. Extracted so CFK/CP can map to native RBAC (LDAP, RBAC via MDS) | Called by topic module or directly by scenario | Terraform (CC), MDS API (CP), CFK RBAC CRD |
| **Observability Module** | Dashboard templates and alert rules per provider (Dynatrace, Datadog, Splunk, Prometheus, New Relic, Instana) | Reads topic metadata to generate dashboards; outputs to provider-specific format | Terraform (for managed providers), JSON/YAML templates |
| **Networking Module** | PrivateLink (Azure), PrivateLink (AWS), PSC (GCP), VPC peering. One sub-module per cloud | Called by CC scenarios only; CFK/CP manage networking via OCP/RHEL network config | Terraform |
| **Flink Module** | Flink cluster/pool deployment per scenario type | CC Flink pools (Terraform), CFK Flink operator (Helm), standalone Flink (Ansible) | Varies by scenario |
| **DR Framework** | Pluggable CLI that orchestrates failover/failback with backend-specific adapters | Reads scenario config for cluster details; calls Confluent CLI, kubectl, or Ansible | Bash/Python CLI |
| **DR State Machine** | Tracks failover step progression, validates preconditions, enables rollback | Used by DR CLI internally; persists state to local file or Consul KV | Embedded in DR CLI |
| **Reference Implementations** | Working producer/consumer/connect examples | Reads from schemas/; connects to any scenario's cluster | Maven/dotnet SDK |

### Data Flow

**Scenario Selection and Provisioning:**

```
Team picks scenario (e.g., cc-aws/)
  --> copies _template/ or clones scenario README
  --> fills in scenario .tfvars (cluster IDs, API keys, regions)
  --> adds topic declarations referencing shared modules
  --> PR --> CI validates (per-scenario pipeline) --> merge --> apply
```

**Topic Creation (CC scenarios -- Terraform):**

```
scenarios/cc-aws/topics/fraud.tf
  --> module "fraud_alert" { source = "../../modules/topic" ... }
    --> modules/topic/main.tf creates:
      1. confluent_kafka_topic (East cluster)
      2. confluent_schema (Avro, SR)
      3. confluent_subject_config (compatibility)
      4. confluent_role_binding (producer/consumer/SR RBAC)
      5. confluent_kafka_mirror_topic (DR cluster, if enabled)
```

**Topic Creation (CFK scenario -- Operator CRDs):**

```
scenarios/cfk-openshift/topics/fraud.yaml
  --> KafkaTopic CRD applied via kubectl/Helm
  --> SchemaRegistry CRD for schema registration
  --> ConfluentRolebinding CRD for RBAC via MDS
  --> MirrorMaker2 CRD for DR mirroring (if MM2 backend)
```

**Topic Creation (CP-RHEL scenario -- Ansible + Terraform hybrid):**

```
scenarios/cp-rhel/inventory/hosts.yml  (Ansible inventory)
scenarios/cp-rhel/topics/fraud.tf      (Terraform via CP provider or confluent-kafka-rest)
  --> Ansible deploys/configures brokers
  --> Terraform creates topics against the CP cluster REST endpoint
  --> MRC configured via server.properties (observer broker role)
```

**DR Failover Flow (Unified):**

```
fsi-dr failover --scenario cc-aws --dry-run
  --> DR CLI reads scenarios/cc-aws/dr-config.yaml
  --> Selects backend: cluster-linking (based on scenario type)
  --> State machine: HEALTHY --> PRE_CHECK --> MIRROR_PROMOTE --> SERVICE_FLIP --> VALIDATE --> COMPLETE
  --> Each step: precondition check --> execute --> postcondition check
  --> On failure: rollback to last good state

fsi-dr failover --scenario cfk-openshift
  --> Selects backend: mirrormaker2
  --> State machine: same steps, different implementation per step

fsi-dr failover --scenario cp-rhel --backend mrc
  --> Selects backend: mrc
  --> Observer promotion: promote observer broker to leader
  --> RPO=0 (synchronous replication)
```

## Scenario Directory Layout

Each scenario is self-contained. A team can `git clone`, navigate to their scenario, fill in config, and deploy.

### CC Scenario (AWS/Azure/GCP)

```
scenarios/cc-aws/
|-- README.md                           # Quick start for this scenario
|-- main.tf                             # Terraform root: provider, backend, locals
|-- variables.tf                        # Scenario-specific variables
|-- terraform.tfvars.example            # Template for team to fill in
|-- outputs.tf                          # Cluster endpoints, topic list
|-- dr-config.yaml                      # DR framework configuration
|-- topics/                             # Topic declarations (one .tf per domain)
|   |-- example-topics.tf              # Reference module calls
|   +-- _template.tf                    # Copy-paste template for new topics
|-- networking/                         # Cloud-specific networking
|   +-- privatelink.tf                  # AWS PrivateLink configuration
|-- flink/                              # Flink pool configuration
|   +-- flink-pool.tf                   # CC Flink compute pool
+-- observability/                      # Observability templates for this scenario
    +-- dashboards/                     # Provider-specific dashboards
```

### CFK-on-OpenShift Scenario

```
scenarios/cfk-openshift/
|-- README.md
|-- kustomization.yaml                  # Kustomize root
|-- base/                               # Base CFK operator manifests
|   |-- namespace.yaml
|   |-- confluent-platform.yaml         # KafkaCluster, SchemaRegistry, Connect CRDs
|   |-- rbac.yaml                       # ConfluentRolebinding CRDs
|   +-- mirrormaker2.yaml              # MM2 CRD for DR
|-- overlays/                           # Environment-specific overlays
|   |-- dev/
|   |-- staging/
|   +-- prod/
|-- topics/                             # KafkaTopic CRDs
|   +-- example-topics.yaml
|-- dr-config.yaml                      # DR framework config (backend: mirrormaker2)
|-- flink/                              # Flink on K8s
|   +-- flink-kubernetes-operator.yaml
+-- values/                             # Helm values files
    +-- confluent-platform-values.yaml
```

### CP-on-RHEL Scenario

```
scenarios/cp-rhel/
|-- README.md
|-- ansible/                            # Ansible playbooks for CP deployment
|   |-- playbook-deploy.yml
|   |-- playbook-upgrade.yml
|   |-- inventory/
|   |   +-- hosts.yml.example
|   +-- roles/
|       |-- broker/
|       |-- schema-registry/
|       |-- connect/
|       +-- control-center/
|-- terraform/                          # Terraform for topic/schema/RBAC against CP REST
|   |-- main.tf
|   |-- topics/
|   +-- terraform.tfvars.example
|-- dr-config.yaml                      # DR framework config (backend: mrc)
|-- mrc/                                # MRC-specific configuration
|   |-- server-observer.properties      # Observer broker config
|   +-- promotion-playbook.yml          # Ansible playbook for observer promotion
+-- flink/
    +-- flink-standalone.yml            # Ansible role for standalone Flink
```

## Shared vs Scenario-Specific Modules

| Asset | Shared or Scenario-Specific | Rationale |
|-------|----------------------------|-----------|
| Topic module (Terraform) | **Shared** (`modules/topic/`) | Same governance logic everywhere; CC scenarios call it directly |
| Schema module | **Shared** (`modules/schema/`) | Extracted from topic module; CFK maps it to SchemaRegistry CRD |
| RBAC module | **Shared** (`modules/rbac/`) | CC uses Confluent RBAC; CFK/CP map to MDS; logic is shared |
| Observability templates | **Shared** (`modules/observability/`) | Dashboard JSON/YAML per provider; scenario selects its provider |
| Networking (PrivateLink/PSC) | **Scenario-specific** | Fundamentally different per cloud; no useful abstraction |
| Flink deployment | **Scenario-specific** | CC Flink pool vs K8s operator vs standalone -- no common interface |
| DR backend adapters | **Shared** (`dr/backends/`) | Pluggable; scenario config selects the backend |
| DR config | **Scenario-specific** (`dr-config.yaml`) | Cluster IDs, endpoints, backend selection per scenario |
| Ansible roles | **Scenario-specific** (CP-RHEL only) | Only CP-RHEL uses Ansible |
| Helm values | **Scenario-specific** (CFK only) | Only CFK uses Helm/Kustomize |
| Topic declarations | **Scenario-specific** | Each deployment has its own cluster; topic .tf/.yaml files live in scenario |

## DR Framework Architecture

### Pluggable Backend Design

```
dr/
|-- cli/
|   |-- fsi-dr.sh                       # Entry point (or Python CLI via Click)
|   |-- commands/
|   |   |-- failover.sh
|   |   |-- failback.sh
|   |   |-- status.sh
|   |   +-- dry-run.sh
|   +-- lib/
|       |-- state-machine.sh            # Step progression, validation, rollback
|       |-- config-loader.sh            # Reads dr-config.yaml
|       +-- logging.sh                  # Audit-trail logging
|
|-- backends/
|   |-- cluster-linking/
|   |   |-- failover.sh                 # Promote mirror topics via Confluent CLI
|   |   |-- failback.sh                 # Restore primary, re-mirror
|   |   |-- status.sh                   # Mirror lag, link health
|   |   +-- validate.sh                 # Pre/post-condition checks
|   |
|   |-- mirrormaker2/
|   |   |-- failover.sh                 # Stop MM2, promote consumer offsets
|   |   |-- failback.sh                 # Reverse MM2 direction
|   |   |-- status.sh                   # MM2 connector status, lag
|   |   +-- validate.sh
|   |
|   +-- mrc/
|       |-- failover.sh                 # Promote observer to leader
|       |-- failback.sh                 # Demote back to observer
|       |-- status.sh                   # Observer sync status, ISR
|       +-- validate.sh
|
+-- state/
    |-- state-machine.sh                # States: HEALTHY -> PRE_CHECK -> EXECUTING -> VALIDATING -> COMPLETE
    |-- state-file.json                 # Persisted state between steps
    +-- rollback-registry.sh            # Undo actions for each completed step
```

### DR Config Schema (per scenario)

```yaml
# scenarios/cc-aws/dr-config.yaml
dr:
  backend: cluster-linking              # cluster-linking | mirrormaker2 | mrc
  primary:
    cluster_id: lkc-xxxxx
    bootstrap: pkc-xxxxx.us-east-1.aws.confluent.cloud:9092
    region: us-east-1
  secondary:
    cluster_id: lkc-yyyyy
    bootstrap: pkc-yyyyy.us-west-2.aws.confluent.cloud:9092
    region: us-west-2
  cluster_link:
    name: cluster-link-bidir-prod-dr
  service_discovery:
    provider: consul                    # consul | dns | none
    consul_addr: http://consul.internal:8500
    kv_key: fsi/kafka/active-region
  validation:
    mirror_lag_threshold_seconds: 30
    post_failover_produce_test: true
  rollback:
    enabled: true
    auto_rollback_on_failure: false     # Manual confirmation required
```

### MRC 2.5-Cluster Pattern

The "2.5-cluster" pattern for RPO=0 uses Confluent Platform Multi-Region Clusters with an observer broker:

```
+-------------------+     sync repl     +-------------------+
|   Region East     | <===============> |   Region West     |
|   (Leader)        |                   |   (Follower)      |
|   2+ brokers      |                   |   2+ brokers      |
+-------------------+                   +-------------------+
         |                                       |
         |          async repl                   |
         +-----------> +-------------------+ <---+
                       |   Region Central  |
                       |   (Observer)      |
                       |   1 broker        |
                       +-------------------+
                       "the 0.5 cluster"
```

- **East (Leader):** Serves all reads and writes. ISR includes West followers.
- **West (Follower):** Synchronous replicas. Can be promoted to leader on East failure. RPO=0.
- **Central (Observer):** Asynchronous replica. Serves local reads only (read replicas for latency-sensitive consumers). Can be promoted to leader if both East and West fail (RPO > 0 in this case).
- **Promotion sequence:** Observer promotion via `kafka-configs --alter --replica-placement` or Ansible automation.

**When to use MRC vs Cluster Linking:**

| Criterion | Cluster Linking | MRC 2.5-Cluster |
|-----------|----------------|-----------------|
| Deployment model | CC (any cloud) | CP-RHEL or CFK only |
| RPO | > 0 (seconds to minutes) | 0 (synchronous) |
| RTO | Minutes (scripted failover) | Seconds (automatic promotion) |
| Operational complexity | Low (managed by CC) | High (self-managed brokers) |
| Cost | Two CC clusters | 5+ brokers across 3 regions |
| Latency impact | None (async) | Cross-region write latency (sync repl) |
| Use when | RPO ~2h is acceptable; CC deployment | RPO=0 required by compliance; CP deployment |

## Patterns to Follow

### Pattern 1: Scenario-as-Root

**What:** Each scenario directory is a complete, deployable root. Not a fragment that needs assembly.

**When:** Always. Every scenario must be independently deployable.

**Example:**
```bash
# Team adopting CC on AWS:
cd scenarios/cc-aws/
cp terraform.tfvars.example terraform.tfvars
# Fill in cluster IDs, API keys
terraform init
terraform plan
terraform apply
```

**Why:** Lower barrier to entry. Teams browse `scenarios/`, pick their deployment model, and start. No CLI scaffolding, no code generation, no assembly required.

### Pattern 2: Module Interface Stability

**What:** Shared modules expose a stable interface. Scenarios adapt to the module, not the reverse.

**When:** When adding new deployment models. The topic module interface (domain, application, version, entity, sla_tier, etc.) does not change per scenario.

**Example:**
```hcl
# scenarios/cc-aws/topics/fraud.tf -- same module call as cc-azure
module "fraud_alert" {
  source      = "../../../modules/topic"
  domain      = "fraud"
  application = "detection"
  # ... identical interface regardless of scenario
}
```

### Pattern 3: Config-Driven DR Backend Selection

**What:** The DR framework reads `dr-config.yaml` from the scenario directory and dispatches to the correct backend adapter. No code changes needed to switch backends.

**When:** All DR operations.

**Example:**
```bash
# Same CLI, different backend selected by config:
fsi-dr failover --scenario cc-aws          # uses cluster-linking backend
fsi-dr failover --scenario cfk-openshift   # uses mirrormaker2 backend
fsi-dr failover --scenario cp-rhel         # uses mrc backend
```

### Pattern 4: Governance Parity Across Deployment Models

**What:** Core governance (topic naming, schema compatibility, RBAC, SLA tiers) is identical regardless of deployment model. The implementation differs (Terraform vs CRD vs Ansible) but the policy is the same.

**When:** Always. This is the fundamental constraint.

**Enforcement:**
- Shared CI validation pipeline that checks topic naming regex, schema JSON, and SLA tier rules regardless of scenario
- Shared schema library (`schemas/`) consumed by all scenarios
- Governance tests that verify the same policies are applied across scenarios

## Anti-Patterns to Avoid

### Anti-Pattern 1: Abstraction Over Deployment Tools

**What:** Creating a single abstraction that hides whether Terraform, Helm, or Ansible is being used.

**Why bad:** The deployment models are fundamentally different. Terraform provisions CC resources via API. Helm applies CFK operator CRDs. Ansible configures RHEL systemd services. Abstracting over these creates a leaky abstraction that obscures debugging and limits capability.

**Instead:** Let each scenario use its native tool. Share governance policy (naming, schemas, SLA tiers), not deployment mechanics.

### Anti-Pattern 2: Single Environment Directory for All Scenarios

**What:** Keeping the `environments/prod/` pattern and trying to parameterize it for CC-AWS, CC-Azure, CFK, etc.

**Why bad:** CFK does not use Terraform providers. CP-RHEL uses Ansible. Forcing everything into `environments/{env}/` creates conditionals that make the codebase unmaintainable.

**Instead:** Scenario directories. Each scenario owns its deployment tool configuration.

### Anti-Pattern 3: Shared State Across Scenarios

**What:** Using a single Terraform state file for multiple scenarios.

**Why bad:** One scenario's failure blocks all others. State lock contention. Blast radius is the entire platform.

**Instead:** Each scenario has its own Terraform state backend (or Helm release, or Ansible inventory). Complete isolation.

### Anti-Pattern 4: DR Framework Hardcoded to One Backend

**What:** Building the DR CLI to only support Cluster Linking, then bolting on MM2 and MRC later.

**Why bad:** The initial design bakes in Cluster Linking assumptions (mirror topics, cluster link names) that do not translate to MM2 (connectors, consumer group offsets) or MRC (observer brokers, replica placement).

**Instead:** Define the state machine and step interface first. Each backend implements the same steps with different mechanics.

## Suggested Build Order

Build order is driven by dependencies and incremental value delivery.

```
Phase 1: Scenario Scaffolding + CC Migration
  |-- Create scenarios/ directory structure
  |-- Migrate environments/prod/ --> scenarios/cc-azure/ (backward-compatible)
  |-- Create scenarios/cc-aws/ and scenarios/cc-gcp/ (clone + adapt)
  |-- Create scenarios/_template/
  |-- Update CI/CD for per-scenario pipelines
  |
  Dependencies: None (extends existing)
  Value: Multi-cloud CC support; teams can pick their cloud

Phase 2: Shared Module Extraction
  |-- Extract modules/schema/ from modules/topic/ (keep topic as facade)
  |-- Extract modules/rbac/ from modules/topic/
  |-- Create modules/networking/ with per-cloud sub-modules
  |-- Ensure modules/topic/ still works unchanged (backward compat)
  |
  Dependencies: Phase 1 (scenarios exist to consume modules)
  Value: Modules reusable across CC and CFK/CP scenarios

Phase 3: DR Framework (Cluster Linking backend first)
  |-- Build dr/cli/ with state machine and config loader
  |-- Implement dr/backends/cluster-linking/ (migrate from scripts/)
  |-- Add dry-run, rollback, audit logging
  |-- Wire into scenarios/cc-*/dr-config.yaml
  |-- Deprecate scripts/ (keep as symlinks temporarily)
  |
  Dependencies: Phase 1 (scenario config to read)
  Value: Automated, auditable DR for CC deployments

Phase 4: CFK-on-OpenShift Scenario
  |-- Create scenarios/cfk-openshift/ with Kustomize structure
  |-- Map shared governance to CFK CRDs (KafkaTopic, SchemaRegistry, RBAC)
  |-- Implement dr/backends/mirrormaker2/
  |-- Flink on K8s via Flink Kubernetes Operator
  |
  Dependencies: Phase 2 (shared modules for governance parity), Phase 3 (DR framework interface)
  Value: OpenShift deployment path for on-prem FSIs

Phase 5: CP-on-RHEL Scenario + MRC
  |-- Create scenarios/cp-rhel/ with Ansible roles
  |-- Implement MRC 2.5-cluster configuration
  |-- Implement dr/backends/mrc/ (observer promotion)
  |-- Standalone Flink deployment via Ansible
  |
  Dependencies: Phase 3 (DR framework), Phase 4 (MM2 backend validates plugin interface)
  Value: RPO=0 path for compliance-critical FSIs

Phase 6: Observability + Flink + CPC
  |-- Create modules/observability/ with per-provider templates
  |-- Create modules/flink/ with per-scenario adapters
  |-- Create scenarios/cpc/ (Confluent Private Cloud)
  |-- Cross-scenario governance test suite
  |
  Dependencies: Phases 1-5 (all scenarios exist)
  Value: Complete platform coverage
```

## Scalability Considerations

| Concern | 5 Scenarios | 20 Scenarios | 50+ Topics per Scenario |
|---------|-------------|--------------|------------------------|
| CI/CD pipeline time | Per-scenario pipelines, parallel execution | Matrix builds; only run changed scenarios | Terraform plan time scales linearly with topics; partition into domain .tf files |
| Module versioning | Pin shared modules by git ref or tag | Mandatory versioning; breaking changes gated by semver | N/A (modules are per-topic, not per-scenario) |
| DR framework testing | Test each backend manually | Automated DR drill per scenario on schedule | DR operates on all topics in cluster; no per-topic scaling issue |
| State management | One state file per scenario | One state per scenario; terraform workspaces for env tiers | Split state by domain if > 100 topics (state file size) |
| Schema registry | Single SR per CC environment | SR per environment; schema context for CFK/CP | Subject count scales; use schema contexts to namespace |

## Sources

- Codebase analysis: `modules/topic/main.tf`, `environments/prod/main.tf`, `scripts/mirror-failover.sh`
- ADR-003 (Consul service discovery), ADR-004 (on-prem Connect), ADR-005 (Cluster Linking over MRC)
- `.env.example` configuration structure
- `docs/cloud-providers.md` (Azure/AWS/GCP differences)
- `.planning/PROJECT.md` (requirements and constraints)
- `.planning/codebase/CONCERNS.md` (14 documented concerns)
- Confluent documentation for MRC, CFK operator, Cluster Linking (training data, MEDIUM confidence)
- Flink Kubernetes Operator architecture (training data, LOW confidence -- verify operator CRD versions against current Confluent docs)

**Confidence notes:**
- Scenario directory structure: HIGH confidence (driven by codebase evidence and stated requirements)
- DR framework state machine design: MEDIUM confidence (standard pattern, not verified against specific Confluent CLI behavior changes)
- MRC 2.5-cluster topology: MEDIUM confidence (well-documented Confluent pattern, but observer promotion automation specifics should be verified against current CP docs)
- CFK CRD mappings: LOW confidence (CFK operator evolves rapidly; verify CRD schema versions against CFK 2.x docs before implementation)
- Flink Kubernetes Operator: LOW confidence (verify current operator version and CRD compatibility with CFK)

---

*Architecture research: 2026-03-21*

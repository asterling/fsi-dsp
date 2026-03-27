# Phase 8: CFK on OpenShift - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md -- this log preserves the alternatives considered.

**Date:** 2026-03-27
**Phase:** 08-cfk-on-openshift
**Areas discussed:** Scenario Structure, MM2 DR Adapter, Flink K8s Operator, RBAC & Auth Model

---

## Scenario Structure

### Q1: Infrastructure Definition Format

| Option | Description | Selected |
|--------|-------------|----------|
| Helm values | Operator installed via Helm, infrastructure defined as values overrides. Follows CFK's native deployment model. Easier upgrades. | ✓ |
| Raw YAML manifests | CRD YAML files applied with oc/kubectl. More transparent, easier to review in PRs. Requires manual operator lifecycle. | |
| Kustomize overlays | Base manifests + environment-specific overlays. GitOps-friendly, good for multi-env. Adds tooling dependency. | |
| You decide | Claude picks the best approach based on CFK docs and OpenShift conventions | |

**User's choice:** Helm values
**Notes:** None

### Q2: Operator Installation Method

| Option | Description | Selected |
|--------|-------------|----------|
| OLM (OperatorHub) | OpenShift-native. Auto-updates, approval gates, catalog integration. Standard for OCP 4.x operators. CFK is available in OperatorHub. | |
| Helm chart direct | More control over versions, no OLM dependency. Simpler for air-gapped or restricted environments. Matches Flink operator install. | |
| Document both | README covers OLM as primary path with Helm as alternative for restricted environments. Manifests work with either. | ✓ |

**User's choice:** Document both
**Notes:** None

### Q3: Directory Structure

| Option | Description | Selected |
|--------|-------------|----------|
| scenarios/cfk-openshift/ | Consistent with cc-aws/, cc-azure/, cc-gcp/ pattern. Contains Helm values, CRD manifests, README, quickstart. Teams browse scenarios/ to pick deployment model. | |
| scenarios/cfk-openshift/ + modules/cfk-topic/ | Scenario dir for cluster setup, separate shared module for CFK KafkaTopic CRDs (parallel to modules/topic/ for CC). Enables governance parity via shared module pattern. | |
| You decide | Claude picks based on what makes governance parity cleanest | ✓ |

**User's choice:** You decide
**Notes:** None

### Q4: Topic Governance Enforcement

| Option | Description | Selected |
|--------|-------------|----------|
| Helm values templates | SLA tier maps to topic config in values.yaml. Operator applies naming convention. Simpler, but less CI enforcement than Terraform. | |
| CI validation + Helm | Helm values define topics, CI pipeline validates naming/SLA/schema parity before merge (reusing existing Python validators). Belt-and-suspenders. | ✓ |
| You decide | Claude picks best approach that matches existing CI validation from Phase 1 | |

**User's choice:** CI validation + Helm
**Notes:** None

---

## MM2 DR Adapter

### Q1: Topic Naming Policy

| Option | Description | Selected |
|--------|-------------|----------|
| Prefix-based (default) | Keep MM2 default source prefix. Consumers on DR cluster read from prefixed topics. Simpler MM2 config, but consumers need awareness of prefix. | ✓ |
| IdentityReplicationPolicy | Configure MM2 to replicate with identical topic names (no prefix). Matches Cluster Linking behavior. Requires careful config to avoid replication loops. | |
| You decide | Claude picks based on what achieves closest parity with Cluster Linking failover behavior | |

**User's choice:** Prefix-based (default)
**Notes:** None

### Q2: Failover Sequence

| Option | Description | Selected |
|--------|-------------|----------|
| Stop replication + flip | Failover = stop MM2 connectors + flip Consul to DR. Topics already writable on DR. Simple, matches the spirit of the 6-step process. | ✓ |
| Stop + consumer offset sync | Stop MM2 connectors + sync consumer offsets from source to DR + flip Consul. Ensures consumers resume from correct position. More complex but less data re-processing. | |
| You decide | Claude designs the MM2 failover sequence to best match the existing 6-step pattern | |

**User's choice:** Stop replication + flip
**Notes:** None

### Q3: MM2 Deployment Model

| Option | Description | Selected |
|--------|-------------|----------|
| CFK Connect cluster | MM2 runs as connectors inside the CFK-managed Connect cluster. Reuses existing Connect infrastructure. Simpler but shares resources. | |
| Dedicated MM2 CRD | Separate KafkaMirrorMaker2 CRD via CFK operator. Dedicated resources, independent lifecycle. CFK natively supports this CRD. | ✓ |
| You decide | Claude picks based on CFK best practices and operational isolation | |

**User's choice:** Dedicated MM2 CRD
**Notes:** None

### Q4: Mirror Lag Monitoring

| Option | Description | Selected |
|--------|-------------|----------|
| JMX via kubectl exec | Shell into the MM2 pod and query JMX metrics for replication lag. Works without external tooling but requires kubectl/oc access. | |
| Prometheus endpoint | MM2 exposes JMX metrics via Prometheus exporter. Query Prometheus API for lag data. Requires Prometheus to be running. | |
| You decide | Claude picks based on what integrates best with the existing fsi-dr status command pattern | ✓ |

**User's choice:** You decide
**Notes:** None

---

## Flink K8s Operator

### Q1: Installation Method

| Option | Description | Selected |
|--------|-------------|----------|
| Separate Helm chart | Flink K8s Operator installed independently via its own Helm chart. Decoupled lifecycle from CFK operator. | |
| Bundled in scenario | Flink operator Helm values included in the CFK scenario directory as separate values file. Single scenario = complete platform. | ✓ |
| You decide | Claude picks based on operator lifecycle best practices on OpenShift | |

**User's choice:** Bundled in scenario
**Notes:** None

### Q2: SR Integration Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Operator + example jobs | Include FlinkDeployment CRD examples matching Phase 6 SQL templates with Avro format connector pointing to CFK SR. Full reference. | ✓ |
| Operator only | Install the operator and document how to create FlinkDeployment CRDs. Teams build their own job definitions. Lighter scope. | |
| You decide | Claude decides scope based on Phase 6 parity and success criteria (FLINK-02) | |

**User's choice:** Operator + example jobs
**Notes:** None

### Q3: Metrics Export

| Option | Description | Selected |
|--------|-------------|----------|
| JMX exporter sidecar | Flink pods get a JMX exporter sidecar that exposes Prometheus metrics. Matches JMX exporter stubs in observability/ dirs. | ✓ |
| Native Prometheus reporter | Flink's built-in Prometheus metrics reporter. No sidecar needed, lighter footprint. | |
| You decide | Claude picks based on what integrates with existing observability templates from Phase 5 | |

**User's choice:** JMX exporter sidecar
**Notes:** None

---

## RBAC & Auth Model

### Q1: Authentication Mechanism

| Option | Description | Selected |
|--------|-------------|----------|
| mTLS (certificates) | Client certificates for authentication. CFK operator manages cert generation via cert-manager. Strong security, common in FSI. | ✓ |
| SASL/PLAIN + LDAP | Username/password backed by LDAP/Active Directory. Familiar to enterprise teams. Requires LDAP infrastructure. | |
| SASL/SCRAM | Salted password hashes stored in ZooKeeper/KRaft. No external identity provider needed. Good for air-gapped. | |
| You decide | Claude picks based on FSI best practices and OpenShift conventions | |

**User's choice:** mTLS (certificates)
**Notes:** None

### Q2: Authorization Model

| Option | Description | Selected |
|--------|-------------|----------|
| Kafka ACLs | Standard Apache Kafka ACLs. Simpler, no MDS dependency. ACL entries in CFK CRDs map to DeveloperRead/DeveloperWrite patterns. | |
| MDS (Confluent RBAC) | Confluent Metadata Service for centralized role bindings. Closest parity to CC RBAC. Requires MDS deployment + LDAP. | |
| Document both | ACLs as default (simpler), MDS as advanced option for teams needing CC-equivalent RBAC. README covers both paths. | ✓ |
| You decide | Claude picks based on governance parity requirements and operational complexity trade-offs | |

**User's choice:** Document both
**Notes:** None

### Q3: Certificate Management

| Option | Description | Selected |
|--------|-------------|----------|
| Prerequisite | Document cert-manager as a required prerequisite. Most OpenShift clusters already have it. Keeps scenario focused on CFK. | ✓ |
| Include in scenario | Bundle cert-manager Helm install in the scenario. Self-contained, but adds dependency management. | |
| You decide | Claude picks based on OpenShift conventions and the self-contained scenario pattern | |

**User's choice:** Prerequisite
**Notes:** None

### Q4: Access Control Parity

| Option | Description | Selected |
|--------|-------------|----------|
| ACL templates in values | Helm values include ACL template entries mapping to producer=DeveloperWrite / consumer=DeveloperRead pattern. CI validates ACL parity. | ✓ |
| CFK RolebindingCRD | Use CFK's ConfluentRolebinding CRDs to define RBAC (requires MDS). Most direct CC parity but heavier dependency. | |
| You decide | Claude designs the approach that best achieves parity with CC RBAC pattern | |

**User's choice:** ACL templates in values
**Notes:** None

---

## Claude's Discretion

- Scenario directory internal organization
- MM2 mirror lag data collection method
- MM2 failback sequence design
- FlinkDeployment CRD structure
- CI validator extensions for CFK
- Consumer offset handling during MM2 failover

## Deferred Ideas

None -- discussion stayed within phase scope

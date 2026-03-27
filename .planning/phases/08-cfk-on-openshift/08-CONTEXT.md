# Phase 8: CFK on OpenShift - Context

**Gathered:** 2026-03-27
**Status:** Ready for planning

<domain>
## Phase Boundary

Deploy a fully governed Kafka environment on OpenShift using CFK operator manifests -- with identical governance to CC scenarios (topic naming, schema compatibility, RBAC patterns, SLA-tier defaults), MirrorMaker 2 DR adapter integrated into the existing `fsi-dr` CLI, and Flink Kubernetes Operator deployment with SR integration and JMX metrics export. This phase does NOT cover MRC/RPO=0 (Phase 9), FIPS compliance (Phase 9), or Ansible/systemd deployment (Phase 9).

</domain>

<decisions>
## Implementation Decisions

### Scenario Structure
- **D-01:** CFK scenario uses Helm values files to configure the CFK operator. Infrastructure defined as values overrides, not raw YAML manifests.
- **D-02:** CFK operator installation documented with two paths: OLM (OperatorHub) as primary for standard OpenShift, Helm chart as alternative for air-gapped or restricted environments. Manifests work with either.
- **D-03:** Scenario directory at `scenarios/cfk-openshift/` following existing pattern. Internal structure is Claude's discretion (likely Helm values + CI validators).
- **D-04:** Topic governance parity via CI validation + Helm: Helm values define KafkaTopic CRDs with SLA-tier mappings, CI pipeline validates naming/SLA/schema parity before merge (reusing existing Python validators from Phase 1).

### MM2 DR Adapter
- **D-05:** MM2 uses default prefix-based topic naming (e.g., `east.corebanking.core.v1.account-transaction`). Consumers on DR cluster read from prefixed topics.
- **D-06:** MM2 failover sequence: stop MM2 connectors + flip Consul to DR. DR topics are already writable (no mirror promotion needed). Matches the spirit of the existing 6-step process.
- **D-07:** MM2 deployed via dedicated KafkaMirrorMaker2 CRD (CFK operator), not as connectors inside the Connect cluster. Independent lifecycle and dedicated resources.
- **D-08:** MM2 mirror lag monitoring approach is Claude's discretion. Must integrate with existing `fsi-dr status` command pattern and use the same SLA-tier thresholds from ADR-008.

### Flink Kubernetes Operator
- **D-09:** Flink Kubernetes Operator bundled in the CFK scenario directory as a separate Helm values file. Single scenario = complete platform (Kafka + SR + Connect + MM2 + Flink).
- **D-10:** Scenario includes example FlinkDeployment CRDs that match Phase 6 SQL templates (tumbling window, stream-table join, filter-route) with Avro format connector pointing to CFK Schema Registry. Full reference for parity with CC Flink.
- **D-11:** Flink job metrics exported via JMX exporter sidecar on Flink pods. Matches the JMX exporter stubs already in `observability/` directories from Phase 5.

### RBAC & Auth Model
- **D-12:** CFK scenario uses mTLS (certificates) for Kafka broker authentication. CFK operator manages cert generation via cert-manager integration.
- **D-13:** cert-manager is a documented prerequisite, not bundled in the scenario. Most OpenShift clusters already have it.
- **D-14:** RBAC authorization documented with two paths: Kafka ACLs as default (simpler, no MDS dependency), MDS (Confluent RBAC) as advanced option for teams needing CC-equivalent role bindings. README covers both.
- **D-15:** Governance parity for producer/consumer access control via ACL templates in Helm values. Templates map to the same producer=DeveloperWrite / consumer=DeveloperRead pattern from CC scenarios. CI validates ACL parity.

### Claude's Discretion
- Scenario directory internal structure (Helm chart organization, namespace layout)
- MM2 mirror lag data collection method (JMX via kubectl exec vs Prometheus endpoint vs other)
- MM2 failback sequence details (reverse of failover with appropriate modifications)
- FlinkDeployment CRD structure and Avro format connector configuration details
- How CI validators are extended to cover CFK YAML/Helm in addition to Terraform
- Whether to create a shared CFK topic template or inline topic definitions in values
- Consumer offset handling during MM2 failover (sync strategy)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### DR Architecture & Backend Dispatch
- `docs/adr/008-dr-tier-classification.md` -- SLA tier RPO/RTO targets, mirror lag thresholds, DR backend selection per deployment model (MM2 for CFK)
- `docs/adr/005-cluster-linking-over-mrc.md` -- Cluster Linking design for CC; MM2 is the CFK equivalent
- `docs/adr/003-consul-service-discovery.md` -- Consul KV for atomic endpoint failover (same pattern for CFK)
- `scripts/fsi-dr.sh` -- Existing DR CLI with pluggable backend dispatch. MM2 backend stubbed at line 534. Implement `mm2_preflight`, `mm2_failover_mirrors`, `mm2_failback_mirrors`, `mm2_get_mirror_lag`, `mm2_get_mirror_status` functions.
- `docs/dr-runbook.md` -- DR runbook to extend with MM2-specific steps and CFK context

### Existing Scenario Pattern
- `scenarios/cc-aws/` -- Reference CC scenario directory structure (README, main.tf, variables, example-topics, quickstart)
- `scenarios/cc-azure/` -- Same pattern, Azure-specific backend
- `scenarios/cc-gcp/` -- Same pattern, GCP-specific backend

### Governance & Validation
- `modules/topic/variables.tf` -- Topic naming regex, SLA tier enum, validation patterns to replicate for CFK KafkaTopic CRDs
- `ci/scripts/validate-schemas.py` -- Schema validation to extend for CFK YAML-defined topics
- `ci/scripts/check-overrides.sh` -- Override detection to extend for CFK context

### Observability (JMX exporter stubs)
- `observability/grafana/jmx-exporter-stub.yaml` -- JMX exporter config template for CFK/CP deployments
- `observability/dynatrace/jmx-exporter-stub.json` -- Dynatrace JMX config template
- `observability/datadog/jmx-exporter-stub.yaml` -- Datadog JMX config template

### Phase 4 Context (DR CLI design)
- `.planning/phases/04-dr-automation-framework/04-CONTEXT.md` -- DR CLI design decisions, failover sequence, state file, backend dispatch pattern

### Phase 6 Context (Flink patterns)
- `modules/flink/` -- CC Flink Terraform module (compute pool + SQL statements). CFK Flink uses FlinkDeployment CRDs instead.
- `reference/flink-sql/` -- SQL templates (tumbling window, stream-table join, filter-route, DLQ) to port as FlinkDeployment examples

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `scripts/fsi-dr.sh`: DR CLI with backend dispatch at `init_backend()` (line 525). MM2 case at line 534 returns error. Phase 8 fills in the 5 backend functions.
- `ci/scripts/validate-schemas.py`: Python schema validator. Can be extended to parse CFK KafkaTopic YAML for naming/SLA validation.
- `ci/scripts/check-overrides.sh`: Override detection. Extend to check CFK Helm values for override patterns.
- `observability/*/jmx-exporter-stub.*`: JMX exporter configs per provider. Ready to be activated for CFK Kafka and Flink pods.
- `reference/flink-sql/*.sql`: SQL templates from Phase 6. Port logic to FlinkDeployment CRDs with Avro format connector.

### Established Patterns
- Scenario directories: `scenarios/{model}/` with README, IaC files, variable examples, quickstart
- CI validation: Python + shell validators run on PR, block on failure
- SLA tier as configuration multiplier: tier drives partition count, retention, compatibility, DR thresholds
- `set -euo pipefail` + env var configuration for all Bash scripts
- Pluggable backend via function dispatch (DR CLI pattern)

### Integration Points
- `scenarios/cfk-openshift/` -- New scenario directory with Helm values for CFK operator + Flink operator
- `scripts/fsi-dr.sh` -- Extend with mm2_* backend functions
- `.github/workflows/` -- CI workflows may need CFK-specific validation path
- `docs/dr-runbook.md` -- Extend with MM2 failover/failback procedures
- `.env.example` -- May need CFK-specific environment variables section

</code_context>

<specifics>
## Specific Ideas

- The CFK scenario should be a "complete platform in a box" -- Kafka, SR, Connect, MM2, and Flink all deployable from one scenario directory.
- MM2 failover is simpler than Cluster Linking (no mirror promotion needed) -- stop replication, flip Consul, done.
- Flink examples should directly parallel the Phase 6 CC Flink SQL templates so teams can see equivalent patterns across deployment models.
- mTLS + ACLs as the default auth path keeps the scenario accessible without requiring LDAP/MDS infrastructure, while documenting MDS as the upgrade path for full CC RBAC parity.

</specifics>

<deferred>
## Deferred Ideas

None -- discussion stayed within phase scope

</deferred>

---

*Phase: 08-cfk-on-openshift*
*Context gathered: 2026-03-27*

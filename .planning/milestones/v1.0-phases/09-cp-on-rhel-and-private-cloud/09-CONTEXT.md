# Phase 9: CP on RHEL and Private Cloud - Context

**Gathered:** 2026-03-27
**Status:** Ready for planning

<domain>
## Phase Boundary

Deploy Confluent Platform on bare-metal RHEL via Ansible roles (Kafka, SR, Connect, MDS RBAC, Flink standalone) and Confluent Private Cloud via Terraform with shared module governance. Includes MRC with automatic observer promotion (2.5-cluster pattern) for RPO=0, FIPS 140-2 compliance automation for CP on RHEL and CFK on FIPS-enabled OpenShift, and standalone Flink with systemd service management and SR integration.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion
All implementation choices are at Claude's discretion -- pure infrastructure phase.

Key areas for Claude to decide:
- Ansible role structure and variable organization for CP deployment
- Private Cloud Terraform module structure (extending shared governance modules)
- MRC observer promotion automation approach (Confluent CLI-based or API-based)
- FIPS compliance validation method (JVM flag checks, TLS library validation, OpenShift FIPS mode detection)
- Standalone Flink systemd service file structure and Ansible role organization
- How MRC backend integrates with existing fsi-dr.sh dispatch pattern (new `mrc_*` functions)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Existing Scenario Patterns
- `scenarios/cc-aws/` -- CC Terraform scenario directory (README, main.tf, variables, quickstart)
- `scenarios/cfk-openshift/` -- CFK operator scenario directory (Helm values, KafkaTopic CRDs, Flink operator)

### DR Architecture
- `docs/adr/008-dr-tier-classification.md` -- SLA tier RPO/RTO targets; MRC for RPO=0 critical workloads
- `docs/adr/005-cluster-linking-over-mrc.md` -- CL vs MRC design rationale; MRC is the RPO=0 path for CP
- `scripts/fsi-dr.sh` -- DR CLI with backend dispatch; CL and MM2 backends implemented; MRC backend needed

### Governance & Validation
- `modules/topic/variables.tf` -- Topic naming regex, SLA tier enum, validation patterns
- `ci/scripts/c4e-precheck.py` -- C4E validation with YAML topic parsing (from Phase 8)
- `ci/scripts/validate-schemas.py` -- Schema validation pipeline

### Observability
- `observability/*/jmx-exporter-stub.*` -- JMX exporter configs per provider for CP/standalone deployments

### Phase 4 Context (DR CLI design)
- `.planning/phases/04-dr-automation-framework/04-CONTEXT.md` -- DR CLI design decisions, backend dispatch pattern

### Phase 6 Context (Flink patterns)
- `modules/flink/` -- CC Flink Terraform module; standalone Flink uses Ansible + systemd instead
- `reference/flink-sql/` -- SQL templates to reference for standalone Flink examples

### Phase 8 Context (CFK patterns)
- `.planning/phases/08-cfk-on-openshift/08-CONTEXT.md` -- CFK scenario decisions; Phase 9 builds the RHEL/Private Cloud equivalents

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `scripts/fsi-dr.sh`: DR CLI with CL and MM2 backends. MRC backend needs `mrc_preflight`, `mrc_failover_mirrors`, `mrc_failback_mirrors`, `mrc_get_mirror_lag`, `mrc_get_mirror_status` functions.
- `ci/scripts/c4e-precheck.py`: C4E validator with Terraform and CFK YAML parsing. Extend for Ansible variable validation.
- `modules/topic/`: Shared governance module. Private Cloud scenario can consume this directly via Terraform.
- `observability/*/jmx-exporter-stub.*`: JMX exporter configs ready for CP deployments.
- `tests/dr/test-fsi-dr-mm2.sh`: MM2 test pattern to replicate for MRC backend tests.

### Established Patterns
- Scenario directories: `scenarios/{model}/` with README, IaC files, variable examples, quickstart
- DR backend dispatch: function-name pattern (`{backend}_preflight`, `{backend}_failover_mirrors`, etc.)
- SLA tier as configuration multiplier across all deployment models
- CI validation: Python + shell validators on PR

### Integration Points
- `scenarios/cp-rhel/` -- New Ansible-based scenario directory
- `scenarios/private-cloud/` -- New Terraform-based scenario directory consuming shared modules
- `scripts/fsi-dr.sh` -- Extend with mrc_* backend functions
- `.env.example` -- CP/Private Cloud environment variables
- `docs/dr-runbook.md` -- Extend with MRC failover/failback procedures

</code_context>

<specifics>
## Specific Ideas

No specific requirements -- infrastructure phase

</specifics>

<deferred>
## Deferred Ideas

None -- discussion stayed within phase scope

</deferred>

---

*Phase: 09-cp-on-rhel-and-private-cloud*
*Context gathered: 2026-03-27*

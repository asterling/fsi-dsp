# Phase 14: CFK on OpenShift Governance - Context

**Gathered:** 2026-04-10
**Status:** Ready for planning
**Mode:** Auto-generated (infrastructure phase — discuss skipped)

<domain>
## Phase Boundary

Operators can deploy the CFK operator and apply governed Kafka custom resources on OpenShift using Ansible -- with the same SLA-tier defaults and governance rules as CP REST API roles. This phase bridges the existing CFK manifests (v1.0 Phase 8) with the Ansible governance framework (v2.0 Phases 10-12) by adding kubernetes.core-based roles that deploy CFK via Helm and generate KafkaTopic CRDs from the same CPTopic YAML definitions used by the cp_topic role.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion
All implementation choices are at Claude's discretion -- pure infrastructure phase. Use ROADMAP phase goal, success criteria, and codebase conventions to guide decisions. Key patterns to follow:
- Role structure matches cp_connect, cp_dr_mm2 patterns (defaults, meta, tasks, molecule, tests)
- kubernetes.core.helm for operator deployment, kubernetes.core.k8s for CR application
- Readiness gates use kubernetes.core.k8s_info to poll CRD status before proceeding
- CPTopic YAML consumption reuses the pattern from cp_topic role
- SLA-tier defaults derive from existing ansible/vars/sla_tiers.yml

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- ansible/vars/sla_tiers.yml -- SLA tier governance constants
- ansible/vars/naming_rules.yml -- Topic naming validation rules
- ansible/plugins/filter/fsi_governance.py -- Filter plugin for topic name assembly
- scenarios/cfk-openshift/ -- Existing CFK manifests and Helm values from v1.0 Phase 8
- ansible/roles/cp_topic/ -- Topic lifecycle role (REST API pattern, CPTopic YAML consumption)
- ansible/roles/cp_connect/ -- Connector deployment role (structural reference)

### Established Patterns
- Role structure: defaults/main.yml, meta/main.yml, tasks/{main,check,action}.yml, molecule/default/
- Test structure: tests/ansible/test_cp_{role}.py with TestRoleStructure, TestFQCNCompliance, etc.
- FQCN enforcement, task name casing, ansible-lint shared profile compliance
- check_mode routing in main.yml with GET-only audit in check.yml

### Integration Points
- ansible/playbooks/site.yml -- Orchestration entry point (will need CFK play)
- ansible/inventories/ -- May need CFK-specific inventory group
- .github/workflows/ansible-ci.yml -- CI pipeline for Ansible content

</code_context>

<specifics>
## Specific Ideas

No specific requirements -- infrastructure phase. Refer to ROADMAP phase description and success criteria.

</specifics>

<deferred>
## Deferred Ideas

None -- discuss phase skipped.

</deferred>

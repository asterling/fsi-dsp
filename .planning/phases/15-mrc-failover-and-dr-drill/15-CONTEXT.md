# Phase 15: MRC Failover and DR Drill - Context

**Gathered:** 2026-04-10
**Status:** Ready for planning
**Mode:** Auto-generated (infrastructure phase — discuss skipped)

<domain>
## Phase Boundary

Operators can execute MRC observer promotion for RPO=0 scenarios and run quarterly DR drills that produce compliance evidence reports -- building on proven MM2 playbooks from Phase 13. This phase adds two capabilities: (1) MRC-specific failover via Confluent CLI observer promotion, and (2) a full-cycle DR drill playbook that orchestrates failover → validate → failback → validate and generates a timestamped compliance report for regulatory submission.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion
All implementation choices are at Claude's discretion -- pure infrastructure phase. Key patterns to follow:
- Role structure matches cp_dr_mm2 patterns (defaults, meta, tasks, molecule, tests)
- MRC observer promotion uses Confluent CLI (`confluent kafka replica promote`) not REST API
- DR drill playbook composes existing MM2 failover/failback roles with MRC role
- Compliance report is a structured Markdown/YAML file with timestamps, step results, and pass/fail verdict
- Reuse sla_tiers.yml, consul_flip.yml patterns from Phase 13

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- ansible/roles/cp_dr_mm2/ -- MM2 DR role (failover, failback, check mode, validation)
- ansible/vars/sla_tiers.yml -- SLA tier governance constants + mirror lag thresholds
- ansible/roles/cp_dr_mm2/tasks/consul_flip.yml -- Consul KV region flip
- ansible/roles/cp_dr_mm2/tasks/validate_state.yml -- State validation pattern
- ansible/roles/cp_dr_mm2/tasks/connector_pause.yml -- Connector lifecycle
- scripts/fsi-dr.sh -- Existing shell DR framework with MRC backend reference

### Established Patterns
- TDD: tests first (RED), then implementation (GREEN)
- FQCN enforcement, task name casing, ansible-lint shared profile
- check_mode routing with GET-only audit log
- ansible.builtin.command for CLI invocations with changed_when/failed_when

### Integration Points
- ansible/playbooks/site.yml -- May need DR drill play
- .github/workflows/ansible-ci.yml -- CI pipeline molecule matrix

</code_context>

<specifics>
## Specific Ideas

No specific requirements -- infrastructure phase. Refer to ROADMAP phase description and success criteria.

</specifics>

<deferred>
## Deferred Ideas

None -- discuss phase skipped.

</deferred>

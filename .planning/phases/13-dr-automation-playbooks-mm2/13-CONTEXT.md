# Phase 13: DR Automation Playbooks (MM2) - Context

**Gathered:** 2026-04-09
**Status:** Ready for planning
**Mode:** Auto-generated (infrastructure phase — discuss skipped)

<domain>
## Phase Boundary

Operators can execute MM2 failover and failback operations via Ansible playbooks with dry-run mode, state validation, and audit-ready output -- replacing manual shell script execution.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion
All implementation choices are at Claude's discretion — pure infrastructure phase. Use ROADMAP phase goal, success criteria, and codebase conventions to guide decisions.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `scripts/mirror-failover.sh` — existing shell-based DR failover (6-step sequence)
- `scripts/dr/` — fsi-dr CLI framework with backend dispatch and state management
- `ansible/roles/cp_topic/`, `cp_schema/`, `cp_rbac/`, `cp_connect/` — established Ansible role patterns
- `ansible/vars/sla_tiers.yml` — SLA-tier thresholds for mirror lag alerting
- `tests/ansible/conftest.py` — shared pytest fixtures for Ansible role testing

### Established Patterns
- `ansible.builtin.uri` for all REST API operations (not custom modules)
- `failed_when: false` for error collection (ansible-lint shared profile)
- Task names start with uppercase, Jinja at end only
- PUT for idempotent create-or-update operations
- Molecule default scenario for each role

### Integration Points
- Phase 11 governance roles (cp_topic, cp_schema, cp_rbac) — may be invoked post-failover
- Phase 12 site.yml orchestration — DR playbooks are standalone but follow same patterns
- `ansible/vars/sla_tiers.yml` — mirror lag thresholds per SLA tier

</code_context>

<specifics>
## Specific Ideas

No specific requirements — infrastructure phase. Refer to ROADMAP phase description and success criteria.

</specifics>

<deferred>
## Deferred Ideas

None — discuss phase skipped.

</deferred>

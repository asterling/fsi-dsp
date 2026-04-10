# Phase 10: Ansible Foundation and Governance Scaffolding - Context

**Gathered:** 2026-04-07
**Status:** Ready for planning
**Mode:** Auto-generated (infrastructure phase — discuss skipped)

<domain>
## Phase Boundary

The `ansible/` directory is fully scaffolded with pinned dependencies, shared governance constants that mirror Terraform, filter plugins, multi-environment inventories, and lint rules -- establishing the foundation every subsequent role depends on.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion
All implementation choices are at Claude's discretion — pure infrastructure phase with no user-facing behavior decisions. Use ROADMAP phase goal, success criteria, and codebase conventions to guide decisions.

Key constraints from success criteria:
- `requirements.yml` must pin cp-ansible 7.7.x and all required collections
- `sla_tiers.yml` must produce identical values to Terraform module locals
- `fsi_governance` filter plugin must match Terraform `{domain}.{application}.{version}.{entity}` regex
- `ansible-lint` must pass with zero violations
- Inventory skeletons for dev, staging, prod, dr environments

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Governance Source of Truth
- `modules/topic/main.tf` lines 35-103 — SLA-tier maps (compatibility, partitions, retention) that Ansible vars must mirror exactly
- `modules/topic/variables.tf` lines 8-16, 18-26, 28-36, 38-46 — Topic naming regex patterns (`^[a-z][a-z0-9-]{1,30}$` for domain/app, `^v[0-9]+$` for version, `^[a-z][a-z0-9-]{1,60}$` for entity)
- `modules/topic/variables.tf` lines 61-69 — SLA tier enum: critical, standard, best-effort, compliance

### Existing Ansible Patterns (cp-rhel scenario)
- `scenarios/cp-rhel/playbooks/deploy-cp.yml` — Existing playbook structure, cp-ansible role usage, tag patterns
- `scenarios/cp-rhel/inventory/hosts.yml.example` — Existing inventory structure with host groups (kafka_broker, schema_registry, kafka_connect, flink)
- `scenarios/cp-rhel/inventory/group_vars/` — Existing group_vars pattern
- `scenarios/cp-rhel/topics/*.yml` — CPTopic YAML format with governance labels (fsi.domain, fsi.sla-tier, etc.)
- `scenarios/cp-rhel/roles/flink_standalone/` — Existing custom role structure (defaults, tasks, templates, handlers)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `scenarios/cp-rhel/inventory/hosts.yml.example` — Multi-group inventory pattern (kafka_broker, schema_registry, kafka_connect, flink) that can inform the new `ansible/inventories/` structure
- `scenarios/cp-rhel/topics/*.yml` — CPTopic YAML definitions with governance labels that the filter plugin must parse
- `scenarios/cp-rhel/roles/flink_standalone/` — Role structure pattern (defaults, tasks, templates, handlers) to follow for new roles
- `scenarios/cp-rhel/playbooks/deploy-cp.yml` — Playbook patterns with preflight checks, cp-ansible collection usage, and tag-based execution

### Established Patterns
- Topic naming: `{domain}.{application}.{version}.{entity}` assembled in Terraform locals
- SLA tier derivation: critical→12 partitions/7d retention/FULL_TRANSITIVE, standard→6/3d/BACKWARD_TRANSITIVE, best-effort→3/1d/BACKWARD, compliance→12/configurable/FULL_TRANSITIVE
- cp-ansible collection `confluent.platform` used for component roles
- Preflight checks pattern: assert RHEL version, verify Java 17

### Integration Points
- New `ansible/` directory sits at repo root alongside `modules/`, `scenarios/`, `scripts/`
- Governance constants must stay in sync with `modules/topic/main.tf` locals
- CPTopic YAML format from `scenarios/cp-rhel/topics/` is consumed by future topic role (Phase 11)
- Filter plugins will be used by all subsequent Ansible roles (Phases 11-15)

</code_context>

<specifics>
## Specific Ideas

No specific requirements — infrastructure phase. Refer to ROADMAP phase description and success criteria.

</specifics>

<deferred>
## Deferred Ideas

None — infrastructure phase, discuss skipped.

</deferred>

---

*Phase: 10-ansible-foundation-and-governance-scaffolding*
*Context gathered: 2026-04-07*

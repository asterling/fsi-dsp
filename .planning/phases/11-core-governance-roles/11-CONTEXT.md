# Phase 11: Core Governance Roles - Context

**Gathered:** 2026-04-08
**Status:** Ready for planning

<domain>
## Phase Boundary

Operators can create topics, register schemas, and provision RBAC bindings on a Confluent Platform cluster using Ansible roles -- with identical governance rules to Terraform and full idempotency. Three standalone roles (cp_topic, cp_schema, cp_rbac) using ansible.builtin.uri for all CP REST API interactions.

</domain>

<decisions>
## Implementation Decisions

### Error Handling Strategy
- When processing multiple topics/schemas/bindings, collect all errors and report at end with summary (do not fail fast on first error) — matches Terraform's plan-all-then-apply pattern
- Transient API errors (503, connection timeout) get 3 retries with exponential backoff using uri module's native retry (`retries: 3, delay: 5, until: result.status == 200`)
- Check mode gathers current state via GET per resource individually (not bulk listing) — compare declared vs actual config, report diff

### Molecule Test Architecture
- Delegated driver with Python HTTP mock server — lightweight pytest fixture starts a mock CP API returning realistic responses (no Docker overhead, fast CI)
- Shared test fixtures in `tests/ansible/fixtures/` across all roles — mock API responses, sample CPTopic YAMLs (aligns with existing `tests/ansible/` from Phase 10)
- Idempotency verification = second converge reports zero `changed` tasks via molecule's built-in idempotence test

### Role Variable Interface
- Roles register output variables with results (`cp_topic_results`, `cp_schema_results`, `cp_rbac_results`) containing created/updated/failed counts for downstream orchestration (Phase 12 needs this)
- Schema role reuses existing `ci/scripts/validate-schemas.py` via command module (ASCHEMA-04) — avoids duplicating validation logic
- Roles accept both `cp_topics_dir` (YAML glob for CPTopic files, standard use per ATOPIC-03) and `cp_topics` list (inline variables for programmatic/orchestration use)

### Claude's Discretion
- Internal task ordering within roles (e.g., GET-before-POST sequence, token acquisition flow)
- Exact mock API response structures for molecule tests
- Variable naming within roles beyond the registered output variables

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Governance Source of Truth
- `modules/topic/main.tf` lines 35-103 — SLA-tier maps that Ansible governance constants mirror
- `modules/topic/variables.tf` lines 8-46 — Topic naming regex patterns
- `ansible/vars/sla_tiers.yml` — Ansible SLA tier constants (Phase 10 output)
- `ansible/vars/naming_rules.yml` — Ansible naming rules (Phase 10 output)
- `ansible/filter_plugins/fsi_governance.py` — Governance Jinja2 filters (Phase 10 output)

### CP REST API References
- Admin REST v3 for topic CRUD: `POST/GET/DELETE /kafka/v3/clusters/{id}/topics`
- Schema Registry REST API for schema CRUD: `POST/GET /subjects/{subject}/versions`
- MDS REST API for RBAC bindings: `POST/GET/DELETE /security/1.0/principals/{principal}/roles/{role}/bindings`

### Existing Patterns
- `scenarios/cp-rhel/topics/*.yml` — CPTopic YAML format consumed by the topic role
- `scenarios/cp-rhel/roles/flink_standalone/` — Role structure pattern (defaults, tasks, templates, handlers)
- `ci/scripts/validate-schemas.py` — Schema validation script reused by schema role

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ansible/filter_plugins/fsi_governance.py` — fsi_topic_name, fsi_sla_lookup, fsi_validate_topic_name filters
- `ansible/vars/sla_tiers.yml` — SLA tier governance constants matching Terraform
- `ansible/vars/naming_rules.yml` — Topic naming regex patterns matching Terraform
- `scenarios/cp-rhel/topics/*.yml` — 3 CPTopic YAML files (corebanking, fraud, compliance) as test input
- `ci/scripts/validate-schemas.py` — Schema structural validation for ASCHEMA-04
- `tests/ansible/conftest.py` — Shared test configuration from Phase 10

### Established Patterns
- ansible.builtin.uri for all REST API operations (decided in STATE.md)
- Standalone roles, not Galaxy collection (decided in STATE.md)
- SLA tier derivation: critical→12/7d/FULL_TRANSITIVE, standard→6/3d/BACKWARD_TRANSITIVE, best-effort→3/1d/BACKWARD
- Topic naming: {domain}.{application}.{version}.{entity} with dot separators
- CPTopic YAML format with apiVersion/kind/metadata/spec structure

### Integration Points
- Roles go in `ansible/roles/cp_topic/`, `ansible/roles/cp_schema/`, `ansible/roles/cp_rbac/`
- Roles import governance filters from `ansible/filter_plugins/` (path configured in ansible.cfg)
- Roles load governance constants from `ansible/vars/` via include_vars
- Phase 12 orchestration playbook will chain these roles together

</code_context>

<specifics>
## Specific Ideas

- CPTopic YAML files from `scenarios/cp-rhel/topics/` serve as both input format definition and test fixtures
- MDS token TTL is 15 minutes — role must track and refresh during long playbook runs (ARBAC-02)
- Topic deletion requires double confirmation: `state: absent` AND `confirm_deletion: true`, plus blocks critical/compliance tier deletion without override (ATOPIC-07)

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 11-core-governance-roles*
*Context gathered: 2026-04-08*

# Phase 1: Shared Governance Foundation - Context

**Gathered:** 2026-03-21
**Status:** Ready for planning

<domain>
## Phase Boundary

Codify governance primitives (topic naming, schema compatibility, RBAC patterns, SLA-tier defaults) in a shared module library and CI pipeline — before any new scenario directory is created. Refactor the existing `modules/topic/` into a shared library consumable by all deployment scenarios. Externalize hardcoded cluster config. Add schema CI validation. Write 3 ADRs.

</domain>

<decisions>
## Implementation Decisions

### Shared Module Library Structure
- **D-01:** Refactor existing `modules/topic/` into `modules/shared/` (or similar) that can be imported by any scenario directory via relative path or Terraform registry-style source
- **D-02:** The shared module interface stays: `domain`, `application`, `version`, `entity`, `sla_tier`, `owner_email`, `producer_sa`, `consumer_sa`, `pii_fields`, `data_classification` — extend, don't break
- **D-03:** SLA tier map extended with `compliance` tier (7-year retention, FULL_TRANSITIVE compat, 12 partitions) alongside existing critical/standard/best-effort
- **D-04:** Module outputs remain: topic_name, schema_subject, compatibility_mode, partition_count — used by downstream scenarios

### Externalized Cluster Configuration
- **D-05:** Replace hardcoded locals in `environments/prod/main.tf` (lines 33-55) with a `clusters.tfvars` pattern or `terraform_remote_state` data source
- **D-06:** Cluster metadata (IDs, REST endpoints, CRNs, bootstrap URLs) stored in a single config file per environment — not scattered across locals
- **D-07:** Existing `environments/prod/` directory migrates to `scenarios/cc-azure/` as first scenario (backward compat preserved)

### Schema CI Validation
- **D-08:** Add schema compatibility check to `.github/workflows/terraform-plan.yml` using SR REST API (`/compatibility/subjects/{subject}/versions/{version}`)
- **D-09:** Namespace validation enforces `org.fsi.{domain}.{application}.{entity}` pattern — CI rejects `.avsc` files that violate this
- **D-10:** `compatibility_override` blocked in CI unless PR description contains ADR or JIRA exception reference (regex match on PR body)
- **D-11:** Python validation script in CI for schema checks (already partially exists in plan workflow)

### Breaking Change Runbook
- **D-12:** Add "Breaking Change Runbook" section to existing `docs/schema-guide.md` — not a separate document
- **D-13:** Runbook covers: create versioned topic (v2), dual-write period, consumer migration, deprecate old topic, decommission

### ADRs
- **D-14:** ADR-006: OAuth vs API Keys — recommend OAuth/OAUTHBEARER for CC (Azure AD, AWS IAM), API keys as fallback for on-prem, include credential rotation guidance per model
- **D-15:** ADR-007: Topic Naming Rationale — document `{domain}.{application}.{version}.{entity}` with regex `^[a-z][a-z0-9-]{1,30}$` per segment, explain why dots as separators
- **D-16:** ADR-008: DR Tier Classification — map SLA tiers to RPO/RTO targets (critical: RPO <5min/RTO <15min, standard: RPO <2h/RTO <1h, best-effort: RPO <24h/RTO <4h, compliance: RPO=0 via MRC)

### Claude's Discretion
- Exact directory naming for shared modules (`modules/shared/` vs `modules/governance/` vs keeping `modules/topic/`)
- CI script language (Python vs bash for schema validation)
- Whether to use Terraform `test` blocks (1.6+) for validation or shell-based smoke tests
- ADR numbering continuation (006, 007, 008 vs different scheme)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Existing Topic Module (refactor source)
- `modules/topic/main.tf` — Current topic module with SLA-tier maps, schema registration, RBAC, DR mirror logic
- `modules/topic/variables.tf` — Variable definitions with naming validation regex, SLA tier enum, override options
- `modules/topic/outputs.tf` — Module outputs consumed by downstream

### Existing CI Pipeline (enhancement target)
- `.github/workflows/terraform-plan.yml` — Current CI with format check, naming validation, schema JSON validation, TF plan
- `.github/workflows/terraform-apply.yml` — Apply workflow triggered on merge to main

### Existing Environment (migration source)
- `environments/prod/main.tf` — Hardcoded cluster IDs (lines 33-55) that must be externalized
- `environments/prod/example-topics.tf` — Example module usage showing current interface
- `environments/prod/terraform.tfvars.example` — Current variable examples

### Schema Governance
- `docs/schema-guide.md` — Existing schema guide where breaking change runbook will be added
- `schemas/examples/` — Reference Avro schemas showing current namespace patterns
- `docs/adr/002-compatibility-by-tier.md` — Existing ADR on compatibility mode selection by SLA tier

### Architecture Decisions
- `docs/adr/001-avro-over-protobuf.md` — Avro as canonical format
- `docs/adr/003-consul-service-discovery.md` — Consul for endpoint failover
- `docs/adr/005-cluster-linking-over-mrc.md` — Cluster Linking for CC DR
- `docs/adr/000-template.md` — ADR template for new ADRs

### Research
- `.planning/research/ARCHITECTURE.md` — Scenario directory layout and shared module boundaries
- `.planning/research/PITFALLS.md` — Governance drift pitfall (Critical severity) and Terraform state divergence
- `.planning/codebase/CONCERNS.md` — 14 documented concerns, several addressed in this phase

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `modules/topic/main.tf`: Complete topic module with SLA-tier-based configuration multiplier pattern — this is the foundation to refactor, not rewrite
- `.github/workflows/terraform-plan.yml`: Existing CI pipeline with Python-based schema validation — extend with compatibility and namespace checks
- `docs/adr/000-template.md`: ADR template ready for new ADRs

### Established Patterns
- SLA tier as configuration multiplier: compatibility_map, partition_map, retention_map in locals — extend with compliance tier
- Topic naming regex: `^[a-z][a-z0-9-]{1,30}$` per segment — keep this pattern
- Schema metadata tags: owner, sla-tier, data-classification, domain, application, pii, pii-fields — extend, don't replace
- Terraform module interface: domain/application/version/entity + sla_tier + service accounts — backward compatible extension

### Integration Points
- `environments/prod/main.tf` → will become `scenarios/cc-azure/main.tf` (first scenario migration)
- `.github/workflows/terraform-plan.yml` → enhanced with schema CI validation steps
- `docs/schema-guide.md` → enhanced with breaking change runbook section
- `docs/adr/` → new ADRs 006, 007, 008 added

</code_context>

<specifics>
## Specific Ideas

- C4E philosophy: "Automation > Documentation. Golden Path > Gatekeeping. Community > Committee." — every governance check should make it easier to do the right thing than the wrong thing
- The shared module library is the architectural linchpin (research finding) — if governance drifts between scenarios, the platform delivers 3 separate platforms, not one
- Keep the existing CC-Azure module working throughout — this is a brownfield refactor, not a greenfield build

</specifics>

<deferred>
## Deferred Ideas

- Post-apply Terraform validation (IAC-10) — Phase 2 requirement
- Service account provisioning via IaC (RBAC-01) — Phase 3 requirement
- Credential rotation automation (RBAC-04) — Phase 3 requirement
- Compliance retention tier implementation in topic module (COMP-01) — Phase 3, but compliance map entry added here

</deferred>

---

*Phase: 01-shared-governance-foundation*
*Context gathered: 2026-03-21*

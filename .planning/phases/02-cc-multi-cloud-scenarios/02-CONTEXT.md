# Phase 2: CC Multi-Cloud Scenarios - Context

**Gathered:** 2026-03-22
**Status:** Ready for planning

<domain>
## Phase Boundary

Self-contained CC scenario directories for AWS and GCP with parameterized backends and post-apply validation. Operators can deploy a fully governed Kafka environment on CC-AWS or CC-GCP using a self-contained scenario directory — identical governance to existing CC-Azure. Migrate existing environments/prod/ to scenarios/cc-azure/ as first scenario.

</domain>

<decisions>
## Implementation Decisions

### Scenario Directory Structure
- **D-01:** Migrate `environments/prod/` to `scenarios/cc-azure/` as part of this phase — clean break, all three cloud providers live under `scenarios/` with identical structure
- **D-02:** Each scenario directory is fully standalone — own main.tf, variables.tf, example-topics.tf, clusters.auto.tfvars.example, terraform.tfvars.example, and README. No shared provider module or symlinks between scenarios
- **D-03:** Each scenario README includes a full quickstart walkthrough (prerequisites, setup, terraform init/plan/apply, verification) — self-contained with copy-pasteable commands specific to that cloud provider
- **D-04:** All three scenarios include the same 3 reference topics (corebanking, fraud, compliance) in example-topics.tf — proves governance parity: same module call, same result, different cloud

### Backend Parameterization
- **D-05:** Each scenario main.tf has its own native backend block — `azurerm` for Azure, `s3` for AWS, `gcs` for GCP. No partial configs or -backend-config flags
- **D-06:** Backend blocks use placeholder values with descriptive comments and .env variable references — matches existing pattern in environments/prod/main.tf
- **D-07:** AWS S3 backend uses DynamoDB for state locking (standard best practice)
- **D-08:** GCS backend uses native GCS locking (built-in)

### Post-Apply Validation
- **D-09:** Shell smoke script (not Terraform test blocks) for post-apply validation — runs after terraform apply, works with any Terraform version >= 1.5
- **D-10:** Script validates all 4 resource types: topic exists (Kafka REST API), schema registered (SR REST API), RBAC applied (role binding list), mirror created (mirror topic status)
- **D-11:** Single shared validation script (e.g., `scripts/validate-apply.sh`) that takes cluster endpoints as arguments — reused across all CC scenarios
- **D-12:** Human-readable output with PASS/FAIL per check and actionable error messages. Non-zero exit code on any failure
- **D-13:** Validation script runs automatically in CI after terraform apply — fails the workflow if any check fails

### CI Pipeline Changes
- **D-14:** Per-scenario workflows (terraform-plan-aws.yml, terraform-plan-gcp.yml, terraform-plan-azure.yml) rather than a single matrix workflow
- **D-15:** Reusable called workflow (.github/workflows/terraform-scenario.yml) for common plan/validate/apply logic — per-scenario workflows call it with scenario-specific inputs (directory, backend, secrets)
- **D-16:** Existing terraform-plan.yml and terraform-apply.yml migrated to call the reusable workflow for cc-azure scenario — all scenarios use the same pattern
- **D-17:** Post-apply validation integrated into the apply workflow — runs after terraform apply automatically

### Claude's Discretion
- Exact validation script implementation (curl vs confluent CLI for API calls)
- README template structure and section ordering
- Reusable workflow input parameter design
- Whether to add a scenarios/ top-level README listing available scenarios
- .env.example updates for multi-cloud support

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Existing Azure Scenario (migration source)
- `environments/prod/main.tf` — Current Terraform config with azurerm backend, provider config, externalized cluster variables
- `environments/prod/variables.tf` — Cluster configuration variables (IDs, endpoints, CRNs)
- `environments/prod/example-topics.tf` — 3 reference module calls (corebanking, fraud, compliance) showing current interface
- `environments/prod/clusters.auto.tfvars.example` — Externalized cluster metadata template
- `environments/prod/terraform.tfvars.example` — Variable values template for secrets

### Shared Topic Module (consumed by all scenarios)
- `modules/topic/main.tf` — Cloud-agnostic topic module with SLA-tier maps, schema registration, RBAC, DR mirror
- `modules/topic/variables.tf` — Module input schema (domain, app, version, entity, SLA tier, service accounts)
- `modules/topic/outputs.tf` — Module outputs consumed by downstream

### Cloud Provider Differences
- `docs/cloud-providers.md` — Azure vs AWS vs GCP differences (networking, auth, secrets, backend)

### CI Pipeline (enhancement target)
- `.github/workflows/terraform-plan.yml` — Current CI with format check, naming validation, schema validation, TF plan
- `.github/workflows/terraform-apply.yml` — Apply workflow triggered on merge to main

### Phase 1 Context (prior decisions)
- `.planning/phases/01-shared-governance-foundation/01-CONTEXT.md` — Phase 1 decisions including D-07 (environments/prod/ migrates to scenarios/cc-azure/)

### Architecture Decisions
- `docs/adr/006-oauth-vs-api-keys.md` — OAuth/OAUTHBEARER for CC, API keys as fallback (Phase 1)
- `docs/adr/007-topic-naming.md` — Topic naming convention with dot separators (Phase 1)
- `docs/adr/008-dr-tier-classification.md` — DR tier to RPO/RTO mapping (Phase 1)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `modules/topic/main.tf`: Cloud-agnostic topic module — already works for any CC deployment, just needs correct cluster endpoints and credentials passed in
- `environments/prod/main.tf`: Azure scenario template — direct migration source for scenarios/cc-azure/, adaptation source for cc-aws/ and cc-gcp/
- `environments/prod/variables.tf`: Cluster config variable declarations — reusable across all scenarios with same structure
- `environments/prod/clusters.auto.tfvars.example`: Externalized config template — same pattern applies per-cloud with different endpoint formats
- `.github/workflows/terraform-plan.yml`: CI pipeline — refactor target for reusable workflow extraction
- `docs/cloud-providers.md`: Provider comparison table — informs per-scenario backend, auth, and networking differences

### Established Patterns
- `clusters.auto.tfvars` pattern: Metadata in auto-loaded file, secrets in terraform.tfvars (gitignored) — apply to all scenarios
- Confluent provider `~> 2.0`: Same provider version across all scenarios
- `required_version >= 1.5`: Terraform version floor — no test blocks (1.6+), but shell scripts work fine
- Module source via relative path: `source = "../../modules/topic"` — path changes with new directory structure (`source = "../../modules/topic"` still works from `scenarios/cc-aws/`)

### Integration Points
- `environments/prod/` → `scenarios/cc-azure/` (migration, path changes in CI triggers)
- `.github/workflows/` → new reusable workflow + per-scenario caller workflows
- `scripts/` → new `validate-apply.sh` shared across scenarios
- `.env.example` → may need updates for multi-cloud variable references

</code_context>

<specifics>
## Specific Ideas

- Governance parity is the core value — same 3 example topics across all scenarios proves "same module call, same result, different cloud"
- Self-contained scenarios follow C4E philosophy: "Golden Path > Gatekeeping" — teams browse scenarios/ and pick their cloud, no hidden dependencies
- Full quickstart READMEs with copy-pasteable commands — operator should be able to go from zero to working cluster without jumping between docs
- Reusable CI workflow keeps DRY while per-scenario workflows give explicit GitHub Actions trigger paths

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 02-cc-multi-cloud-scenarios*
*Context gathered: 2026-03-22*

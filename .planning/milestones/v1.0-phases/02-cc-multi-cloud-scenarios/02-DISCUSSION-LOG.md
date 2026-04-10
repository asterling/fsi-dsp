# Phase 2: CC Multi-Cloud Scenarios - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-22
**Phase:** 02-cc-multi-cloud-scenarios
**Areas discussed:** Scenario directory structure, Backend parameterization, Post-apply validation, CI pipeline changes

---

## Scenario Directory Structure

### Q1: Migration of environments/prod/

| Option | Description | Selected |
|--------|-------------|----------|
| Migrate now | Move environments/prod/ to scenarios/cc-azure/ in this phase. All three cloud providers live under scenarios/ with identical structure. Clean break. | ✓ |
| Leave in place | Keep environments/prod/ as-is for Azure. Only create scenarios/cc-aws/ and scenarios/cc-gcp/. Migrate Azure later. | |
| Symlink bridge | Move to scenarios/cc-azure/ but create a symlink at environments/prod/ for backward compat during transition. | |

**User's choice:** Migrate now (Recommended)
**Notes:** None

### Q2: Standalone vs shared provider config

| Option | Description | Selected |
|--------|-------------|----------|
| Fully standalone | Each scenario has its own complete Terraform config. Copy-paste with provider-specific tweaks. Simpler to understand, no hidden dependencies. | ✓ |
| Shared provider module | Create a modules/provider/ or scenarios/_shared/ that each scenario sources. Reduces duplication but adds a dependency layer. | |
| You decide | Claude picks the best approach based on codebase patterns. | |

**User's choice:** Fully standalone (Recommended)
**Notes:** None

### Q3: README depth

| Option | Description | Selected |
|--------|-------------|----------|
| Full quickstart per scenario | Each README is self-contained with copy-pasteable commands specific to that cloud provider. No jumping between docs. | ✓ |
| Minimal + shared guide | Scenario READMEs link to a single docs/quickstart.md with provider-specific callouts. Less duplication in docs. | |
| You decide | Claude picks based on the C4E philosophy (Automation > Documentation, Golden Path). | |

**User's choice:** Full quickstart per scenario (Recommended)
**Notes:** None

### Q4: Example topics

| Option | Description | Selected |
|--------|-------------|----------|
| Same 3 topics | Identical example-topics.tf across all scenarios. Proves governance parity — same module call, same result, different cloud. | ✓ |
| Different examples | Vary example topics per cloud to showcase different use cases. Risk: harder to compare parity across scenarios. | |
| You decide | Claude chooses the best approach. | |

**User's choice:** Same 3 topics (Recommended)
**Notes:** None

---

## Backend Parameterization

### Q1: Backend switching mechanism

| Option | Description | Selected |
|--------|-------------|----------|
| Native backend per scenario | Each scenario main.tf has its own backend block: azurerm for Azure, s3 for AWS, gcs for GCP. Straightforward, no CLI tricks needed. | ✓ |
| Partial config + -backend-config | Use partial backend configuration in main.tf and pass provider-specific settings via -backend-config flag at terraform init time. | |
| Backend config files | Each scenario has a backend.hcl file and main.tf uses a generic backend block. Run terraform init -backend-config=backend.hcl. | |

**User's choice:** Native backend per scenario (Recommended)
**Notes:** None

### Q2: Backend placeholder style

| Option | Description | Selected |
|--------|-------------|----------|
| Placeholders with comments | Backend blocks use descriptive placeholder values with .env variable references in comments — matches current pattern. | ✓ |
| Backend config file | Move all backend values to a separate backend.tfvars or backend.hcl file per scenario. Keeps main.tf cleaner. | |
| You decide | Claude picks based on existing conventions. | |

**User's choice:** Placeholders with comments (Recommended)
**Notes:** None

### Q3: AWS state locking

| Option | Description | Selected |
|--------|-------------|----------|
| DynamoDB locking | Standard Terraform S3 backend with DynamoDB table for state locking. Well-documented, widely understood by AWS teams. | ✓ |
| S3 native locking | Terraform 1.10+ supports native S3 state locking without DynamoDB. Simpler, but requires recent Terraform version. | |
| You decide | Claude picks the best fit for the required_version >= 1.5 constraint. | |

**User's choice:** DynamoDB locking (Recommended)
**Notes:** None

---

## Post-Apply Validation

### Q1: Validation mechanism

| Option | Description | Selected |
|--------|-------------|----------|
| Shell smoke script | A validate.sh script that calls Confluent REST APIs to verify resources exist. Runs after terraform apply in CI. Works with any Terraform version. | ✓ |
| Terraform test blocks | Use Terraform 1.6+ test framework with .tftest.hcl files. Native to Terraform but requires 1.6+. | |
| Both | Terraform test blocks for structural validation + shell script for runtime verification. | |
| You decide | Claude picks based on the platform's Terraform version constraint (>= 1.5). | |

**User's choice:** Shell smoke script (Recommended)
**Notes:** None

### Q2: Validation checks

| Option | Description | Selected |
|--------|-------------|----------|
| All 4 checks | Topic exists (Kafka REST API), schema registered (SR REST API), RBAC applied (role binding list), mirror created (mirror topic status). Full IAC-10 coverage. | ✓ |
| Topic + schema only | Lighter check — just verify topic and schema exist via REST APIs. Skip RBAC and mirror checks. | |
| You decide | Claude determines the right set of checks based on IAC-10 requirements. | |

**User's choice:** All 4 checks (Recommended)
**Notes:** None

### Q3: Script scope

| Option | Description | Selected |
|--------|-------------|----------|
| Shared script | Single scripts/validate-apply.sh (or similar) that takes cluster endpoints as arguments. Reused across all CC scenarios. | ✓ |
| Per-scenario scripts | Each scenario has its own validate.sh. More self-contained but more to maintain. | |
| You decide | Claude picks the approach. | |

**User's choice:** Shared script (Recommended)
**Notes:** None

### Q4: Output format

| Option | Description | Selected |
|--------|-------------|----------|
| Human-readable with exit codes | Clear text output per check (PASS/FAIL with explanation), non-zero exit code on any failure. Actionable error messages for operators. | ✓ |
| JSON structured output | JSON output with pass/fail per check. Good for CI parsing but harder to read in terminal. | |
| Both formats | Default to human-readable, --json flag for structured output. Most flexible but more to implement. | |

**User's choice:** Human-readable with exit codes (Recommended)
**Notes:** None

---

## CI Pipeline Changes

### Q1: Pipeline discovery strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Matrix strategy | Single workflow with a matrix that iterates over changed scenario directories. | |
| Per-scenario workflows | Separate terraform-plan-aws.yml, terraform-plan-gcp.yml, terraform-plan-azure.yml. Explicit but more files to maintain. | ✓ |
| You decide | Claude picks the best CI approach for multi-scenario support. | |

**User's choice:** Per-scenario workflows
**Notes:** User chose per-scenario workflows over recommended matrix strategy

### Q2: Workflow reuse

| Option | Description | Selected |
|--------|-------------|----------|
| Reusable called workflow | Create .github/workflows/terraform-scenario.yml as a reusable workflow. Each per-scenario workflow calls it with scenario-specific inputs. DRY. | ✓ |
| Fully independent | Each scenario workflow is self-contained with no shared workflow dependency. More duplication but completely standalone. | |
| You decide | Claude picks the approach. | |

**User's choice:** Reusable called workflow (Recommended)
**Notes:** None

### Q3: Existing workflow migration

| Option | Description | Selected |
|--------|-------------|----------|
| Migrate existing | Refactor terraform-plan.yml and terraform-apply.yml to call the reusable workflow for cc-azure scenario. All scenarios use the same pattern. | ✓ |
| Keep existing + add new | Leave current workflows untouched. Only new cc-aws and cc-gcp workflows use the reusable pattern. | |
| You decide | Claude decides based on backward compatibility constraints. | |

**User's choice:** Migrate existing (Recommended)
**Notes:** None

### Q4: Post-apply validation in CI

| Option | Description | Selected |
|--------|-------------|----------|
| In CI after apply | Validation script runs automatically after terraform apply in the apply workflow. Fails the workflow if any check fails. | ✓ |
| Manual only | Validation script exists but is only run manually by operators. | |
| Both | Runs in CI by default. Operators can also run it manually for ad-hoc verification. | |

**User's choice:** In CI after apply (Recommended)
**Notes:** None

---

## Claude's Discretion

- Exact validation script implementation (curl vs confluent CLI)
- README template structure and section ordering
- Reusable workflow input parameter design
- Whether to add a scenarios/ top-level README
- .env.example updates for multi-cloud support

## Deferred Ideas

None — discussion stayed within phase scope

# Phase 2: CC Multi-Cloud Scenarios - Research

**Researched:** 2026-03-22
**Domain:** Terraform multi-cloud Confluent Cloud scenarios, GitHub Actions reusable workflows, post-apply validation
**Confidence:** HIGH

## Summary

Phase 2 extends the proven CC-Azure pattern to AWS and GCP by creating self-contained scenario directories under `scenarios/`. The core topic module (`modules/topic/`) is already cloud-agnostic -- it accepts cluster IDs, REST endpoints, and credentials as inputs. The only cloud-specific elements are: (1) the Terraform backend block (azurerm/s3/gcs), (2) endpoint URL patterns in `.auto.tfvars`, and (3) CI workflow triggers and secrets. This makes the task primarily structural -- cloning and adapting the existing `environments/prod/` pattern rather than building new functionality.

The main technical risks are: (a) the `environments/prod/` to `scenarios/cc-azure/` migration changing the module source path from `../../modules/topic` (which still works at the new depth), (b) backend blocks cannot be parameterized with variables in Terraform -- each scenario needs a literal backend block with placeholder values, and (c) the validation script must work with live Confluent Cloud APIs that require authentication, meaning it needs credentials passed via environment variables or CLI context.

**Primary recommendation:** Clone `environments/prod/` to `scenarios/cc-azure/`, then create `cc-aws/` and `cc-gcp/` by adapting only the backend block and `.auto.tfvars.example` endpoint patterns. Write a single shared `scripts/validate-apply.sh` that uses curl against Kafka REST API and Schema Registry REST API (not the Confluent CLI) for portability. Extract CI into a reusable workflow with per-scenario callers.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Migrate `environments/prod/` to `scenarios/cc-azure/` as part of this phase -- clean break, all three cloud providers live under `scenarios/` with identical structure
- **D-02:** Each scenario directory is fully standalone -- own main.tf, variables.tf, example-topics.tf, clusters.auto.tfvars.example, terraform.tfvars.example, and README. No shared provider module or symlinks between scenarios
- **D-03:** Each scenario README includes a full quickstart walkthrough (prerequisites, setup, terraform init/plan/apply, verification) -- self-contained with copy-pasteable commands specific to that cloud provider
- **D-04:** All three scenarios include the same 3 reference topics (corebanking, fraud, compliance) in example-topics.tf -- proves governance parity: same module call, same result, different cloud
- **D-05:** Each scenario main.tf has its own native backend block -- `azurerm` for Azure, `s3` for AWS, `gcs` for GCP. No partial configs or -backend-config flags
- **D-06:** Backend blocks use placeholder values with descriptive comments and .env variable references -- matches existing pattern in environments/prod/main.tf
- **D-07:** AWS S3 backend uses DynamoDB for state locking (standard best practice)
- **D-08:** GCS backend uses native GCS locking (built-in)
- **D-09:** Shell smoke script (not Terraform test blocks) for post-apply validation -- runs after terraform apply, works with any Terraform version >= 1.5
- **D-10:** Script validates all 4 resource types: topic exists (Kafka REST API), schema registered (SR REST API), RBAC applied (role binding list), mirror created (mirror topic status)
- **D-11:** Single shared validation script (e.g., `scripts/validate-apply.sh`) that takes cluster endpoints as arguments -- reused across all CC scenarios
- **D-12:** Human-readable output with PASS/FAIL per check and actionable error messages. Non-zero exit code on any failure
- **D-13:** Validation script runs automatically in CI after terraform apply -- fails the workflow if any check fails
- **D-14:** Per-scenario workflows (terraform-plan-aws.yml, terraform-plan-gcp.yml, terraform-plan-azure.yml) rather than a single matrix workflow
- **D-15:** Reusable called workflow (.github/workflows/terraform-scenario.yml) for common plan/validate/apply logic -- per-scenario workflows call it with scenario-specific inputs (directory, backend, secrets)
- **D-16:** Existing terraform-plan.yml and terraform-apply.yml migrated to call the reusable workflow for cc-azure scenario -- all scenarios use the same pattern
- **D-17:** Post-apply validation integrated into the apply workflow -- runs after terraform apply automatically

### Claude's Discretion
- Exact validation script implementation (curl vs confluent CLI for API calls)
- README template structure and section ordering
- Reusable workflow input parameter design
- Whether to add a scenarios/ top-level README listing available scenarios
- .env.example updates for multi-cloud support

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| IAC-01 | Operator can deploy CC on AWS with Terraform (topic, schema, RBAC, DR mirror) via self-contained scenario directory | S3 backend config pattern, AWS endpoint URLs in .auto.tfvars.example, same topic module call -- research confirms module is cloud-agnostic |
| IAC-02 | Operator can deploy CC on GCP with Terraform (topic, schema, RBAC, DR mirror) via self-contained scenario directory | GCS backend config pattern with built-in locking, GCP endpoint URLs in .auto.tfvars.example, same topic module call |
| IAC-06 | Each scenario directory is self-contained with README, IaC files, variable examples, and quickstart instructions | Scenario directory structure documented, README template pattern defined, per-cloud quickstart commands researched |
| IAC-08 | Terraform state backend is parameterized per cloud provider (S3 for AWS, Azure Blob for Azure, GCS for GCP) | Backend blocks are static in Terraform (cannot use variables), each scenario gets its own native backend block with placeholders |
| IAC-10 | Post-apply validation confirms topic exists, schema registered, RBAC applied, and mirror created | Confluent Cloud REST APIs documented for all 4 checks, shell script pattern with curl + jq verified |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Terraform | >= 1.5 (project floor) | Infrastructure as code | Already established in project; `required_version = ">= 1.5"` in modules |
| confluentinc/confluent provider | ~> 2.0 | Confluent Cloud resource management | Already pinned in project; latest is 2.64.0 but `~> 2.0` constraint handles upgrades |
| GitHub Actions | N/A | CI/CD pipeline | Already in use; reusable workflows via `workflow_call` are GA and stable |

### Supporting
| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| curl | System | REST API calls in validation script | Checking topic, schema, RBAC, mirror status post-apply |
| jq | System | JSON parsing in validation script | Parsing REST API responses |
| bash | System | Validation and glue scripts | All shell scripts use `set -euo pipefail` per project convention |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| curl for validation | Confluent CLI | CLI requires installation + auth context setup; curl is zero-dependency, works anywhere |
| DynamoDB for S3 locking (D-07) | S3 native locking (`use_lockfile`) | Native locking is newer (Terraform 1.10+) and still experimental; DynamoDB is battle-tested and matches decision D-07 |
| Per-scenario workflows (D-14) | Matrix workflow | Matrix is DRYer but obscures per-scenario trigger paths; per-scenario callers are explicit per user decision |

**Note on S3 locking:** The user locked D-07 as "DynamoDB for state locking." Terraform 1.10+ supports `use_lockfile = true` for S3-native locking (no DynamoDB needed), but this is still marked experimental and the user decision is explicit. Use DynamoDB as decided.

## Architecture Patterns

### Recommended Project Structure
```
scenarios/
  cc-azure/
    main.tf                       # azurerm backend + confluent provider
    variables.tf                  # Cluster config variables (same across all scenarios)
    example-topics.tf             # 3 reference topics (corebanking, fraud, compliance)
    clusters.auto.tfvars.example  # Azure endpoint placeholders
    terraform.tfvars.example      # Secret placeholders
    README.md                     # Azure-specific quickstart
  cc-aws/
    main.tf                       # s3 backend + confluent provider
    variables.tf                  # Same variable declarations
    example-topics.tf             # Same 3 reference topics
    clusters.auto.tfvars.example  # AWS endpoint placeholders
    terraform.tfvars.example      # Same secret placeholders
    README.md                     # AWS-specific quickstart
  cc-gcp/
    main.tf                       # gcs backend + confluent provider
    variables.tf                  # Same variable declarations
    example-topics.tf             # Same 3 reference topics
    clusters.auto.tfvars.example  # GCP endpoint placeholders
    terraform.tfvars.example      # Same secret placeholders
    README.md                     # GCP-specific quickstart
scripts/
  validate-apply.sh               # Shared post-apply validation (NEW)
  mirror-failover.sh              # Existing
  mirror-failback.sh              # Existing
  ...
.github/workflows/
  terraform-scenario.yml          # Reusable called workflow (NEW)
  terraform-plan-azure.yml        # Azure scenario caller (replaces terraform-plan.yml)
  terraform-plan-aws.yml          # AWS scenario caller (NEW)
  terraform-plan-gcp.yml          # GCP scenario caller (NEW)
  terraform-apply-azure.yml       # Azure scenario apply (replaces terraform-apply.yml)
  terraform-apply-aws.yml         # AWS scenario apply (NEW)
  terraform-apply-gcp.yml         # GCP scenario apply (NEW)
modules/topic/                    # Unchanged -- cloud-agnostic shared module
```

### Pattern 1: Scenario Directory as Self-Contained Deployment Unit
**What:** Each scenario directory contains everything needed to `terraform init && terraform apply` without referencing files outside of `scenarios/<name>/` and `modules/`.
**When to use:** Every CC deployment scenario.
**Key constraint:** Terraform backend blocks cannot use variables. The backend block must be a literal in `main.tf` with placeholder values. This is a Terraform language limitation, not a design choice.

**Example (cc-aws/main.tf):**
```hcl
terraform {
  required_version = ">= 1.5"
  required_providers {
    confluent = {
      source  = "confluentinc/confluent"
      version = "~> 2.0"
    }
  }

  # AWS S3 backend with DynamoDB locking
  backend "s3" {
    bucket         = "fsi-terraform-state"       # .env: TF_BACKEND_S3_BUCKET
    key            = "kafka-platform/prod/terraform.tfstate"
    region         = "us-east-1"                 # .env: TF_BACKEND_S3_REGION
    encrypt        = true
    dynamodb_table = "fsi-terraform-locks"       # .env: TF_BACKEND_DYNAMODB_TABLE
  }
}
```

### Pattern 2: Cloud-Specific Endpoint Patterns in .auto.tfvars.example
**What:** Each cloud provider has distinct endpoint URL patterns for Confluent Cloud clusters.
**When to use:** Populating `clusters.auto.tfvars.example` per scenario.

**Azure endpoints:**
```hcl
kafka_rest_endpoint    = "https://pkc-xxxxx.eastus2.azure.confluent.cloud:443"
sr_rest_endpoint       = "https://psrc-xxxxx.eastus2.azure.confluent.cloud"
dr_kafka_rest_endpoint = "https://pkc-yyyyy.westus2.azure.confluent.cloud:443"
```

**AWS endpoints:**
```hcl
kafka_rest_endpoint    = "https://pkc-xxxxx.us-east-1.aws.confluent.cloud:443"
sr_rest_endpoint       = "https://psrc-xxxxx.us-east-1.aws.confluent.cloud"
dr_kafka_rest_endpoint = "https://pkc-yyyyy.us-west-2.aws.confluent.cloud:443"
```

**GCP endpoints:**
```hcl
kafka_rest_endpoint    = "https://pkc-xxxxx.us-east1.gcp.confluent.cloud:443"
sr_rest_endpoint       = "https://psrc-xxxxx.us-east1.gcp.confluent.cloud"
dr_kafka_rest_endpoint = "https://pkc-yyyyy.us-west1.gcp.confluent.cloud:443"
```

### Pattern 3: Reusable CI Workflow with Per-Scenario Callers
**What:** A single `.github/workflows/terraform-scenario.yml` defines the common lint/validate/plan/apply/verify logic. Per-scenario caller workflows pass inputs (directory, environment) and secrets.
**When to use:** All CI/CD for scenario directories.

**Reusable workflow definition:**
```yaml
# .github/workflows/terraform-scenario.yml
name: Terraform Scenario
on:
  workflow_call:
    inputs:
      scenario-dir:
        required: true
        type: string
        description: "Path to scenario directory (e.g., scenarios/cc-aws)"
      environment-name:
        required: true
        type: string
        description: "GitHub environment for protection rules"
    secrets:
      CONFLUENT_CLOUD_API_KEY:
        required: true
      CONFLUENT_CLOUD_API_SECRET:
        required: true
      KAFKA_API_KEY:
        required: true
      KAFKA_API_SECRET:
        required: true
      SR_API_KEY:
        required: true
      SR_API_SECRET:
        required: true
      DR_KAFKA_API_KEY:
        required: true
      DR_KAFKA_API_SECRET:
        required: true
```

**Caller workflow example:**
```yaml
# .github/workflows/terraform-plan-aws.yml
name: "Plan: CC-AWS"
on:
  pull_request:
    paths:
      - 'scenarios/cc-aws/**'
      - 'modules/**'
      - 'schemas/**'
jobs:
  plan:
    uses: ./.github/workflows/terraform-scenario.yml
    with:
      scenario-dir: scenarios/cc-aws
      environment-name: fsi-cc-aws
    secrets: inherit
```

### Pattern 4: Post-Apply Validation via REST API
**What:** Shell script calls Confluent Cloud REST APIs to verify resources were created.
**When to use:** After every `terraform apply` in CI and during manual verification.

**Recommendation (Claude's Discretion):** Use `curl` with Basic Auth against REST APIs rather than `confluent` CLI. Rationale: (1) curl is available everywhere without installation, (2) no CLI login/context setup needed, (3) same credentials already available as TF_VAR env vars in CI, (4) REST responses are deterministic JSON parseable with jq.

**API endpoints for validation:**
| Check | Method | Endpoint | Success Condition |
|-------|--------|----------|-------------------|
| Topic exists | GET | `{kafka_rest}/kafka/v3/clusters/{cluster_id}/topics/{topic_name}` | HTTP 200 |
| Schema registered | GET | `{sr_rest}/subjects/{subject}-value/versions` | HTTP 200 + non-empty array |
| RBAC applied | GET | `{sr_rest}/subjects` (SR read implies RBAC) or CLI fallback | Subject visible with provided credentials |
| Mirror created | GET | `{dr_kafka_rest}/kafka/v3/clusters/{dr_cluster_id}/topics/{topic_name}` | HTTP 200 (topic exists on DR cluster) |

**RBAC validation note:** There is no public REST API endpoint for listing Confluent Cloud RBAC role bindings. The recommended approaches are:
1. **Implicit validation:** If the SR API key can read the subject, SR RBAC is working. If Kafka credentials can describe the topic, Kafka RBAC is working.
2. **CLI fallback:** Use `confluent iam rbac role-binding list --principal User:{sa} --role DeveloperWrite --cloud-cluster {cluster_id} -o json` if the CLI is available.
3. **Terraform state:** Parse `terraform output -json` for role binding resource IDs.

Recommendation: Use implicit validation (attempt to read topic/schema with service account credentials) as primary check, with Terraform output as secondary evidence. This avoids requiring separate RBAC API access.

### Anti-Patterns to Avoid
- **Shared backend configuration module:** Terraform backends cannot reference variables, modules, or data sources. Each scenario must have a literal backend block.
- **Symlinks between scenario directories:** Per D-02, scenarios must be fully standalone. Symlinks create hidden dependencies and break on some CI runners.
- **Matrix workflow for scenarios:** Per D-14, explicit per-scenario workflows. Matrix hides which scenario triggered and complicates secret management per environment.
- **Terraform test blocks for validation:** Per D-09, shell scripts work with Terraform >= 1.5. Test blocks require >= 1.6 and cannot validate external API state (only plan/apply assertions).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| State locking (AWS) | Custom locking mechanism | DynamoDB table (D-07) | Race conditions, split-brain state -- DynamoDB is the proven solution |
| State locking (GCP) | External locking | GCS built-in locking (D-08) | GCS handles this natively -- no additional infrastructure needed |
| JSON parsing in shell | grep/sed/awk on JSON | jq | Fragile regex on JSON breaks on whitespace, escaping, nesting |
| REST API auth encoding | Manual base64 | `echo -n "key:secret" \| base64` or curl `-u key:secret` | curl's `-u` flag handles Basic auth encoding automatically |
| CI workflow duplication | Copy-paste workflow steps | Reusable workflow with `workflow_call` (D-15) | 6+ workflows with identical logic is a maintenance nightmare |

**Key insight:** The topic module is already cloud-agnostic. The only cloud-specific work is backend blocks and endpoint URL patterns. Everything else (topic creation, schema registration, RBAC, DR mirror) works identically across all three clouds because Confluent Cloud's API is the same regardless of the underlying cloud provider.

## Common Pitfalls

### Pitfall 1: Backend Block Cannot Use Variables
**What goes wrong:** Attempting to parameterize the backend block with `var.bucket` or `local.backend_config` results in Terraform errors.
**Why it happens:** Terraform evaluates the backend block during `init`, before any variables, locals, or data sources are available.
**How to avoid:** Accept that each scenario needs a literal backend block. Use descriptive comments mapping to `.env` variable names for human reference.
**Warning signs:** "Variables not allowed" errors during `terraform init`.

### Pitfall 2: Module Source Path After Directory Move
**What goes wrong:** Moving from `environments/prod/` to `scenarios/cc-azure/` could break the module source path.
**Why it happens:** Module source is `../../modules/topic` -- relative path from the calling file.
**How to avoid:** Verify the relative path still resolves correctly. Both `environments/prod/` and `scenarios/cc-azure/` are two levels deep from the repo root, so `../../modules/topic` works from either location.
**Warning signs:** "Module not found" during `terraform init`.

### Pitfall 3: CI Workflow Path Triggers After Migration
**What goes wrong:** Existing CI triggers on `environments/**` no longer fire after content moves to `scenarios/`.
**Why it happens:** GitHub Actions path filters are literal -- `environments/**` does not match `scenarios/**`.
**How to avoid:** Update path triggers to `scenarios/cc-azure/**` in the replacement workflow. Keep `modules/**` and `schemas/**` triggers since those paths are unchanged.
**Warning signs:** PRs that change scenario files don't trigger CI checks.

### Pitfall 4: Secrets Scope in Reusable Workflows
**What goes wrong:** Secrets are not automatically inherited by called workflows. Validation script fails with authentication errors.
**Why it happens:** GitHub Actions requires either `secrets: inherit` or explicit secret passing in the `uses` block.
**How to avoid:** Use `secrets: inherit` in caller workflows (simplest) or explicitly declare all required secrets in the reusable workflow's `workflow_call.secrets` block.
**Warning signs:** Empty environment variables in called workflow steps.

### Pitfall 5: S3 Backend Requires AWS Credentials for terraform init
**What goes wrong:** `terraform init -backend=false` works fine for validation, but `terraform init` (with backend) fails without AWS credentials.
**Why it happens:** S3 backend needs AWS credentials even to read state metadata during init.
**How to avoid:** Ensure `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` are available as environment variables in CI during the init step. For lint/validate-only jobs, use `terraform init -backend=false`.
**Warning signs:** "NoCredentialProviders" error during `terraform init`.

### Pitfall 6: GCS Backend Authentication
**What goes wrong:** GCS backend requires Google Cloud credentials that may differ from Confluent Cloud credentials.
**Why it happens:** Terraform state is stored in GCS (Google infrastructure), while Confluent Cloud resources are managed via Confluent API.
**How to avoid:** Set `GOOGLE_CREDENTIALS` environment variable or use `gcloud auth application-default login` in CI. These are separate from `CONFLUENT_CLOUD_API_KEY`.
**Warning signs:** "google: could not find default credentials" during `terraform init`.

### Pitfall 7: Validation Script Must Handle Missing Resources Gracefully
**What goes wrong:** Validation script crashes or gives misleading output when a resource was not created (e.g., DR mirror disabled).
**Why it happens:** Not all topics have DR mirrors (controlled by `enable_dr_mirror` variable). Script assumes all 4 checks apply to every topic.
**How to avoid:** Make mirror validation conditional -- accept a flag or check Terraform output for `enable_dr_mirror`. Report "SKIP" instead of "FAIL" for intentionally disabled features.
**Warning signs:** False failures in validation for topics with `enable_dr_mirror = false`.

### Pitfall 8: Existing terraform-plan.yml References Hardcoded Path
**What goes wrong:** Existing `terraform-plan.yml` has `TF_WORKING_DIR: "environments/prod-east"` which will not exist after migration.
**Why it happens:** The migration in D-01 moves content out of `environments/prod/`.
**How to avoid:** The replacement workflow must point to `scenarios/cc-azure/`. The old `environments/prod-east` reference in the existing workflow is already stale (the actual code is in `environments/prod/`). Both old workflows should be replaced entirely by the new reusable pattern.
**Warning signs:** CI referencing non-existent directories.

## Code Examples

### Example 1: cc-aws/main.tf Backend Block
```hcl
# Source: Terraform S3 backend docs + project conventions
terraform {
  required_version = ">= 1.5"
  required_providers {
    confluent = {
      source  = "confluentinc/confluent"
      version = "~> 2.0"
    }
  }

  # AWS S3 backend with DynamoDB state locking
  backend "s3" {
    bucket         = "fsi-terraform-state"       # .env: TF_BACKEND_S3_BUCKET
    key            = "kafka-platform/prod/terraform.tfstate"
    region         = "us-east-1"                 # .env: TF_BACKEND_S3_REGION
    encrypt        = true
    dynamodb_table = "fsi-terraform-locks"       # .env: TF_BACKEND_DYNAMODB_TABLE
  }
}

provider "confluent" {
  cloud_api_key    = var.confluent_cloud_api_key
  cloud_api_secret = var.confluent_cloud_api_secret
}
```

### Example 2: cc-gcp/main.tf Backend Block
```hcl
# Source: Terraform GCS backend docs + project conventions
terraform {
  required_version = ">= 1.5"
  required_providers {
    confluent = {
      source  = "confluentinc/confluent"
      version = "~> 2.0"
    }
  }

  # GCP Cloud Storage backend (locking is built-in)
  backend "gcs" {
    bucket = "fsi-terraform-state"               # .env: TF_BACKEND_GCS_BUCKET
    prefix = "kafka-platform/prod"               # .env: TF_BACKEND_GCS_PREFIX
  }
}

provider "confluent" {
  cloud_api_key    = var.confluent_cloud_api_key
  cloud_api_secret = var.confluent_cloud_api_secret
}
```

### Example 3: Validation Script Core Pattern
```bash
#!/usr/bin/env bash
# Source: Confluent Cloud REST API docs + project shell conventions
set -euo pipefail

# Arguments
KAFKA_REST_ENDPOINT="${1:?Usage: validate-apply.sh <kafka-rest> <cluster-id> <sr-rest> <kafka-key> <kafka-secret> <sr-key> <sr-secret> [dr-rest] [dr-cluster-id] [dr-key] [dr-secret]}"
KAFKA_CLUSTER_ID="${2:?}"
SR_REST_ENDPOINT="${3:?}"
KAFKA_API_KEY="${4:?}"
KAFKA_API_SECRET="${5:?}"
SR_API_KEY="${6:?}"
SR_API_SECRET="${7:?}"
DR_KAFKA_REST_ENDPOINT="${8:-}"
DR_KAFKA_CLUSTER_ID="${9:-}"
DR_KAFKA_API_KEY="${10:-}"
DR_KAFKA_API_SECRET="${11:-}"

PASS=0
FAIL=0
SKIP=0

check() {
  local label="$1" url="$2" key="$3" secret="$4"
  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" -u "${key}:${secret}" "${url}")
  if [ "${http_code}" = "200" ]; then
    echo "  PASS: ${label}"
    ((PASS++))
  else
    echo "  FAIL: ${label} (HTTP ${http_code})"
    echo "        Endpoint: ${url}"
    ((FAIL++))
  fi
}

# Discover topics from Terraform output
TOPICS=$(terraform output -json | jq -r 'to_entries[] | select(.value.value | type == "object") | select(.value.value.topic_name?) | .value.value.topic_name')

for topic in ${TOPICS}; do
  echo "=== Validating: ${topic} ==="
  subject="${topic}-value"

  # Check 1: Topic exists
  check "Topic exists" \
    "${KAFKA_REST_ENDPOINT}/kafka/v3/clusters/${KAFKA_CLUSTER_ID}/topics/${topic}" \
    "${KAFKA_API_KEY}" "${KAFKA_API_SECRET}"

  # Check 2: Schema registered
  check "Schema registered" \
    "${SR_REST_ENDPOINT}/subjects/${subject}/versions" \
    "${SR_API_KEY}" "${SR_API_SECRET}"

  # Check 3: RBAC (implicit -- if we can read the subject, RBAC allows it)
  check "Schema readable (RBAC)" \
    "${SR_REST_ENDPOINT}/subjects/${subject}/versions/latest" \
    "${SR_API_KEY}" "${SR_API_SECRET}"

  # Check 4: DR mirror (conditional)
  if [ -n "${DR_KAFKA_REST_ENDPOINT}" ] && [ -n "${DR_KAFKA_CLUSTER_ID}" ]; then
    check "DR mirror exists" \
      "${DR_KAFKA_REST_ENDPOINT}/kafka/v3/clusters/${DR_KAFKA_CLUSTER_ID}/topics/${topic}" \
      "${DR_KAFKA_API_KEY}" "${DR_KAFKA_API_SECRET}"
  else
    echo "  SKIP: DR mirror (DR cluster not configured)"
    ((SKIP++))
  fi
  echo ""
done

echo "=== Summary: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped ==="
[ "${FAIL}" -eq 0 ] || exit 1
```

### Example 4: Reusable Workflow (Condensed)
```yaml
# .github/workflows/terraform-scenario.yml
name: Terraform Scenario
on:
  workflow_call:
    inputs:
      scenario-dir:
        required: true
        type: string
      tf-version:
        required: false
        type: string
        default: "1.7.0"
    secrets:
      CONFLUENT_CLOUD_API_KEY:
        required: true
      CONFLUENT_CLOUD_API_SECRET:
        required: true
      KAFKA_API_KEY:
        required: true
      KAFKA_API_SECRET:
        required: true
      SR_API_KEY:
        required: true
      SR_API_SECRET:
        required: true
      DR_KAFKA_API_KEY:
        required: true
      DR_KAFKA_API_SECRET:
        required: true

jobs:
  lint:
    name: Lint & Validate
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ inputs.tf-version }}
      - name: Format Check
        run: terraform fmt -check -recursive
        working-directory: ${{ inputs.scenario-dir }}
      - name: Terraform Init (no backend)
        run: terraform init -backend=false
        working-directory: ${{ inputs.scenario-dir }}
      - name: Terraform Validate
        run: terraform validate
        working-directory: ${{ inputs.scenario-dir }}
```

### Example 5: AWS clusters.auto.tfvars.example
```hcl
# =============================================================================
# Cluster Configuration -- Copy to clusters.auto.tfvars (gitignored)
# =============================================================================
# Source values from Confluent Cloud Console, CLI, or .env.example.
# This file is auto-loaded by Terraform (*.auto.tfvars pattern).

kafka_cluster_id       = "lkc-xxxxx"                                              # CC_KAFKA_CLUSTER_ID
kafka_rest_endpoint    = "https://pkc-xxxxx.us-east-1.aws.confluent.cloud:443"    # CC_KAFKA_REST_ENDPOINT
kafka_cluster_crn      = "crn://confluent.cloud/organization=org-xxxxx/environment=env-xxxxx/cloud-cluster=lkc-xxxxx"
sr_cluster_id          = "lsrc-xxxxx"                                             # CC_SR_CLUSTER_ID
sr_rest_endpoint       = "https://psrc-xxxxx.us-east-1.aws.confluent.cloud"       # CC_SR_REST_ENDPOINT
sr_cluster_crn         = "crn://confluent.cloud/organization=org-xxxxx/environment=env-xxxxx/schema-registry=lsrc-xxxxx"
cluster_link_name      = "cluster-link-bidir-prod-dr"                             # CC_CLUSTER_LINK_NAME
dr_kafka_cluster_id    = "lkc-yyyyy"                                              # CC_DR_KAFKA_CLUSTER_ID
dr_kafka_rest_endpoint = "https://pkc-yyyyy.us-west-2.aws.confluent.cloud:443"
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| DynamoDB for S3 state locking | S3 native locking (`use_lockfile`) | Terraform 1.10 (2025) | DynamoDB no longer strictly required; however D-07 locks us to DynamoDB |
| Single environment directory | Scenario-based directory structure | This phase | Enables multi-cloud parity without shared state |
| terraform-plan.yml with hardcoded dir | Reusable workflow + per-scenario callers | This phase | DRY CI with explicit per-scenario triggers |
| No post-apply validation | Shell smoke script via REST API | This phase (IAC-10) | Catches silent failures in topic/schema/RBAC/mirror creation |

**Deprecated/outdated:**
- `environments/prod/` directory: Will be migrated to `scenarios/cc-azure/` as part of D-01
- `environments/prod-east` reference in existing workflows: Already stale (code lives in `environments/prod/`)
- DynamoDB state locking (long-term): HashiCorp has deprecated `dynamodb_table` in favor of `use_lockfile`, but D-07 decision keeps DynamoDB for now

## Open Questions

1. **RBAC Validation Depth**
   - What we know: No public REST API for listing CC role bindings; CLI works but requires installation
   - What's unclear: Whether implicit validation (ability to read topic/schema proves RBAC works) is sufficient for IAC-10
   - Recommendation: Use implicit validation as primary (it proves RBAC is functional). Add a note in the validation output explaining the approach. If explicit RBAC listing is needed later, add CLI-based check as enhancement.

2. **Topic Discovery in Validation Script**
   - What we know: Need to validate all 3 reference topics; could hardcode names or parse Terraform output
   - What's unclear: Whether `terraform output -json` is available in the validation context (it requires state access)
   - Recommendation: Accept topic names as arguments or read from a generated manifest file. Alternatively, have the validation script accept a comma-separated list of expected topic names.

3. **.env.example Updates for Multi-Cloud**
   - What we know: Current `.env.example` is Azure-centric (section 7 has Azure-specific vars)
   - What's unclear: Whether to add AWS/GCP sections to the single `.env.example` or create per-scenario `.env.example` files
   - Recommendation: Add AWS and GCP sections to the existing `.env.example` (sections 7a, 7b, 7c) since it's described as "SINGLE source of truth." Comment out the non-active cloud sections.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Shell script (bash) + curl + jq |
| Config file | None -- validation is script-based |
| Quick run command | `bash scripts/validate-apply.sh <args>` |
| Full suite command | `terraform validate && terraform fmt -check -recursive && bash scripts/validate-apply.sh <args>` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| IAC-01 | CC-AWS scenario produces working Kafka env | smoke | `cd scenarios/cc-aws && terraform init -backend=false && terraform validate` | No -- Wave 0 |
| IAC-02 | CC-GCP scenario produces working Kafka env | smoke | `cd scenarios/cc-gcp && terraform init -backend=false && terraform validate` | No -- Wave 0 |
| IAC-06 | Each scenario is self-contained with README | manual-only | Verify file existence: `ls scenarios/cc-{aws,gcp,azure}/{main.tf,variables.tf,example-topics.tf,README.md}` | No -- Wave 0 |
| IAC-08 | Backend parameterized per provider | unit | `grep -q 'backend "s3"' scenarios/cc-aws/main.tf && grep -q 'backend "gcs"' scenarios/cc-gcp/main.tf && grep -q 'backend "azurerm"' scenarios/cc-azure/main.tf` | No -- Wave 0 |
| IAC-10 | Post-apply validation works | smoke | `bash scripts/validate-apply.sh <test-args>` (requires live cluster) | No -- Wave 0 |

### Sampling Rate
- **Per task commit:** `terraform fmt -check -recursive && terraform validate` in each scenario dir
- **Per wave merge:** Full `terraform validate` across all 3 scenarios + structural checks
- **Phase gate:** All 3 scenarios pass `terraform init -backend=false && terraform validate`; validation script syntax-checked with `bash -n scripts/validate-apply.sh`

### Wave 0 Gaps
- [ ] `scenarios/cc-azure/` directory -- migrated from `environments/prod/`
- [ ] `scenarios/cc-aws/` directory -- new scenario
- [ ] `scenarios/cc-gcp/` directory -- new scenario
- [ ] `scripts/validate-apply.sh` -- new validation script
- [ ] `.github/workflows/terraform-scenario.yml` -- new reusable workflow
- [ ] `.github/workflows/terraform-plan-{azure,aws,gcp}.yml` -- new caller workflows
- [ ] `.github/workflows/terraform-apply-{azure,aws,gcp}.yml` -- new apply workflows

Note: All validation for this phase is structural (file existence, Terraform syntax, backend block correctness) and smoke-level (REST API calls against live cluster). There are no unit tests in the traditional sense because the deliverables are Terraform configurations and shell scripts, not application code.

## Sources

### Primary (HIGH confidence)
- Existing codebase: `environments/prod/main.tf`, `modules/topic/main.tf`, `modules/topic/variables.tf` -- verified current project patterns
- Existing codebase: `.github/workflows/terraform-plan.yml`, `.github/workflows/terraform-apply.yml` -- verified current CI patterns
- [Terraform S3 Backend Docs](https://developer.hashicorp.com/terraform/language/backend/s3) -- S3 backend configuration, DynamoDB locking, `use_lockfile`
- [Terraform GCS Backend Docs](https://developer.hashicorp.com/terraform/language/backend/gcs) -- GCS backend configuration, built-in locking
- [GitHub Actions Reusable Workflows](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows) -- `workflow_call` syntax, inputs, secrets, `secrets: inherit`
- [Confluent Cloud Kafka REST API](https://docs.confluent.io/cloud/current/kafka-rest/krest-qs.html) -- Topic listing and verification via REST
- [Confluent Schema Registry REST API](https://docs.confluent.io/cloud/current/sr/sr-rest-apis.html) -- Subject listing and version verification

### Secondary (MEDIUM confidence)
- [Confluent CLI Mirror Commands](https://docs.confluent.io/confluent-cli/current/command-reference/kafka/mirror/confluent_kafka_mirror_list.html) -- mirror topic status checking
- [Confluent CLI RBAC Role Binding List](https://docs.confluent.io/confluent-cli/current/command-reference/iam/rbac/role-binding/confluent_iam_rbac_role-binding_list.html) -- RBAC verification via CLI
- [S3 Native Locking Blog](https://www.bschaatsbergen.com/s3-native-state-locking) -- `use_lockfile` introduced in Terraform 1.10

### Tertiary (LOW confidence)
- RBAC validation via REST API: No public CC endpoint found for listing role bindings; implicit validation approach is researcher's recommendation, not documented best practice

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all tools already in use in the project, versions verified against project constraints
- Architecture: HIGH -- scenario directory structure directly adapts existing `environments/prod/` pattern; module source paths verified
- Pitfalls: HIGH -- pitfalls derived from Terraform language constraints (backend blocks) and existing codebase analysis (CI path triggers)
- Validation script: MEDIUM -- REST API endpoints verified, but RBAC validation approach is a recommendation (no public REST API for CC role binding listing)

**Research date:** 2026-03-22
**Valid until:** 2026-04-22 (30 days -- tools and patterns are stable)

# Phase 1: Shared Governance Foundation - Research

**Researched:** 2026-03-21
**Domain:** Terraform module refactoring, Avro schema CI validation, Confluent Schema Registry compatibility API, ADR authoring
**Confidence:** HIGH

## Summary

Phase 1 codifies governance primitives (topic naming, schema compatibility, RBAC patterns, SLA-tier defaults) into a shared module library and CI pipeline before any new scenario directory is created. This is a brownfield refactor of the existing `modules/topic/` and `environments/prod/` codebase, not a greenfield build. The existing module already implements the core governance pattern (SLA-tier-derived compatibility, partitions, retention); this phase extends it (compliance tier), externalizes hardcoded config, adds CI-level schema validation, and documents three architectural decisions.

The primary technical challenge is the CI schema validation pipeline: checking compatibility against a live Schema Registry endpoint during PR validation, enforcing namespace conventions, and blocking undocumented `compatibility_override` usage. The Confluent Schema Registry REST API provides a `POST /compatibility/subjects/{subject}/versions` endpoint that returns `is_compatible: true/false` -- this is the mechanism for CI pre-merge validation. The secondary challenge is externalizing the 10+ hardcoded cluster IDs/endpoints from `environments/prod/main.tf` into a centralized `clusters.tfvars` pattern without breaking the existing deployment.

**Primary recommendation:** Refactor `modules/topic/` in place (keep the directory name, extend the interface), externalize cluster config to `clusters.auto.tfvars`, add a Python schema validation script to CI, and write three ADRs using the existing template.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Refactor existing `modules/topic/` into `modules/shared/` (or similar) that can be imported by any scenario directory via relative path or Terraform registry-style source
- **D-02:** The shared module interface stays: `domain`, `application`, `version`, `entity`, `sla_tier`, `owner_email`, `producer_sa`, `consumer_sa`, `pii_fields`, `data_classification` -- extend, don't break
- **D-03:** SLA tier map extended with `compliance` tier (7-year retention, FULL_TRANSITIVE compat, 12 partitions) alongside existing critical/standard/best-effort
- **D-04:** Module outputs remain: topic_name, schema_subject, compatibility_mode, partition_count -- used by downstream scenarios
- **D-05:** Replace hardcoded locals in `environments/prod/main.tf` (lines 33-55) with a `clusters.tfvars` pattern or `terraform_remote_state` data source
- **D-06:** Cluster metadata (IDs, REST endpoints, CRNs, bootstrap URLs) stored in a single config file per environment -- not scattered across locals
- **D-07:** Existing `environments/prod/` directory migrates to `scenarios/cc-azure/` as first scenario (backward compat preserved)
- **D-08:** Add schema compatibility check to `.github/workflows/terraform-plan.yml` using SR REST API (`/compatibility/subjects/{subject}/versions/{version}`)
- **D-09:** Namespace validation enforces `org.fsi.{domain}.{application}.{entity}` pattern -- CI rejects `.avsc` files that violate this
- **D-10:** `compatibility_override` blocked in CI unless PR description contains ADR or JIRA exception reference (regex match on PR body)
- **D-11:** Python validation script in CI for schema checks (already partially exists in plan workflow)
- **D-12:** Add "Breaking Change Runbook" section to existing `docs/schema-guide.md` -- not a separate document
- **D-13:** Runbook covers: create versioned topic (v2), dual-write period, consumer migration, deprecate old topic, decommission
- **D-14:** ADR-006: OAuth vs API Keys -- recommend OAuth/OAUTHBEARER for CC (Azure AD, AWS IAM), API keys as fallback for on-prem, include credential rotation guidance per model
- **D-15:** ADR-007: Topic Naming Rationale -- document `{domain}.{application}.{version}.{entity}` with regex `^[a-z][a-z0-9-]{1,30}$` per segment, explain why dots as separators
- **D-16:** ADR-008: DR Tier Classification -- map SLA tiers to RPO/RTO targets (critical: RPO <5min/RTO <15min, standard: RPO <2h/RTO <1h, best-effort: RPO <24h/RTO <4h, compliance: RPO=0 via MRC)

### Claude's Discretion
- Exact directory naming for shared modules (`modules/shared/` vs `modules/governance/` vs keeping `modules/topic/`)
- CI script language (Python vs bash for schema validation)
- Whether to use Terraform `test` blocks (1.6+) for validation or shell-based smoke tests
- ADR numbering continuation (006, 007, 008 vs different scheme)

### Deferred Ideas (OUT OF SCOPE)
- Post-apply Terraform validation (IAC-10) -- Phase 2 requirement
- Service account provisioning via IaC (RBAC-01) -- Phase 3 requirement
- Credential rotation automation (RBAC-04) -- Phase 3 requirement
- Compliance retention tier implementation in topic module (COMP-01) -- Phase 3, but compliance map entry added here
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| IAC-07 | Shared module library enforces identical topic naming, schema compatibility, RBAC, and SLA-tier defaults across all deployment models | Refactoring `modules/topic/` to add compliance tier, keeping stable interface. Terraform mock_provider testing validates module in isolation. |
| IAC-09 | Cluster IDs, REST endpoints, and CRNs are externalized to centralized config instead of hardcoded locals | `clusters.auto.tfvars` pattern replaces hardcoded locals in `environments/prod/main.tf` lines 33-55. Variables replace locals. |
| SCHEMA-01 | CI pipeline validates schema compatibility before merge using SR compatibility API | Python script calls `POST /compatibility/subjects/{subject}/versions` with `?verbose=true`. Runs in CI before TF plan. |
| SCHEMA-02 | CI prevents namespace collisions by validating `.avsc` namespace matches `org.fsi.{domain}.{application}.{entity}` | Python script parses `.avsc` JSON, validates namespace regex, cross-references with topic declarations. |
| SCHEMA-03 | CI blocks `compatibility_override` unless paired with documented exception reference | GitHub Actions step greps for `compatibility_override` in changed .tf files, checks PR body for ADR/JIRA regex. |
| SCHEMA-04 | Breaking change runbook in schema-guide.md walks teams through multi-topic migration | Added as new section to existing `docs/schema-guide.md`. Covers v2 topic creation, dual-write, consumer migration, decommission. |
| GOV-01 | ADR for OAuth vs API keys authentication decision with deployment-model-specific guidance | ADR-006 following existing template in `docs/adr/000-template.md`. Covers CC (OAuth via Azure AD / AWS IAM), CP (MDS), CFK (LDAP). |
| GOV-02 | ADR for topic naming rationale explaining convention | ADR-007 documenting `{domain}.{application}.{version}.{entity}`, regex per segment, dot separators rationale. |
| GOV-03 | ADR for DR tier classification (RPO/RTO targets per SLA tier) | ADR-008 mapping SLA tiers to RPO/RTO targets, backend selection criteria (Cluster Linking vs MRC). |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Terraform | >= 1.7.0 | Infrastructure as code | Already pinned in CI; 1.7+ required for mock_provider in tests |
| Confluent Terraform Provider | ~> 2.0 (currently 2.64.0 latest) | Confluent Cloud resource management | Already in use; `~> 2.0` constraint kept for stability |
| Python 3 | 3.8+ | Schema validation CI scripts | Already used in existing CI pipeline for Avro validation |
| fastavro | 1.12.x | Avro schema parsing and validation | Fast, well-maintained Python library for Avro schema operations |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| jq | 1.6+ | JSON processing in CI scripts | Parse curl responses from SR compatibility API |
| curl | 7.x | HTTP requests to Schema Registry | CI pipeline schema compatibility checks |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Python + fastavro for schema validation | Confluent CLI `confluent schema-registry schema compatibility validate` | CLI requires Confluent CLI installation in CI runners and auth configuration; Python is already in the pipeline and gives more control over error messages |
| `clusters.auto.tfvars` for config externalization | `terraform_remote_state` data source | Remote state requires a separate admin TF module to exist first; tfvars is simpler for Phase 1 and can be upgraded to remote state later |
| Keeping `modules/topic/` directory name | Renaming to `modules/shared/` or `modules/governance/` | Renaming now breaks the existing `source = "../../modules/topic"` reference in `environments/prod/example-topics.tf`; keep `modules/topic/` for backward compat, add `modules/governance/` as a new wrapper if needed in later phases |

## Architecture Patterns

### Recommended Project Structure (Phase 1 Changes)

```
fsi-kafka-platform/
|-- modules/
|   +-- topic/                          # EXTENDED: Add compliance tier, accept variables for cluster config
|       |-- main.tf                     # Add compliance tier to SLA maps
|       |-- variables.tf               # Extend sla_tier validation to include "compliance"
|       |-- outputs.tf                 # Keep existing outputs
|       +-- tests/                     # NEW: Terraform test files
|           +-- governance.tftest.hcl  # Mock provider tests for governance rules
|
|-- environments/
|   +-- prod/                          # MIGRATED: Externalize hardcoded config
|       |-- main.tf                    # Locals replaced with variables from clusters.auto.tfvars
|       |-- clusters.auto.tfvars       # NEW: Centralized cluster metadata (gitignored)
|       |-- clusters.auto.tfvars.example  # NEW: Template for cluster metadata
|       |-- example-topics.tf          # Unchanged
|       +-- terraform.tfvars.example   # Updated with new variables
|
|-- schemas/
|   +-- examples/                      # EXISTING: Reference schemas (unchanged)
|
|-- ci/
|   +-- scripts/                       # NEW: CI validation scripts
|       |-- validate-schemas.py        # Schema validation: namespace, compatibility, structure
|       +-- check-overrides.sh         # Override detection in PR changes
|
|-- .github/
|   +-- workflows/
|       |-- terraform-plan.yml         # ENHANCED: Add schema compatibility + override checks
|       +-- terraform-apply.yml        # UPDATED: Path references for scenarios/ (Phase 2 prep)
|
|-- docs/
|   |-- schema-guide.md               # ENHANCED: Add breaking change runbook section
|   +-- adr/
|       |-- 006-oauth-vs-api-keys.md   # NEW
|       |-- 007-topic-naming.md        # NEW
|       +-- 008-dr-tier-classification.md  # NEW
```

### Pattern 1: SLA Tier as Configuration Multiplier (Extend, Don't Rewrite)

**What:** The existing `modules/topic/main.tf` uses local maps (`compatibility_map`, `partition_map`, `retention_map`) keyed by SLA tier to derive configuration. This pattern is extended by adding the `compliance` tier entry to each map.

**When to use:** Always when adding new SLA tier behavior. Never bypass the map pattern with hardcoded values.

**Example:**
```hcl
# Source: existing modules/topic/main.tf pattern, extended
locals {
  compatibility_map = {
    critical    = "FULL_TRANSITIVE"
    standard    = "BACKWARD_TRANSITIVE"
    best-effort = "BACKWARD"
    compliance  = "FULL_TRANSITIVE"        # NEW: Same as critical for audit integrity
  }

  partition_map = {
    critical    = 12
    standard    = 6
    best-effort = 3
    compliance  = 12                       # NEW: Same as critical for throughput
  }

  retention_map = {
    critical    = 604800000                # 7 days
    standard    = 259200000                # 3 days
    best-effort = 86400000                 # 1 day
    compliance  = 220898664000000          # 7 years (7 * 365.25 * 24 * 60 * 60 * 1000)
  }
}
```

### Pattern 2: Cluster Config Externalization via Variables + Auto-Tfvars

**What:** Replace hardcoded `locals` blocks containing cluster IDs, REST endpoints, and CRNs with Terraform variables loaded from a `clusters.auto.tfvars` file. The `.auto.tfvars` suffix means Terraform loads it automatically without `-var-file` flags.

**When to use:** For all environment-specific cluster metadata. Never hardcode cluster IDs or endpoints in `.tf` files.

**Example:**
```hcl
# environments/prod/variables.tf (NEW variables replacing locals)
variable "kafka_cluster_id" {
  description = "Confluent Cloud Kafka cluster ID (production)"
  type        = string
}

variable "kafka_rest_endpoint" {
  description = "Kafka REST endpoint for the production cluster"
  type        = string
}

variable "kafka_cluster_crn" {
  description = "Confluent Resource Name for the Kafka cluster (for RBAC)"
  type        = string
}

# ... (all 10+ cluster-specific values become variables)

# environments/prod/main.tf (AFTER -- locals replaced)
locals {
  infra = {
    kafka_cluster_id       = var.kafka_cluster_id
    kafka_rest_endpoint    = var.kafka_rest_endpoint
    kafka_cluster_crn      = var.kafka_cluster_crn
    sr_cluster_id          = var.sr_cluster_id
    sr_rest_endpoint       = var.sr_rest_endpoint
    sr_cluster_crn         = var.sr_cluster_crn
    cluster_link_name      = var.cluster_link_name
    dr_kafka_cluster_id    = var.dr_kafka_cluster_id
    dr_kafka_rest_endpoint = var.dr_kafka_rest_endpoint
  }
}
```

```hcl
# environments/prod/clusters.auto.tfvars.example
# Copy to clusters.auto.tfvars (gitignored). Source values from .env or CI secrets.
kafka_cluster_id       = "lkc-xxxxx"
kafka_rest_endpoint    = "https://pkc-xxxxx.eastus2.azure.confluent.cloud:443"
kafka_cluster_crn      = "crn://confluent.cloud/organization=org-xxxxx/environment=env-xxxxx/cloud-cluster=lkc-xxxxx"
sr_cluster_id          = "lsrc-xxxxx"
sr_rest_endpoint       = "https://psrc-xxxxx.eastus2.azure.confluent.cloud"
sr_cluster_crn         = "crn://confluent.cloud/organization=org-xxxxx/environment=env-xxxxx/schema-registry=lsrc-xxxxx"
cluster_link_name      = "cluster-link-bidir-prod-dr"
dr_kafka_cluster_id    = "lkc-yyyyy"
dr_kafka_rest_endpoint = "https://pkc-yyyyy.westus2.azure.confluent.cloud:443"
```

### Pattern 3: Schema CI Validation Pipeline

**What:** A Python script that validates all `.avsc` files in the PR against three rules: (1) valid Avro structure, (2) namespace matches `org.fsi.{domain}.{application}.{entity}` convention, (3) compatibility check against live Schema Registry. A separate bash step checks for `compatibility_override` usage and validates it against PR body.

**When to use:** Every PR that touches `schemas/` or `modules/` or `environments/` paths.

**Example CI step:**
```yaml
# In .github/workflows/terraform-plan.yml
- name: Validate Avro Schemas (Enhanced)
  env:
    SR_ENDPOINT: ${{ secrets.CC_SR_REST_ENDPOINT }}
    SR_API_KEY: ${{ secrets.SR_API_KEY }}
    SR_API_SECRET: ${{ secrets.SR_API_SECRET }}
  run: python3 ci/scripts/validate-schemas.py --schemas-dir schemas/ --check-compatibility

- name: Check Compatibility Overrides
  env:
    PR_BODY: ${{ github.event.pull_request.body }}
  run: |
    # Find any compatibility_override in changed .tf files
    OVERRIDES=$(git diff origin/main --name-only -- '*.tf' | xargs grep -l 'compatibility_override' 2>/dev/null || true)
    if [ -n "$OVERRIDES" ]; then
      # Check PR body for ADR or JIRA reference
      if ! echo "$PR_BODY" | grep -qiE '(ADR-[0-9]+|[A-Z]+-[0-9]+)'; then
        echo "ERROR: compatibility_override found but no ADR/JIRA reference in PR description"
        echo "Files: $OVERRIDES"
        exit 1
      fi
    fi
```

### Pattern 4: ADR Authoring Convention

**What:** ADRs follow the existing template at `docs/adr/000-template.md` with three sections: Context, Decision, Consequences. Numbering continues from the highest existing ADR (005).

**When to use:** Every governance decision that affects multiple deployment models.

**Numbering:** Continue with 006, 007, 008. This matches the existing sequential pattern (001-005).

### Anti-Patterns to Avoid

- **Rewriting the topic module from scratch:** The existing module is well-structured. Extend the SLA maps, add the compliance tier, and add new variables. Do not create a new module that duplicates logic.
- **Moving `modules/topic/` to `modules/shared/`:** This breaks the existing `source = "../../modules/topic"` reference. Keep `modules/topic/` as the directory name for Phase 1. If a wrapper is needed in later phases, create `modules/governance/` as a facade.
- **Hardcoding Schema Registry credentials in CI scripts:** Use GitHub Actions secrets and environment variables. Never commit SR credentials.
- **CI schema validation that requires `terraform init`:** The schema validation script should be independent of Terraform. Parse `.avsc` files directly with Python. Call the SR REST API directly with curl/requests. Do not couple schema checks to the Terraform plan step.
- **Running `terraform fmt -check` only on changed files:** Run it recursively on the entire repo to catch formatting drift introduced by concurrent PRs.

## Discretion Recommendations

Based on research, here are recommendations for areas marked as Claude's discretion:

### Directory Naming: Keep `modules/topic/`

**Recommendation:** Keep the existing `modules/topic/` directory name. Do not rename to `modules/shared/` or `modules/governance/`.

**Rationale:**
1. The existing `environments/prod/example-topics.tf` references `source = "../../modules/topic"`. Renaming breaks this.
2. D-07 says `environments/prod/` migrates to `scenarios/cc-azure/` -- but that is Phase 2 work. Phase 1 must keep backward compat.
3. The module IS a topic module. It creates a topic with governance. The name is accurate.
4. In Phase 2, if additional shared modules are extracted (schema, RBAC per ARCHITECTURE.md research), they get their own directories (`modules/schema/`, `modules/rbac/`). No need to rename topic.

### CI Script Language: Python

**Recommendation:** Use Python for schema validation scripts.

**Rationale:**
1. The existing CI pipeline already uses inline Python for Avro schema validation (`.github/workflows/terraform-plan.yml` lines 54-69).
2. `fastavro` provides robust Avro parsing with namespace handling.
3. Python can make HTTP requests to the SR compatibility API using `urllib` (stdlib, no pip install needed) or `requests`.
4. Python provides structured error reporting with clear messages per schema file.
5. Shell scripts struggle with JSON parsing and structured error reporting.

### Terraform Test Blocks: Use for Governance Rule Validation

**Recommendation:** Use `terraform test` with `mock_provider` for validating governance rules (SLA tier mappings, naming validation, override behavior). Do not use them for post-apply validation (that is IAC-10 in Phase 2).

**Rationale:**
1. Terraform 1.7+ (already pinned in CI) supports `mock_provider` -- governance rules can be tested without real Confluent credentials.
2. Mock tests validate: compliance tier produces FULL_TRANSITIVE + 12 partitions + 7-year retention, naming regex rejects invalid input, override behavior works correctly.
3. Tests run in CI without secrets, providing fast feedback on governance logic changes.
4. This is unit testing for Terraform, not integration testing. Integration (post-apply) is Phase 2.

### ADR Numbering: Continue Sequential (006, 007, 008)

**Recommendation:** Continue the existing sequential numbering: ADR-006, ADR-007, ADR-008.

**Rationale:**
1. Existing ADRs are numbered 000-005 sequentially.
2. No gaps, no category prefixes. Simple and consistent.
3. ADR-006 = OAuth vs API Keys, ADR-007 = Topic Naming, ADR-008 = DR Tier Classification.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Avro schema parsing | Custom JSON parser for `.avsc` files | `fastavro.schema.load_schema()` or `json.load()` + `fastavro.parse_schema()` | Avro has complex types (unions, logical types, nested records); fastavro handles all edge cases |
| Schema compatibility check | Custom diff logic comparing old and new schemas | Confluent SR REST API `POST /compatibility/subjects/{subject}/versions` | Compatibility rules (BACKWARD, FORWARD, FULL, TRANSITIVE variants) are complex; SR is the authority |
| Topic naming validation | Custom regex engine | Terraform `validation` blocks with `can(regex(...))` | Already implemented in `variables.tf`; extend, don't rebuild |
| GitHub Actions PR body inspection | Custom webhook handler | `${{ github.event.pull_request.body }}` in workflow | Native Actions context variable; no custom code needed |

**Key insight:** The governance validation logic is split between two enforcement points: Terraform validation blocks (build-time, catches invalid inputs) and CI pipeline scripts (pre-merge, catches policy violations). Do not try to consolidate into one. They serve different purposes.

## Common Pitfalls

### Pitfall 1: Breaking the Existing Module Interface
**What goes wrong:** Adding the `compliance` tier to `sla_tier` validation changes the enum. Any existing code that doesn't include `compliance` in its validation regex/list will fail `terraform validate`.
**Why it happens:** The `sla_tier` variable in `modules/topic/variables.tf` line 66 has a `contains()` validation that must be updated to include "compliance". But the existing environments still use only critical/standard/best-effort -- they will not break because adding a new valid value is backward compatible.
**How to avoid:** Only ADD "compliance" to the `contains()` list. Do not remove or rename existing tiers. Test with existing `environments/prod/example-topics.tf` after the change.
**Warning signs:** `terraform validate` fails on existing configurations.

### Pitfall 2: CI Schema Validation Requires Live SR Access
**What goes wrong:** The schema compatibility check calls the SR REST API, which requires network access and credentials. If SR is down, CI is blocked. If credentials expire, all PRs are blocked.
**Why it happens:** Pre-merge compatibility checking is fundamentally a live-service dependency.
**How to avoid:** Make the compatibility check a separate, optional CI step that warns but does not block if SR is unreachable (graceful degradation). The namespace and structure checks should always run (they are offline). Add a retry with timeout (30s) for the SR call.
**Warning signs:** CI pipeline hangs on schema validation step; PRs blocked by SR outage.

### Pitfall 3: `clusters.auto.tfvars` Accidentally Committed
**What goes wrong:** The `clusters.auto.tfvars` file contains non-secret but environment-specific values (cluster IDs, REST endpoints). If committed, other developers get wrong cluster IDs. If it contains secrets, they are leaked.
**Why it happens:** `.auto.tfvars` is an unusual extension not always in `.gitignore`.
**How to avoid:** Add `*.auto.tfvars` to `.gitignore`. Provide `clusters.auto.tfvars.example` (committed) as a template. Separate secrets (API keys) into `terraform.tfvars` (already gitignored) from cluster metadata (IDs, endpoints) in `clusters.auto.tfvars`.
**Warning signs:** Git status shows `clusters.auto.tfvars` as untracked/modified.

### Pitfall 4: Namespace Validation Pattern Mismatch
**What goes wrong:** The CONTEXT.md decision D-09 says namespace must match `org.fsi.{domain}.{application}.{entity}`, but existing schemas use `org.fsi.{domain}.{application}.{version}` (e.g., `org.fsi.cncb.core.v1`). The version segment is in the namespace, not the entity.
**Why it happens:** The AVSC namespace and the Terraform topic naming convention differ slightly. The topic name is `{domain}.{application}.{version}.{entity}` but the Avro namespace is `org.fsi.{domain}.{application}.{version}` (no entity -- the entity is the record name).
**How to avoid:** Validate that the namespace starts with `org.fsi.` and that the remaining segments match valid naming segments. Do not enforce entity in the namespace -- it is the Avro record name, not the namespace. The correct pattern is `org.fsi.{domain}.{application}.{version}`.
**Warning signs:** All 7 existing schemas would fail the D-09 namespace check if the entity segment is enforced in the namespace.

### Pitfall 5: Compliance Tier Retention Overflow
**What goes wrong:** 7-year retention in milliseconds is ~220,898,664,000,000 (220+ trillion). Terraform stores this as a number. The Confluent provider sends it as a string config value. If the value exceeds what the broker accepts for `retention.ms`, topic creation fails.
**Why it happens:** Confluent Cloud dedicated clusters support up to `-1` (infinite retention) or very large values, but standard clusters may have limits.
**How to avoid:** Verify that the target CC cluster type (dedicated/enterprise) supports the retention value. For CC dedicated clusters, `retention.ms = -1` (infinite) is supported. Consider using `-1` for compliance tier and documenting that actual retention enforcement is at the application/archival level, not Kafka-native.
**Warning signs:** Topic creation fails with "invalid retention.ms" error; Terraform plan shows unexpected large numbers.

### Pitfall 6: Override Detection False Positives
**What goes wrong:** The CI step that checks for `compatibility_override` in changed `.tf` files matches any file containing the string -- including the module definition itself (`modules/topic/variables.tf` declares the variable). This would flag every PR that touches the module.
**Why it happens:** Grep on `compatibility_override` matches both the variable declaration and actual usage. The variable declaration (with `default = null`) is not an override -- it is the definition.
**How to avoid:** Only check for `compatibility_override` in scenario/environment `.tf` files (topic declarations), not in `modules/`. The grep should target `environments/` and `scenarios/` paths, excluding `modules/`. Alternatively, check for lines where `compatibility_override` is assigned a non-null value: match `compatibility_override\s*=\s*"[^"]*"` instead of just the string.
**Warning signs:** Every PR touching the topic module is blocked.

## Code Examples

### Schema Validation Python Script Core Logic

```python
# ci/scripts/validate-schemas.py
# Source: Derived from existing CI inline Python + Confluent SR API docs

import json
import re
import sys
import os
import urllib.request
import urllib.error
import base64

NAMESPACE_PATTERN = re.compile(r'^org\.fsi\.[a-z][a-z0-9-]*\.[a-z][a-z0-9-]*\.v[0-9]+$')

def validate_schema_structure(schema_path):
    """Validate Avro schema JSON structure and required fields."""
    with open(schema_path) as f:
        schema = json.load(f)

    errors = []
    if schema.get('type') != 'record':
        errors.append(f"Schema must be a record type, got: {schema.get('type')}")
    if not schema.get('namespace'):
        errors.append("Schema must have a namespace")
    if not schema.get('fields'):
        errors.append("Schema must have fields")

    for field in schema.get('fields', []):
        if 'name' not in field:
            errors.append(f"Field missing 'name'")
        if 'type' not in field:
            errors.append(f"Field missing 'type': {field.get('name', '?')}")

    return schema, errors

def validate_namespace(schema, schema_path):
    """Validate namespace matches org.fsi.{domain}.{application}.{version}."""
    namespace = schema.get('namespace', '')
    if not NAMESPACE_PATTERN.match(namespace):
        return [f"Invalid namespace '{namespace}'. Must match org.fsi.{{domain}}.{{application}}.v{{N}}"]
    return []

def check_compatibility(schema, subject, sr_endpoint, sr_key, sr_secret):
    """Check schema compatibility against Schema Registry."""
    url = f"{sr_endpoint}/compatibility/subjects/{subject}/versions?verbose=true"
    data = json.dumps({"schema": json.dumps(schema), "schemaType": "AVRO"}).encode()

    credentials = base64.b64encode(f"{sr_key}:{sr_secret}".encode()).decode()
    req = urllib.request.Request(url, data=data, method='POST')
    req.add_header('Content-Type', 'application/vnd.schemaregistry.v1+json')
    req.add_header('Authorization', f'Basic {credentials}')

    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            result = json.loads(resp.read())
            if not result.get('is_compatible', False):
                return [f"Schema incompatible: {result.get('messages', [])}"]
    except urllib.error.HTTPError as e:
        if e.code == 404:
            pass  # Subject does not exist yet -- first registration, skip
        else:
            return [f"SR API error: {e.code} {e.reason}"]
    except urllib.error.URLError:
        print(f"WARNING: Schema Registry unreachable, skipping compatibility check")

    return []
```

### Terraform Test File for Governance Rules

```hcl
# modules/topic/tests/governance.tftest.hcl
# Source: HashiCorp Terraform test docs (developer.hashicorp.com/terraform/language/tests/mocking)

mock_provider "confluent" {}

variables {
  domain      = "corebanking"
  application = "transactions"
  version     = "v1"
  entity      = "account-transaction"
  owner       = "core-banking@fsi.org"
  sla_tier    = "critical"
  schema_file = "../../../schemas/examples/account-transaction.avsc"
  pii_fields  = ["account_number"]
  producer_service_accounts = ["sa-producer"]
  consumer_service_accounts = ["sa-consumer"]

  kafka_cluster_id              = "lkc-test"
  kafka_rest_endpoint           = "https://test.confluent.cloud:443"
  kafka_api_key                 = "test-key"
  kafka_api_secret              = "test-secret"
  kafka_cluster_crn             = "crn://confluent.cloud/organization=test/environment=test/cloud-cluster=lkc-test"
  schema_registry_cluster_id    = "lsrc-test"
  schema_registry_rest_endpoint = "https://test-sr.confluent.cloud"
  schema_registry_api_key       = "test-sr-key"
  schema_registry_api_secret    = "test-sr-secret"
  schema_registry_cluster_crn   = "crn://confluent.cloud/organization=test/environment=test/schema-registry=lsrc-test"
}

# Test: Critical tier produces correct governance defaults
run "critical_tier_governance" {
  command = plan

  assert {
    condition     = output.compatibility_mode == "FULL_TRANSITIVE"
    error_message = "Critical tier must use FULL_TRANSITIVE compatibility"
  }

  assert {
    condition     = output.partitions == 12
    error_message = "Critical tier must have 12 partitions"
  }
}

# Test: Compliance tier produces correct governance defaults
run "compliance_tier_governance" {
  command = plan

  variables {
    sla_tier = "compliance"
  }

  assert {
    condition     = output.compatibility_mode == "FULL_TRANSITIVE"
    error_message = "Compliance tier must use FULL_TRANSITIVE compatibility"
  }

  assert {
    condition     = output.partitions == 12
    error_message = "Compliance tier must have 12 partitions"
  }
}

# Test: Topic naming follows convention
run "topic_naming_convention" {
  command = plan

  assert {
    condition     = output.topic_name == "corebanking.transactions.v1.account-transaction"
    error_message = "Topic name must follow {domain}.{application}.{version}.{entity}"
  }
}

# Test: Invalid domain is rejected
run "invalid_domain_rejected" {
  command = plan
  expect_failures = [var.domain]

  variables {
    domain = "UPPERCASE"
  }
}
```

### Override Detection CI Script

```bash
#!/bin/bash
# ci/scripts/check-overrides.sh
# Checks for compatibility_override usage in scenario/environment files.
# Requires PR body to contain ADR or JIRA reference if override is used.
set -euo pipefail

PR_BODY="${PR_BODY:-}"
CHANGED_FILES=$(git diff origin/main --name-only -- 'environments/**/*.tf' 'scenarios/**/*.tf' 2>/dev/null || true)

if [ -z "$CHANGED_FILES" ]; then
  echo "No scenario/environment .tf files changed. Skipping override check."
  exit 0
fi

# Look for non-null compatibility_override assignments
OVERRIDE_FILES=""
for file in $CHANGED_FILES; do
  if grep -q 'compatibility_override\s*=\s*"[^"]*"' "$file" 2>/dev/null; then
    OVERRIDE_FILES="$OVERRIDE_FILES $file"
  fi
done

if [ -n "$OVERRIDE_FILES" ]; then
  echo "compatibility_override detected in:$OVERRIDE_FILES"

  if echo "$PR_BODY" | grep -qiE '(ADR-[0-9]+|[A-Z]{2,10}-[0-9]+)'; then
    echo "OK: ADR/JIRA reference found in PR description."
  else
    echo "ERROR: compatibility_override requires an ADR or JIRA reference in the PR description."
    echo "Add a reference like 'ADR-006' or 'PROJ-1234' to the PR body explaining the exception."
    exit 1
  fi
else
  echo "No compatibility_override detected in changed files."
fi
```

### Breaking Change Runbook Section (for schema-guide.md)

```markdown
## Breaking Change Runbook

When you must make an incompatible schema change (field removal, type change,
renaming) on a topic with FULL_TRANSITIVE or BACKWARD_TRANSITIVE compatibility:

### Step 1: Create Versioned Topic
Create a new topic with the next version:
- Old: `corebanking.transactions.v1.account-transaction`
- New: `corebanking.transactions.v2.account-transaction`

Use the same Terraform module with `version = "v2"` and the new schema file.

### Step 2: Dual-Write Period
Deploy producers that write to BOTH v1 and v2 topics simultaneously.
Duration: minimum 2 business days (allow consumer teams to migrate).

### Step 3: Consumer Migration
Each consumer team:
1. Updates their consumer to read from the v2 topic
2. Deploys and validates
3. Confirms to the C4E team via the intake form

### Step 4: Deprecate Old Topic
After all consumers confirm migration:
1. Stop producing to v1 topic
2. Add `deprecated = true` tag to the v1 schema metadata
3. Set a decommission date (retention period + 30 days buffer)

### Step 5: Decommission
After the decommission date:
1. Verify v1 consumer lag is 0 (no active consumers)
2. Remove v1 topic module from Terraform
3. Run `terraform apply` to delete the topic
4. Soft-delete the v1 schema subject (optional, preserves history)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Terraform `validate` only | `terraform test` with mock providers | Terraform 1.6 (Oct 2023), mocking in 1.7 (Jan 2024) | Module governance rules can be unit-tested without credentials |
| Schema validation at registration time only | Pre-merge CI compatibility check via SR REST API | Available since SR 5.x, standardized in CI by 2024 | Catches incompatible schemas before they reach apply |
| Hardcoded locals per environment | Variables + .auto.tfvars per scenario | Terraform best practice (always available) | Enables multi-scenario architecture without code duplication |
| API keys only | OAuth/OAUTHBEARER for CC | Confluent Cloud supports OAUTHBEARER since 2023 | Zero-downtime credential rotation via IdP token refresh |

**Deprecated/outdated:**
- `avro-python3` package: Consolidated into `avro` package. Use `fastavro` instead for better performance.
- `confluentinc/confluentcloud` Terraform provider: Deprecated in favor of `confluentinc/confluent` provider (already using the correct one).

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Terraform test (built-in, >= 1.7.0) + Python scripts (schema validation) |
| Config file | `modules/topic/tests/governance.tftest.hcl` (Wave 0 -- must be created) |
| Quick run command | `terraform test -filter=governance.tftest.hcl` (from `modules/topic/`) |
| Full suite command | `terraform test` (from `modules/topic/`) + `python3 ci/scripts/validate-schemas.py --schemas-dir schemas/` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| IAC-07 | SLA tier maps produce correct defaults for all tiers | unit (terraform test) | `cd modules/topic && terraform test` | Wave 0 |
| IAC-07 | Topic naming regex validation works | unit (terraform test) | `cd modules/topic && terraform test` | Wave 0 |
| IAC-09 | Config externalized -- no hardcoded cluster IDs in .tf locals | lint (grep) | `grep -rn 'lkc-\|lsrc-\|pkc-\|psrc-' environments/prod/main.tf` (expect 0 results) | Wave 0 |
| SCHEMA-01 | Schema compatibility checked against SR in CI | integration (python) | `python3 ci/scripts/validate-schemas.py --check-compatibility` | Wave 0 |
| SCHEMA-02 | Namespace matches `org.fsi.{domain}.{app}.{version}` | unit (python) | `python3 ci/scripts/validate-schemas.py --schemas-dir schemas/` | Wave 0 |
| SCHEMA-03 | Override blocked without ADR/JIRA reference | unit (bash) | `bash ci/scripts/check-overrides.sh` (with test PR body) | Wave 0 |
| SCHEMA-04 | Breaking change runbook section exists in schema-guide.md | manual-only | Verify section exists in `docs/schema-guide.md` | N/A |
| GOV-01 | ADR-006 exists with required sections | manual-only | Verify file exists and has Context/Decision/Consequences | N/A |
| GOV-02 | ADR-007 exists with required sections | manual-only | Verify file exists and has Context/Decision/Consequences | N/A |
| GOV-03 | ADR-008 exists with required sections | manual-only | Verify file exists and has Context/Decision/Consequences | N/A |

### Sampling Rate
- **Per task commit:** `cd modules/topic && terraform test` + `python3 ci/scripts/validate-schemas.py --schemas-dir schemas/`
- **Per wave merge:** Full suite: terraform test + schema validation + override check + `terraform validate` + `terraform fmt -check`
- **Phase gate:** All automated tests green + manual verification of ADRs and runbook before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `modules/topic/tests/governance.tftest.hcl` -- covers IAC-07 (SLA tier governance rules, naming validation)
- [ ] `ci/scripts/validate-schemas.py` -- covers SCHEMA-01, SCHEMA-02 (schema compatibility and namespace validation)
- [ ] `ci/scripts/check-overrides.sh` -- covers SCHEMA-03 (override detection)
- [ ] `pip install fastavro` or use stdlib `json` only -- determine if fastavro is needed in CI runner

## Open Questions

1. **Schema Registry access from CI**
   - What we know: SR REST API requires Basic auth with API key/secret. The existing CI pipeline has `SR_API_KEY` and `SR_API_SECRET` secrets.
   - What's unclear: Whether the CI runner can reach the SR endpoint (firewall rules, VPN, PrivateLink). The SR endpoint in `.env.example` is `https://psrc-xxxxx.eastus2.azure.confluent.cloud` which is a public CC endpoint -- likely reachable from GitHub Actions runners.
   - Recommendation: Test connectivity first. If unreachable, the compatibility check degrades gracefully (warn, don't block). Namespace and structure checks always run.

2. **Compliance tier retention value**
   - What we know: 7-year retention = ~220.9 trillion ms. CC dedicated clusters support `retention.ms = -1` (infinite).
   - What's unclear: Whether a specific numeric value > 2^53 (JavaScript MAX_SAFE_INTEGER) causes precision issues in the Confluent provider or broker.
   - Recommendation: Use `-1` (infinite retention) for compliance tier rather than calculating 7 years in ms. Document that actual retention enforcement is at the archival/compliance platform level, not purely Kafka-native.

3. **`environments/prod/` vs `scenarios/cc-azure/` migration timing**
   - What we know: D-07 says environments/prod/ migrates to scenarios/cc-azure/. But D-05 says externalize config in environments/prod/.
   - What's unclear: Whether the directory migration happens in Phase 1 or Phase 2.
   - Recommendation: Phase 1 externalizes config in `environments/prod/` in place. Phase 2 performs the directory migration to `scenarios/cc-azure/`. This preserves CI pipeline paths (`environments/prod-east` in workflow YAML) and avoids coupling two large changes.

## Sources

### Primary (HIGH confidence)
- Existing codebase: `modules/topic/main.tf`, `variables.tf`, `outputs.tf` -- read directly
- Existing codebase: `environments/prod/main.tf`, `example-topics.tf` -- read directly
- Existing codebase: `.github/workflows/terraform-plan.yml`, `terraform-apply.yml` -- read directly
- Existing codebase: `schemas/examples/*.avsc` (7 files) -- namespaces verified
- Existing codebase: `docs/schema-guide.md`, `docs/adr/000-template.md` through `005-*.md` -- read directly
- [Confluent Schema Registry API Reference](https://docs.confluent.io/platform/current/schema-registry/develop/api.html) -- compatibility endpoint verified
- [Confluent CLI schema compatibility validate](https://docs.confluent.io/confluent-cli/current/command-reference/schema-registry/schema/compatibility/confluent_schema-registry_schema_compatibility_validate.html) -- CLI syntax verified
- [HashiCorp Terraform Tests - Mock Providers](https://developer.hashicorp.com/terraform/language/tests/mocking) -- mock_provider syntax verified
- [HashiCorp Terraform Tests - Configuration Language](https://developer.hashicorp.com/terraform/language/tests) -- .tftest.hcl format verified

### Secondary (MEDIUM confidence)
- [Confluent Terraform Provider Registry](https://registry.terraform.io/providers/confluentinc/confluent/latest) -- latest version 2.64.0 confirmed
- [fastavro PyPI](https://pypi.org/project/fastavro/) -- version 1.12.x confirmed current
- [Schema Registry API Usage Examples](https://docs.confluent.io/platform/current/schema-registry/develop/using.html) -- curl examples for compatibility

### Tertiary (LOW confidence)
- Compliance tier retention value limits on CC dedicated clusters -- not verified against specific CC documentation; needs testing

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All tools already in use or well-documented
- Architecture: HIGH - Extending existing patterns, not creating new ones
- Pitfalls: HIGH - Verified against actual codebase; namespace pattern mismatch (Pitfall 4) discovered through direct schema inspection
- Validation: MEDIUM - Terraform test with mock_provider verified in docs but not tested against Confluent provider specifically
- ADR content: HIGH - Follows existing template and numbering; content derived from project decisions

**Research date:** 2026-03-21
**Valid until:** 2026-04-21 (stable domain; Terraform provider minor versions may change but not affect Phase 1 patterns)

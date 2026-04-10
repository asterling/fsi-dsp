# Phase 3: Access Control and Compliance - Research

**Researched:** 2026-03-22
**Domain:** Confluent Cloud RBAC, OAuth/OAUTHBEARER, CSFLE, Vault credential rotation, CI/CD audit trails
**Confidence:** HIGH

## Summary

Phase 3 enhances the existing topic module (`modules/topic/`) with automated service account provisioning, data classification enforcement via CSFLE, and compliance retention controls. It adds per-scenario OAuth/OAUTHBEARER identity provider configuration, documents Vault-based credential rotation with dual-credential windows, and strengthens the CI/CD pipeline with audit trail annotations and compliance documentation.

The Confluent Terraform Provider v2.x provides all necessary resources: `confluent_service_account` for SA provisioning, `confluent_identity_provider` + `confluent_identity_pool` for OAuth, `confluent_schema_registry_kek` + `confluent_schema_registry_dek` for CSFLE, and `confluent_api_key` for credential management. The existing module's `for_each = toset()` pattern and SLA-tier-as-configuration-multiplier architecture directly support the create-or-reference SA pattern and classification-driven CSFLE enforcement.

CSFLE requires the Stream Governance Advanced package on Confluent Cloud. The encryption rule model uses envelope encryption (KEK + DEK) with tags on schema fields (e.g., `PII`) to automatically encrypt/decrypt at producer/consumer. The Terraform `confluent_schema` resource supports `ruleset.domain_rules` blocks with `type = "ENCRYPT"` and `tags = ["PII"]` for defining these rules declaratively.

**Primary recommendation:** Extend the topic module with conditional SA creation (controlled by `create_service_accounts` bool), CSFLE encryption rules (conditional on `data_classification == "confidential"`), and `retention_years` variable for compliance tier. Add per-scenario `oauth.tf` files. Add CI job summary and PR template enhancements for audit trail.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Service accounts created inside the topic module -- one module call produces SA + topic + schema + RBAC + DR mirror. No separate SA creation step required for teams.
- **D-02:** Create-or-reference pattern -- module accepts optional existing SA IDs. If not provided, creates new `confluent_service_account` resources. If provided, skips creation and binds RBAC to existing SAs. Handles both dedicated and shared SA scenarios.
- **D-03:** Per-scenario OAuth config files -- each scenario directory gets an `oauth.tf` or OAuth configuration example showing IdP integration for that cloud (Azure AD/Entra ID for Azure, AWS IAM Identity Center for AWS, GCP Cloud Identity for GCP). References ADR-006.
- **D-04:** Reference pattern + docs -- Terraform module for Vault secret engine configuration, example rotation policy, dual-credential window documentation. No live Vault dependency in CI. Teams adapt to their Vault instance.
- **D-05:** Time-based dual-credential window -- new credential created, both valid for configurable window (e.g., 24h default). After window expires, old credential revoked. Documented in rotation runbook with Vault TTL settings.
- **D-06:** Prescriptive Vault path convention -- `secret/fsi-kafka/{env}/{domain}/{sa-name}`. All examples, docs, and rotation scripts use this convention. Teams expected to follow it.
- **D-07:** Vault primary, cloud-native documented -- Vault is the golden path with full reference Terraform pattern. AWS Secrets Manager, Azure Key Vault, GCP Secret Manager get per-scenario doc sections showing equivalent rotation approach. No Terraform for cloud-native secret managers.
- **D-08:** Full encryption enforcement for confidential topics -- Confluent CSFLE (client-side field-level encryption) via Schema Registry encryption rules. PII fields encrypted at producer, decrypted at authorized consumer. Requires KMS integration (Vault or cloud KMS per provider).
- **D-09:** Terraform validation for confidential topics -- at least one consumer SA explicitly listed (no open access), PII fields must be non-empty, consumer group pattern restricted to named SAs only. Enforced via Terraform validation blocks in topic module.
- **D-10:** Audit log tagging + alert rules for enhanced logging -- tag confidential topic operations in Confluent Cloud audit logs. Provide alert rule templates that trigger on unauthorized access attempts to confidential topics. Leverages CC's built-in audit log.
- **D-11:** Configurable compliance retention -- add `retention_years` variable for compliance tier. Default -1 (infinite), but teams can set 7, 10, etc. (calculated to ms). CI validates compliance topics have retention >= 7 years or infinite.
- **D-12:** CI annotations + compliance guide -- GitHub Actions workflow annotations on apply jobs (PR link, reviewer, timestamp, validation result). Plus `docs/compliance-guide.md` mapping each step to regulatory controls. Examiners follow the doc, click links to GitHub artifacts.
- **D-13:** Generic FSI control mapping -- map steps to generic control categories: change management, access control, segregation of duties, audit logging. Teams map to their specific frameworks (OCC, FFIEC, PRA). More reusable across jurisdictions.
- **D-14:** Enhanced PR template -- update `.github/PULL_REQUEST_TEMPLATE.md` with checkboxes: data classification reviewed, RBAC verified, schema compatibility checked, compliance tier justified. Guides reviewers and creates audit evidence.
- **D-15:** Workflow summary + annotations -- terraform apply job writes a GitHub Actions job summary with: resources created/modified, validation PASS/FAIL per check, timestamp, PR link. Visible in workflow run page. No extra artifacts.

### Claude's Discretion
- Whether topic module creates API keys for provisioned SAs (security vs convenience trade-off given Terraform state sensitivity)
- Exact CSFLE encryption rule syntax and KMS key reference format per cloud provider
- CI validation script implementation for compliance retention floor check
- Rotation runbook structure and step ordering
- Alert rule template format for confidential topic access monitoring

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| RBAC-01 | Service accounts provisioned via IaC alongside topic creation (CC: `confluent_service_account`) | `confluent_service_account` resource is GA in provider v2.x. Create-or-reference via `count` conditional on `create_service_accounts` variable. Existing `for_each = toset()` RBAC pattern works with both created and referenced SAs. |
| RBAC-02 | RBAC binding patterns produce identical permissions across CC deployment models | CC RBAC uses `confluent_role_binding` with CRN patterns -- already implemented in module. Azure/AWS/GCP all use identical Confluent Cloud RBAC API. No cloud-specific RBAC differences for CC scenarios. |
| RBAC-03 | OAuth/OAUTHBEARER authentication documented and configured for CC deployments | `confluent_identity_provider` + `confluent_identity_pool` resources enable declarative OAuth setup per scenario. JAAS config properties documented for Azure AD, AWS IAM, GCP Cloud Identity. |
| RBAC-04 | Credential rotation automation supports zero-downtime dual-credential window via Vault integration | Confluent allows multiple active API keys per SA. Vault KV v2 with TTL-based versioning enables dual-credential window. Reference Terraform pattern + rotation runbook. |
| COMP-01 | Compliance SLA tier with configurable retention up to 7 years | Existing compliance tier uses -1 (infinite). Add `retention_years` variable to calculate ms. 7 years = 220,752,000,000 ms. CI validation script checks floor. |
| COMP-02 | Data classification enforcement for `confidential` topics | CSFLE via `confluent_schema` ruleset with `domain_rules` blocks. `confluent_schema_registry_kek` registers KEK per KMS provider. Terraform validation blocks enforce consumer list + PII fields for confidential topics. |
| COMP-04 | Audit trail documentation maps PR -> review -> merge -> apply -> verify | GitHub Actions `$GITHUB_STEP_SUMMARY` for job summaries. Annotations via `::notice`/`::warning`. `docs/compliance-guide.md` maps workflow to FSI control categories. |
</phase_requirements>

## Standard Stack

### Core

| Library/Resource | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `confluentinc/confluent` Terraform provider | ~> 2.0 (latest GA) | All Confluent Cloud resource management | Already pinned in project; v2.x is current GA line |
| `confluent_service_account` | Provider v2.x | Create service accounts alongside topics | GA resource, simple schema (display_name + description) |
| `confluent_identity_provider` | Provider v2.x | Register OAuth/OIDC identity providers (Azure AD, Okta, etc.) | GA resource for CC OAuth flow |
| `confluent_identity_pool` | Provider v2.x | Map IdP claims to Confluent principals via CEL filters | GA resource for CC OAuth flow |
| `confluent_schema_registry_kek` | Provider v2.x | Register Key Encryption Keys for CSFLE | GA resource for envelope encryption |
| `confluent_schema_registry_dek` | Provider v2.x | Manage Data Encryption Keys | GA resource, auto-generated in most flows |
| `confluent_api_key` | Provider v2.x | Create cluster/SR API keys owned by service accounts | GA resource with `owner` block linking to SA |
| `confluent_role_binding` | Provider v2.x | Assign RBAC roles to principals (already in module) | Already in use; extend for new SAs |
| `confluent_schema` (ruleset) | Provider v2.x | Attach CSFLE encryption rules via `ruleset.domain_rules` | Existing resource; `ruleset` block adds encryption |

### Supporting

| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| Terraform `terraform test` | 1.7.0+ | Module validation with mock providers | Testing SA creation, validation blocks, CSFLE conditionals |
| GitHub Actions `$GITHUB_STEP_SUMMARY` | N/A (built-in) | Job-level markdown summaries for audit trail | Every terraform apply job |
| GitHub Actions annotations | N/A (built-in) | `::notice`/`::warning`/`::error` for PR-level feedback | Compliance validation results |
| HashiCorp Vault KV v2 | N/A (reference pattern) | Credential storage with TTL and versioning | Reference Terraform pattern; no live dependency |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| CSFLE via Schema Registry rules | Confluent CSPE (Client-Side Payload Encryption) | CSPE encrypts entire payload; CSFLE is field-level. CSFLE is better for FSI where some fields must be readable by some consumers |
| Vault KV v2 for credential rotation | HCP Vault Secrets with auto-rotation | HCP Vault Secrets has native Confluent integration but requires HCP account. Vault KV v2 is more universal |
| API keys created in module | API keys created separately | Creating API keys in the module puts secrets in Terraform state. Recommendation: DO NOT create API keys in the topic module. Document separate API key creation pattern |

## Architecture Patterns

### Enhanced Module Structure
```
modules/topic/
  main.tf                    # Existing: topic, schema, RBAC, DR mirror
                             # Add: SA creation (conditional), CSFLE rules (conditional)
  variables.tf               # Existing: all current vars
                             # Add: create_service_accounts, retention_years, kek_name, csfle_kms_type, csfle_kms_key_id
  outputs.tf                 # Existing: all current outputs
                             # Add: producer_sa_ids, consumer_sa_ids
  tests/governance.tftest.hcl  # Existing: tier governance tests
                               # Add: SA creation tests, confidential validation tests, compliance retention tests

scenarios/cc-azure/
  main.tf                    # Existing
  oauth.tf                   # NEW: Azure AD identity provider + pool
  vault.tf.example           # NEW: Reference Vault pattern for Azure
  example-topics.tf          # Existing: update to use SA creation

scenarios/cc-aws/
  main.tf                    # Existing
  oauth.tf                   # NEW: AWS IAM identity provider + pool
  vault.tf.example           # NEW: Reference Vault pattern for AWS

scenarios/cc-gcp/
  main.tf                    # Existing
  oauth.tf                   # NEW: GCP Cloud Identity provider + pool
  vault.tf.example           # NEW: Reference Vault pattern for GCP

docs/
  compliance-guide.md        # NEW: PR-to-verify audit chain for examiners
  rotation-runbook.md        # NEW: Credential rotation with dual-credential window
  csfle-guide.md             # NEW: CSFLE setup per KMS provider

.github/
  PULL_REQUEST_TEMPLATE.md   # ENHANCED: Compliance checkboxes
  workflows/
    terraform-scenario.yml   # ENHANCED: Job summary + annotations
```

### Pattern 1: Create-or-Reference Service Accounts
**What:** Module conditionally creates `confluent_service_account` resources or accepts existing SA IDs for RBAC bindings.
**When to use:** Always -- this is the core pattern for D-01/D-02.
**Example:**
```hcl
# Source: Confluent Terraform Provider docs / project convention
variable "create_service_accounts" {
  description = "Whether to create new SAs or use existing IDs"
  type        = bool
  default     = true
}

variable "producer_sa_names" {
  description = "Display names for producer SAs (used when create_service_accounts = true)"
  type        = list(string)
  default     = []
}

# Create SAs when requested
resource "confluent_service_account" "producer" {
  for_each     = var.create_service_accounts ? toset(var.producer_sa_names) : toset([])
  display_name = each.value
  description  = "Producer SA for topic ${local.topic_name}"
}

# Resolve effective SA IDs for RBAC bindings
locals {
  effective_producer_sa_ids = var.create_service_accounts ? [
    for sa in confluent_service_account.producer : sa.id
  ] : var.producer_service_accounts

  effective_consumer_sa_ids = var.create_service_accounts ? [
    for sa in confluent_service_account.consumer : sa.id
  ] : var.consumer_service_accounts
}

# RBAC bindings use effective IDs (works with both patterns)
resource "confluent_role_binding" "producer" {
  for_each  = toset(local.effective_producer_sa_ids)
  principal = "User:${each.value}"
  role_name = "DeveloperWrite"
  crn_pattern = "${var.kafka_cluster_crn}/kafka=${var.kafka_cluster_id}/topic=${local.topic_name}"
}
```

### Pattern 2: CSFLE Encryption Rules (Conditional on Classification)
**What:** Attach CSFLE encryption rules to schema when `data_classification == "confidential"`.
**When to use:** Any topic with `data_classification = "confidential"` and `pii_fields` populated.
**Example:**
```hcl
# Source: Confluent Terraform Provider docs - confluent_schema ruleset
# KEK must be registered first
resource "confluent_schema_registry_kek" "pii" {
  count = var.data_classification == "confidential" ? 1 : 0

  schema_registry_cluster {
    id = var.schema_registry_cluster_id
  }
  rest_endpoint = var.schema_registry_rest_endpoint
  credentials {
    key    = var.schema_registry_api_key
    secret = var.schema_registry_api_secret
  }

  name       = var.kek_name
  kms_type   = var.csfle_kms_type    # "aws-kms", "azure-kms", "gcp-kms"
  kms_key_id = var.csfle_kms_key_id  # ARN / Key Vault URI / GCP resource name
  shared     = true                   # Allow DEK Registry to call KMS
}

# Schema with encryption ruleset
resource "confluent_schema" "value" {
  # ... existing schema config ...

  # CSFLE ruleset: only added for confidential topics
  dynamic "ruleset" {
    for_each = var.data_classification == "confidential" ? [1] : []
    content {
      domain_rules {
        name = "encryptPII"
        kind = "TRANSFORM"
        type = "ENCRYPT"
        mode = "WRITEREAD"
        tags = ["PII"]
        params = {
          "encrypt.kek.name" = var.kek_name
        }
      }
    }
  }
}
```

### Pattern 3: OAuth Identity Provider per Scenario
**What:** Each scenario directory declares its cloud-specific IdP and identity pool.
**When to use:** Per-scenario `oauth.tf` files in `scenarios/cc-*`.
**Example (Azure):**
```hcl
# Source: Confluent Terraform Provider - confluent_identity_provider
resource "confluent_identity_provider" "azure_ad" {
  display_name = "Azure AD (Entra ID)"
  description  = "FSI Azure AD identity provider for OAUTHBEARER authentication"
  issuer       = "https://login.microsoftonline.com/${var.azure_tenant_id}/v2.0"
  jwks_uri     = "https://login.microsoftonline.com/${var.azure_tenant_id}/discovery/v2.0/keys"
}

resource "confluent_identity_pool" "azure_producers" {
  identity_provider {
    id = confluent_identity_provider.azure_ad.id
  }
  display_name   = "Azure Producer Pool"
  description    = "Identity pool for Azure AD authenticated producers"
  identity_claim = "sub"
  filter         = "claims.aud==\"${var.confluent_cloud_app_id}\""
}
```

### Pattern 4: Compliance Retention with Years-to-Milliseconds Calculation
**What:** Add `retention_years` variable for compliance tier that calculates retention in ms.
**When to use:** When `sla_tier == "compliance"` and teams want explicit year-based retention.
**Example:**
```hcl
variable "retention_years" {
  description = "Retention period in years for compliance tier. Default -1 = infinite. Set 7, 10, etc. for specific retention."
  type        = number
  default     = -1

  validation {
    condition     = var.retention_years == -1 || var.retention_years >= 7
    error_message = "Compliance retention must be -1 (infinite) or >= 7 years per FSI regulatory requirements."
  }
}

locals {
  # Calculate retention_ms from years (1 year = 365.25 * 24 * 60 * 60 * 1000 ms)
  ms_per_year = 31557600000
  compliance_retention_ms = var.retention_years == -1 ? -1 : var.retention_years * local.ms_per_year

  # Updated retention_map: compliance tier uses calculated value
  retention_ms = var.sla_tier == "compliance" ? local.compliance_retention_ms : coalesce(
    var.retention_ms_override,
    lookup(local.retention_map, var.sla_tier, 259200000)
  )
}
```

### Pattern 5: GitHub Actions Job Summary for Audit Trail
**What:** Write structured markdown to `$GITHUB_STEP_SUMMARY` after terraform apply with resources modified, validation results, timestamps, and PR link.
**When to use:** Enhanced `terraform-scenario.yml` apply job.
**Example:**
```yaml
- name: Write Audit Summary
  if: inputs.mode == 'apply'
  run: |
    echo "## Terraform Apply Summary" >> "$GITHUB_STEP_SUMMARY"
    echo "" >> "$GITHUB_STEP_SUMMARY"
    echo "| Property | Value |" >> "$GITHUB_STEP_SUMMARY"
    echo "|----------|-------|" >> "$GITHUB_STEP_SUMMARY"
    echo "| Scenario | \`${{ inputs.scenario-dir }}\` |" >> "$GITHUB_STEP_SUMMARY"
    echo "| Timestamp | $(date -u +%Y-%m-%dT%H:%M:%SZ) |" >> "$GITHUB_STEP_SUMMARY"
    echo "| PR | #${{ github.event.pull_request.number }} |" >> "$GITHUB_STEP_SUMMARY"
    echo "| Actor | ${{ github.actor }} |" >> "$GITHUB_STEP_SUMMARY"
    echo "| Commit | \`${{ github.sha }}\` |" >> "$GITHUB_STEP_SUMMARY"
```

### Anti-Patterns to Avoid
- **Creating API keys inside the topic module:** API key secrets end up in Terraform state. State files must be encrypted at rest but the blast radius is large. Recommendation: DO NOT create API keys in the module. Document API key creation as a separate step or via Vault dynamic secrets.
- **Hardcoded KMS key IDs in module:** KMS key ARN/URI should be a variable, not hardcoded. Each cloud provider uses different formats.
- **Empty ruleset block:** The Confluent provider explicitly warns: "Do not define an empty `ruleset {}` block." Use `dynamic` blocks to conditionally include rulesets.
- **Skipping `shared = true` on KEK:** Without `shared = true`, the DEK Registry cannot call KMS to encrypt/decrypt DEKs, breaking CSFLE for Connect and ksqlDB workloads.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Service account lifecycle | Custom scripts to create/delete SAs | `confluent_service_account` Terraform resource | Terraform handles create/update/delete lifecycle, state tracking, import |
| OAuth identity mapping | Custom token validation middleware | `confluent_identity_provider` + `confluent_identity_pool` | CC handles token validation, claim extraction, audit logging natively |
| Field-level encryption | Custom encryption/decryption in app code | CSFLE via Schema Registry encryption rules | Schema Registry manages KEK/DEK lifecycle, key rotation, access control |
| Credential rotation | Custom rotation scripts from scratch | Vault KV v2 with TTL + multiple active API keys | Vault provides versioning, TTL, audit; Confluent allows multiple active keys per SA |
| Audit trail formatting | Custom audit log aggregation service | GitHub Actions `$GITHUB_STEP_SUMMARY` + annotations | Built-in, zero-cost, renders as markdown in workflow run page |
| Years-to-ms calculation | Manual ms values in tfvars | Terraform `locals` computation from `retention_years` variable | Eliminates arithmetic errors; validation ensures >= 7 years |

**Key insight:** Confluent Cloud provides all access control primitives natively (RBAC, OAuth, CSFLE, audit logs). The module's job is to wire them together declaratively and enforce FSI policies via Terraform validation blocks -- not to reimplement security logic.

## Common Pitfalls

### Pitfall 1: Terraform State Contains API Key Secrets
**What goes wrong:** Creating `confluent_api_key` resources in the topic module puts API key secrets in Terraform state. Anyone with state access can read all secrets.
**Why it happens:** Convenience -- single module call creates everything. But Terraform state is not a secrets store.
**How to avoid:** Do NOT create API keys in the topic module. Create them separately or use Vault dynamic secrets. Mark all credential variables as `sensitive = true`. Use encrypted state backends.
**Warning signs:** `terraform show` or state file reveals API key secrets in plaintext.

### Pitfall 2: CSFLE Requires Stream Governance Advanced
**What goes wrong:** CSFLE encryption rules fail at apply time if the Confluent Cloud environment doesn't have Stream Governance Advanced package.
**Why it happens:** CSFLE is a premium feature, not included in Essentials or Advanced without Stream Governance.
**How to avoid:** Document the Stream Governance Advanced prerequisite in the module README and scenario READMEs. Add a note in `variables.tf` that `data_classification = "confidential"` requires the Advanced package.
**Warning signs:** Schema registration fails with "encryption rules not supported" error.

### Pitfall 3: Empty Ruleset Blocks Break Terraform
**What goes wrong:** Defining an empty `ruleset {}` block causes provider errors.
**Why it happens:** The Confluent provider explicitly prohibits empty ruleset blocks.
**How to avoid:** Use `dynamic "ruleset"` blocks with `for_each` conditional on `data_classification == "confidential"`. Never produce an empty block.
**Warning signs:** `terraform plan` error on schema resource.

### Pitfall 4: OAuth Identity Pool Filter Too Permissive
**What goes wrong:** A broad CEL filter on the identity pool allows unintended identities to authenticate.
**Why it happens:** Default filter examples use broad `claims.aud` matching without restricting to specific groups or roles.
**How to avoid:** Always include group or role-based filter clauses. Document filter hardening in the scenario README. Example: `claims.aud=="confluent" && claims.groups.exists(g, g=="kafka-producers")`.
**Warning signs:** Audit logs show unexpected principals authenticating via OAuth.

### Pitfall 5: Dual-Credential Window Not Enforced
**What goes wrong:** Old API key revoked before all consumers update to new key, causing authentication failures.
**Why it happens:** Manual rotation without enforcing the overlap window.
**How to avoid:** Document the dual-credential window pattern explicitly: create new key -> deploy new key to all clients -> wait for configurable window (24h default) -> revoke old key. Use Vault TTL to enforce window.
**Warning signs:** Consumer authentication failures immediately after rotation.

### Pitfall 6: RBAC Binding Race with SA Creation
**What goes wrong:** RBAC binding created before service account is fully provisioned, causing API errors.
**Why it happens:** Terraform parallelism creates resources simultaneously.
**How to avoid:** Use `depends_on` or reference the SA resource directly in the binding's `principal` field (e.g., `principal = "User:${confluent_service_account.producer[each.key].id}"`). Terraform's reference graph handles ordering.
**Warning signs:** `terraform apply` fails with "principal not found" on role binding resources.

### Pitfall 7: KEK KMS Key ID Format Varies by Cloud
**What goes wrong:** AWS ARN passed to Azure scenario or vice versa, causing KMS errors.
**Why it happens:** KMS key ID format is cloud-specific (ARN vs Key Vault URI vs GCP resource name).
**How to avoid:** Add validation blocks on `csfle_kms_key_id` with format-specific regex per `csfle_kms_type`. Document the expected format in variable descriptions.
**Warning signs:** `terraform apply` fails with KMS authentication/format errors on KEK resource.

## Code Examples

Verified patterns from official sources:

### Service Account with RBAC Binding
```hcl
# Source: GitHub confluentinc/terraform-provider-confluent docs
resource "confluent_service_account" "app_producer" {
  display_name = "app-producer"
  description  = "Service account for app producer"
}

resource "confluent_role_binding" "app_producer_write" {
  principal   = "User:${confluent_service_account.app_producer.id}"
  role_name   = "DeveloperWrite"
  crn_pattern = "${var.kafka_cluster_crn}/kafka=${var.kafka_cluster_id}/topic=${local.topic_name}"
}
```

### OAuth Identity Provider (Azure AD)
```hcl
# Source: GitHub confluentinc/terraform-provider-confluent docs
resource "confluent_identity_provider" "azure_ad" {
  display_name = "Azure AD (Entra ID)"
  description  = "Azure AD identity provider for OAUTHBEARER"
  issuer       = "https://login.microsoftonline.com/${var.azure_tenant_id}/v2.0"
  jwks_uri     = "https://login.microsoftonline.com/${var.azure_tenant_id}/discovery/v2.0/keys"
}

resource "confluent_identity_pool" "producers" {
  identity_provider {
    id = confluent_identity_provider.azure_ad.id
  }
  display_name   = "Kafka Producers"
  description    = "Pool for Azure AD authenticated producers"
  identity_claim = "sub"
  filter         = "claims.aud==\"${var.confluent_app_id}\" && claims.groups.exists(g, g==\"kafka-producers\")"
}
```

### OAuth Identity Provider (AWS IAM Identity Center)
```hcl
# Source: Confluent docs + provider conventions
resource "confluent_identity_provider" "aws_iam" {
  display_name = "AWS IAM Identity Center"
  description  = "AWS IAM IdP for OAUTHBEARER"
  issuer       = "https://${var.aws_sso_instance_id}.awsapps.com/start"
  jwks_uri     = "https://${var.aws_sso_instance_id}.awsapps.com/start/keys"
}
```

### OAuth Identity Provider (GCP Cloud Identity)
```hcl
# Source: Confluent docs + provider conventions
resource "confluent_identity_provider" "gcp_identity" {
  display_name = "GCP Cloud Identity"
  description  = "GCP Cloud Identity for OAUTHBEARER"
  issuer       = "https://accounts.google.com"
  jwks_uri     = "https://www.googleapis.com/oauth2/v3/certs"
}
```

### CSFLE KEK Registration
```hcl
# Source: GitHub confluentinc/terraform-provider-confluent docs
resource "confluent_schema_registry_kek" "pii_kek" {
  schema_registry_cluster {
    id = var.schema_registry_cluster_id
  }
  rest_endpoint = var.schema_registry_rest_endpoint
  credentials {
    key    = var.schema_registry_api_key
    secret = var.schema_registry_api_secret
  }

  name       = "pii-encryption-key"
  kms_type   = "aws-kms"  # or "azure-kms", "gcp-kms"
  kms_key_id = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-..."
  shared     = true  # Required for DEK Registry to call KMS
}
```

### KMS Key ID Formats by Cloud Provider
```hcl
# AWS KMS: ARN format
kms_key_id = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789abc"

# Azure Key Vault: Key Identifier URI
kms_key_id = "https://my-keyvault.vault.azure.net/keys/my-key/1234567890abcdef"

# GCP Cloud KMS: Resource name
kms_key_id = "projects/my-project/locations/us-central1/keyRings/my-keyring/cryptoKeys/my-key"
```

### Schema with CSFLE Encryption Rule
```hcl
# Source: GitHub confluentinc/terraform-provider-confluent docs
resource "confluent_schema" "value" {
  # ... schema config ...

  ruleset {
    domain_rules {
      name = "encryptPII"
      kind = "TRANSFORM"
      type = "ENCRYPT"
      mode = "WRITEREAD"
      tags = ["PII"]
      params = {
        "encrypt.kek.name" = "pii-encryption-key"
      }
    }
  }
}
```

### OAUTHBEARER Client Configuration (Java properties reference)
```properties
# Source: Confluent Cloud OAuth Configuration Reference
bootstrap.servers=<bootstrap-url>
security.protocol=SASL_SSL
sasl.mechanism=OAUTHBEARER
sasl.login.callback.handler.class=org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginCallbackHandler
sasl.oauthbearer.token.endpoint.url=https://login.microsoftonline.com/<tenant-id>/oauth2/v2.0/token
sasl.jaas.config=org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required \
  clientId='<client-id>' \
  scope='<scope>' \
  clientSecret='<client-secret>' \
  extension_logicalCluster='<cluster-id>' \
  extension_identityPoolId='<pool-id>';
```

### Vault Reference Pattern (KV v2)
```hcl
# Source: Vault KV v2 documentation / FSI convention (D-06)
# Path convention: secret/fsi-kafka/{env}/{domain}/{sa-name}

resource "vault_kv_secret_v2" "kafka_credentials" {
  mount = "secret"
  name  = "fsi-kafka/${var.environment}/${var.domain}/${var.sa_name}"

  data_json = jsonencode({
    api_key        = var.kafka_api_key
    api_secret     = var.kafka_api_secret
    bootstrap_url  = var.bootstrap_url
    cluster_id     = var.kafka_cluster_id
  })

  # TTL controls dual-credential window
  custom_metadata {
    max_versions = 2  # Keep current + previous for dual-credential window
  }
}
```

### GitHub Actions Job Summary
```yaml
# Source: GitHub docs - $GITHUB_STEP_SUMMARY
- name: Write Compliance Audit Summary
  if: inputs.mode == 'apply'
  run: |
    {
      echo "## Terraform Apply -- Compliance Audit Trail"
      echo ""
      echo "| Property | Value |"
      echo "|----------|-------|"
      echo "| Scenario | \`${{ inputs.scenario-dir }}\` |"
      echo "| Timestamp | $(date -u +%Y-%m-%dT%H:%M:%SZ) |"
      echo "| Triggered by | PR merge to main |"
      echo "| Actor | ${{ github.actor }} |"
      echo "| Commit SHA | \`${{ github.sha }}\` |"
      echo "| Run ID | [${{ github.run_id }}](${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}) |"
      echo ""
      echo "### Validation Results"
      echo ""
      echo "| Check | Result |"
      echo "|-------|--------|"
      # Populate from validation script output
    } >> "$GITHUB_STEP_SUMMARY"
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| API keys only for CC auth | OAuth/OAUTHBEARER as primary, API keys as fallback | Confluent Cloud 2023+ | Auto-rotation, centralized identity, audit via IdP logs |
| Manual PII encryption in app code | CSFLE via Schema Registry encryption rules | Confluent Cloud 2024 | Declarative, schema-driven, automatic key rotation via DEK Registry |
| Confluent Terraform Provider v1 | Provider v2.x (v1 deprecated May 2025) | Nov 2024 | Breaking changes in resource naming; project already on v2.x |
| Custom audit log aggregation | GitHub Actions `$GITHUB_STEP_SUMMARY` | GitHub 2022+ | Built-in, zero-cost, markdown rendering in workflow runs |
| Hardcoded retention `-1` for compliance | Configurable `retention_years` with ms calculation | This phase | Teams can specify 7-year, 10-year, etc. instead of always infinite |

**Deprecated/outdated:**
- Confluent Terraform Provider v1: Deprecated Nov 2024, EOL May 2025. Project already uses `~> 2.0`.
- CSPE (Client-Side Payload Encryption): Newer alternative to CSFLE for full payload encryption. Not suitable here because FSI needs field-level granularity.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Terraform test (`terraform test`) with mock providers |
| Config file | `modules/topic/tests/governance.tftest.hcl` (exists) |
| Quick run command | `terraform test -filter=tests/governance.tftest.hcl` (from `modules/topic/`) |
| Full suite command | `cd modules/topic && terraform test` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| RBAC-01 | SA created when `create_service_accounts = true`; skipped when false | unit (terraform test) | `cd modules/topic && terraform test -filter=tests/access-control.tftest.hcl` | -- Wave 0 |
| RBAC-02 | RBAC bindings use effective SA IDs regardless of creation mode | unit (terraform test) | `cd modules/topic && terraform test -filter=tests/access-control.tftest.hcl` | -- Wave 0 |
| RBAC-03 | OAuth IdP/pool resources created in scenario directories | unit (terraform validate) | `cd scenarios/cc-azure && terraform init -backend=false && terraform validate` | -- Wave 0 (validate only) |
| RBAC-04 | Vault reference pattern validates with `terraform validate` | unit (terraform validate) | `terraform validate` on reference module | -- Wave 0 |
| COMP-01 | Compliance retention calculates correctly from years | unit (terraform test) | `cd modules/topic && terraform test -filter=tests/compliance.tftest.hcl` | -- Wave 0 |
| COMP-02 | Confidential topics require consumer SAs + PII fields; CSFLE rule attached | unit (terraform test) | `cd modules/topic && terraform test -filter=tests/compliance.tftest.hcl` | -- Wave 0 |
| COMP-04 | CI workflow writes job summary (manual verification) | manual-only | Inspect workflow run in GitHub UI | N/A |

### Sampling Rate
- **Per task commit:** `cd modules/topic && terraform test` (quick, uses mock provider)
- **Per wave merge:** Full test suite + `terraform validate` on all scenario directories
- **Phase gate:** All terraform tests green + `terraform validate` passes for all scenarios before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `modules/topic/tests/access-control.tftest.hcl` -- covers RBAC-01, RBAC-02 (SA creation/reference, RBAC binding correctness)
- [ ] `modules/topic/tests/compliance.tftest.hcl` -- covers COMP-01, COMP-02 (retention_years calculation, confidential topic validation, CSFLE rule presence)
- [ ] Update `modules/topic/tests/governance.tftest.hcl` -- extend existing tests to cover new compliance retention variables

## Open Questions

1. **API Key Creation in Module**
   - What we know: `confluent_api_key` resource puts secrets in Terraform state. Confluent best practices recommend separate key management.
   - What's unclear: User's preference -- convenience vs security tradeoff (marked as Claude's Discretion in D-01).
   - Recommendation: DO NOT create API keys in the topic module. Document API key creation as a separate step or via Vault dynamic secrets. This is the safer choice for FSI. The module creates SAs and RBAC bindings; API keys are a separate concern.

2. **CSFLE KEK Shared vs Non-Shared**
   - What we know: `shared = true` allows DEK Registry to call KMS directly. Required for Connect and ksqlDB to process encrypted data.
   - What's unclear: Whether all FSI deployments want shared KEK access (security teams may object to Confluent having KMS access).
   - Recommendation: Default to `shared = true` in the module but document the security implications. Add a `csfle_shared_kek` variable defaulting to `true`.

3. **Stream Governance Package Level Verification**
   - What we know: CSFLE requires Stream Governance Advanced. No way to check this in Terraform at plan time.
   - What's unclear: Whether all target CC environments have this package.
   - Recommendation: Document the prerequisite clearly. The module will fail at apply time with a descriptive error if the package is missing. No pre-check needed.

4. **OAuth IdP Token Endpoint URLs**
   - What we know: Azure AD uses `https://login.microsoftonline.com/{tenant}/oauth2/v2.0/token`. AWS IAM Identity Center and GCP Cloud Identity URLs vary by instance.
   - What's unclear: Exact AWS IAM Identity Center OIDC issuer URL format varies by AWS SSO instance configuration.
   - Recommendation: Document the IdP URL patterns in each scenario's README with placeholders. Teams fill in their instance-specific values.

## Sources

### Primary (HIGH confidence)
- [Confluent Terraform Provider - GitHub docs](https://github.com/confluentinc/terraform-provider-confluent/tree/master/docs) - `confluent_service_account`, `confluent_identity_provider`, `confluent_identity_pool`, `confluent_schema_registry_kek`, `confluent_schema_registry_dek`, `confluent_api_key`, `confluent_schema` (ruleset) resource schemas
- [Confluent Cloud CSFLE Overview](https://docs.confluent.io/cloud/current/security/encrypt/csfle/overview.html) - CSFLE architecture, KEK/DEK model, KMS provider support
- [Confluent Cloud OAuth Overview](https://docs.confluent.io/cloud/current/security/authenticate/workload-identities/identity-providers/oauth/overview.html) - OAuth/OAUTHBEARER flow, identity pools, claim filtering
- [Confluent Cloud Audit Log Concepts](https://docs.confluent.io/cloud/current/monitoring/audit-logging/cloud-audit-log-concepts.html) - Audit log event categories, topic operation tracking
- [GitHub Actions Job Summaries](https://github.blog/news-insights/product-news/supercharging-github-actions-with-job-summaries/) - `$GITHUB_STEP_SUMMARY` usage, markdown rendering

### Secondary (MEDIUM confidence)
- [Confluent Blog - Azure AD with OAuth](https://www.confluent.io/blog/configuring-azure-ad-ds-with-oauth-for-confluent/) - Azure AD configuration walkthrough
- [HCP Vault Secrets - Confluent Integration](https://developer.hashicorp.com/hcp/docs/vault-secrets/auto-rotation/create-rotating-secret/confluent) - Vault auto-rotation for Confluent keys
- [Confluent API Key Best Practices](https://docs.confluent.io/cloud/current/security/authenticate/workload-identities/service-accounts/api-keys/best-practices-api-keys.html) - Multiple active keys per SA, rotation guidance

### Tertiary (LOW confidence)
- AWS IAM Identity Center OIDC issuer URL format -- varies by instance; documented in each org's SSO configuration. Could not verify a canonical URL pattern from official Confluent docs.
- GCP Cloud Identity OIDC integration with Confluent Cloud -- Google uses `https://accounts.google.com` as issuer but specific Confluent Cloud integration guides were not found in search.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All Terraform resources verified via GitHub provider docs, GA status confirmed
- Architecture: HIGH - Patterns follow existing module conventions (`for_each`, SLA-tier multiplier, `dynamic` blocks); CSFLE ruleset syntax verified from provider docs
- Pitfalls: HIGH - API key state sensitivity, empty ruleset block prohibition, Stream Governance requirement all documented in official sources
- OAuth configuration: MEDIUM - Azure AD well-documented; AWS IAM Identity Center and GCP Cloud Identity OIDC endpoints need per-instance verification
- Vault integration: MEDIUM - Reference pattern documented; dual-credential window is a documented Confluent capability (multiple active keys per SA) but specific Vault TTL patterns are architectural guidance rather than verified implementation

**Research date:** 2026-03-22
**Valid until:** 2026-04-22 (30 days - Confluent Terraform provider is actively maintained but core resources are stable)

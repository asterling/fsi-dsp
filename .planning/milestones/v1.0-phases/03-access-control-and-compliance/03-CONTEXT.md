# Phase 3: Access Control and Compliance - Context

**Gathered:** 2026-03-22
**Status:** Ready for planning

<domain>
## Phase Boundary

Production-grade access control and compliance enforcement across CC deployment models. Service accounts provisioned automatically alongside topics, OAuth/OAUTHBEARER configured per cloud provider, credential rotation via Vault with zero-downtime dual-credential window, data classification enforcement with field-level encryption for confidential topics, and audit trail documentation mapping PR-to-verify chain for regulatory examiners. Lays the RBAC pattern that future CFK/CP scenarios will extend.

</domain>

<decisions>
## Implementation Decisions

### Service Account Provisioning
- **D-01:** Service accounts created inside the topic module — one module call produces SA + topic + schema + RBAC + DR mirror. No separate SA creation step required for teams.
- **D-02:** Create-or-reference pattern — module accepts optional existing SA IDs. If not provided, creates new `confluent_service_account` resources. If provided, skips creation and binds RBAC to existing SAs. Handles both dedicated and shared SA scenarios.
- **D-03:** Per-scenario OAuth config files — each scenario directory gets an `oauth.tf` or OAuth configuration example showing IdP integration for that cloud (Azure AD/Entra ID for Azure, AWS IAM Identity Center for AWS, GCP Cloud Identity for GCP). References ADR-006.

### Credential Rotation & Vault
- **D-04:** Reference pattern + docs — Terraform module for Vault secret engine configuration, example rotation policy, dual-credential window documentation. No live Vault dependency in CI. Teams adapt to their Vault instance.
- **D-05:** Time-based dual-credential window — new credential created, both valid for configurable window (e.g., 24h default). After window expires, old credential revoked. Documented in rotation runbook with Vault TTL settings.
- **D-06:** Prescriptive Vault path convention — `secret/fsi-kafka/{env}/{domain}/{sa-name}`. All examples, docs, and rotation scripts use this convention. Teams expected to follow it.
- **D-07:** Vault primary, cloud-native documented — Vault is the golden path with full reference Terraform pattern. AWS Secrets Manager, Azure Key Vault, GCP Secret Manager get per-scenario doc sections showing equivalent rotation approach. No Terraform for cloud-native secret managers.

### Data Classification Enforcement
- **D-08:** Full encryption enforcement for confidential topics — Confluent CSFLE (client-side field-level encryption) via Schema Registry encryption rules. PII fields encrypted at producer, decrypted at authorized consumer. Requires KMS integration (Vault or cloud KMS per provider).
- **D-09:** Terraform validation for confidential topics — at least one consumer SA explicitly listed (no open access), PII fields must be non-empty, consumer group pattern restricted to named SAs only. Enforced via Terraform validation blocks in topic module.
- **D-10:** Audit log tagging + alert rules for enhanced logging — tag confidential topic operations in Confluent Cloud audit logs. Provide alert rule templates that trigger on unauthorized access attempts to confidential topics. Leverages CC's built-in audit log.
- **D-11:** Configurable compliance retention — add `retention_years` variable for compliance tier. Default -1 (infinite), but teams can set 7, 10, etc. (calculated to ms). CI validates compliance topics have retention >= 7 years or infinite.

### Audit Trail & Compliance Documentation
- **D-12:** CI annotations + compliance guide — GitHub Actions workflow annotations on apply jobs (PR link, reviewer, timestamp, validation result). Plus `docs/compliance-guide.md` mapping each step to regulatory controls. Examiners follow the doc, click links to GitHub artifacts.
- **D-13:** Generic FSI control mapping — map steps to generic control categories: change management, access control, segregation of duties, audit logging. Teams map to their specific frameworks (OCC, FFIEC, PRA). More reusable across jurisdictions.
- **D-14:** Enhanced PR template — update `.github/PULL_REQUEST_TEMPLATE.md` with checkboxes: data classification reviewed, RBAC verified, schema compatibility checked, compliance tier justified. Guides reviewers and creates audit evidence.
- **D-15:** Workflow summary + annotations — terraform apply job writes a GitHub Actions job summary with: resources created/modified, validation PASS/FAIL per check, timestamp, PR link. Visible in workflow run page. No extra artifacts.

### Claude's Discretion
- Whether topic module creates API keys for provisioned SAs (security vs convenience trade-off given Terraform state sensitivity)
- Exact CSFLE encryption rule syntax and KMS key reference format per cloud provider
- CI validation script implementation for compliance retention floor check
- Rotation runbook structure and step ordering
- Alert rule template format for confidential topic access monitoring

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Access Control Architecture
- `docs/adr/006-oauth-vs-api-keys.md` -- OAuth/OAUTHBEARER as primary for CC, API keys as fallback, per-deployment-model auth matrix
- `docs/adr/008-dr-tier-classification.md` -- SLA tier definitions, RPO/RTO targets, compliance tier RPO=0 strategy

### Existing Topic Module (enhancement target)
- `modules/topic/main.tf` -- Current RBAC bindings (DeveloperWrite/DeveloperRead, consumer group, SR read/write). SA provisioning and CSFLE to be added here
- `modules/topic/variables.tf` -- Current `producer_service_accounts` and `consumer_service_accounts` as list(string), `data_classification` variable with no enforcement, `sla_tier` with compliance option

### Scenario Directories (OAuth config targets)
- `scenarios/cc-azure/` -- Azure scenario, OAuth config for Azure AD/Entra ID
- `scenarios/cc-aws/` -- AWS scenario, OAuth config for AWS IAM Identity Center
- `scenarios/cc-gcp/` -- GCP scenario, OAuth config for GCP Cloud Identity

### CI Pipeline (audit trail enhancement target)
- `.github/workflows/terraform-scenario.yml` -- Reusable workflow from Phase 2, annotations and job summary to be added
- `.github/PULL_REQUEST_TEMPLATE.md` -- PR template to be enhanced with compliance checkboxes

### Prior Phase Context
- `.planning/phases/01-shared-governance-foundation/01-CONTEXT.md` -- Phase 1 decisions: compliance SLA tier (D-03), externalized config (D-05-D-07), ADR decisions (D-14-D-16)
- `.planning/phases/02-cc-multi-cloud-scenarios/02-CONTEXT.md` -- Phase 2 decisions: scenario directory structure, reusable CI workflow, post-apply validation

### Cloud Provider Differences
- `docs/cloud-providers.md` -- Azure vs AWS vs GCP differences (networking, auth, secrets, backend)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `modules/topic/main.tf`: RBAC bindings for DeveloperWrite/DeveloperRead + consumer group + SR read/write already exist. SA provisioning adds `confluent_service_account` resource and create-or-reference conditional logic.
- `modules/topic/variables.tf`: `data_classification` variable exists with `confidential/internal/public` enum -- enforcement logic and CSFLE config adds conditional resources based on this value.
- `modules/topic/variables.tf`: `sla_tier` with `compliance` option and `retention_map` with -1 retention -- `retention_years` variable extends this.
- `.github/workflows/terraform-scenario.yml`: Reusable workflow from Phase 2 -- add job summary and annotations here for audit trail.
- `scripts/validate-apply.sh`: Post-apply validation script from Phase 2 -- PASS/FAIL output feeds into audit annotations.

### Established Patterns
- SLA tier as configuration multiplier: compatibility_map, partition_map, retention_map in locals -- data classification enforcement follows this pattern (classification drives CSFLE, validation, logging rules).
- `for_each = toset()` pattern for RBAC bindings -- same pattern for SA creation with create-or-reference conditional.
- Per-scenario files with identical structure -- OAuth config follows this (oauth.tf per scenario).
- Sensitive variables marked with `sensitive = true` -- API keys and Vault secrets follow this.

### Integration Points
- `modules/topic/main.tf` -> add `confluent_service_account` resource, CSFLE encryption rules, classification-based validation
- `modules/topic/variables.tf` -> add SA creation toggle, `retention_years`, CSFLE config variables
- `scenarios/cc-*/` -> add `oauth.tf` per scenario, Vault reference pattern
- `.github/workflows/terraform-scenario.yml` -> add job summary, annotations, compliance metadata
- `.github/PULL_REQUEST_TEMPLATE.md` -> add compliance checkboxes
- `docs/` -> add `compliance-guide.md`, rotation runbook

</code_context>

<specifics>
## Specific Ideas

- C4E golden path: one module call = fully provisioned, governed topic with SAs. Teams shouldn't need a multi-step process.
- Create-or-reference pattern is key for shared SAs across topics (e.g., fraud enrichment service consuming from multiple domains).
- Vault is the golden path for credential management, but cloud-native secret managers must be documented since not all FSIs run Vault.
- CSFLE for confidential topics is the strongest enforcement -- PII is encrypted at rest AND in transit at field level, only authorized consumers can decrypt.
- Compliance guide targets regulatory examiners who follow the audit chain from PR to deployed resource. Must be navigable by non-technical auditors.

</specifics>

<deferred>
## Deferred Ideas

None -- discussion stayed within phase scope

</deferred>

---

*Phase: 03-access-control-and-compliance*
*Context gathered: 2026-03-22*

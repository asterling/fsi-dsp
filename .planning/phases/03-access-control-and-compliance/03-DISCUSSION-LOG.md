# Phase 3: Access Control and Compliance - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md -- this log preserves the alternatives considered.

**Date:** 2026-03-22
**Phase:** 03-access-control-and-compliance
**Areas discussed:** Service account provisioning, Credential rotation & Vault, Data classification enforcement, Audit trail & compliance docs

---

## Service Account Provisioning

### Q1: SA Creation Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Inside topic module | Topic module creates confluent_service_account alongside topic/schema/RBAC. One module call = fully provisioned. | :heavy_check_mark: |
| Separate SA module | New modules/service-account/ module creates SAs independently. Topic module takes SA IDs as input. | |
| Scenario-level resources | SAs defined at scenario level. Topic module references them. | |

**User's choice:** Inside topic module
**Notes:** Simplifies team workflow -- one module call provisions everything.

### Q2: Shared SA Handling

| Option | Description | Selected |
|--------|-------------|----------|
| Create-or-reference pattern | Module accepts optional existing SA IDs. Creates new if not provided, binds RBAC if provided. | :heavy_check_mark: |
| Always create dedicated SAs | Every topic gets its own SAs. Shared access via same SA name in multiple calls. | |
| You decide | Claude picks based on provider capabilities. | |

**User's choice:** Create-or-reference pattern
**Notes:** Handles both dedicated and shared SA scenarios without SA sprawl.

### Q3: API Key Creation

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, create API keys | Module outputs SA API key/secret. Convenient but sensitive in state. | |
| No, SAs only | Module creates SAs and RBAC. API keys separate. | |
| You decide | Claude picks based on FSI security best practices. | :heavy_check_mark: |

**User's choice:** You decide (Claude's Discretion)
**Notes:** Claude to decide based on Terraform state security considerations.

### Q4: OAuth Config Per Cloud

| Option | Description | Selected |
|--------|-------------|----------|
| Per-scenario OAuth config files | Each scenario gets oauth.tf showing IdP integration for that cloud. | :heavy_check_mark: |
| Shared OAuth module | New modules/oauth/ abstracting IdP differences. | |
| Documentation only | OAuth setup in docs, no Terraform automation. | |

**User's choice:** Per-scenario OAuth config files
**Notes:** Follows established per-scenario pattern from Phase 2.

---

## Credential Rotation & Vault

### Q1: Vault Integration Level

| Option | Description | Selected |
|--------|-------------|----------|
| Reference pattern + docs | Terraform module for Vault config, example rotation policy, dual-credential docs. No live Vault in CI. | :heavy_check_mark: |
| Full Vault automation | Working integration with Confluent secrets engine, automated triggers, health checks. | |
| Documentation only | Step-by-step rotation docs. No Terraform Vault resources. | |

**User's choice:** Reference pattern + docs
**Notes:** Teams adapt to their Vault instance. Golden path without hard dependency.

### Q2: Dual-Credential Window

| Option | Description | Selected |
|--------|-------------|----------|
| Time-based window | Both credentials valid for configurable period (e.g., 24h), then old revoked. | :heavy_check_mark: |
| Health-check gated | New credential verified via health check before old is revoked. | |
| You decide | Claude picks based on FSI best practices. | |

**User's choice:** Time-based window
**Notes:** Documented in rotation runbook with Vault TTL settings.

### Q3: Vault Path Convention

| Option | Description | Selected |
|--------|-------------|----------|
| Prescriptive convention | Standard path: secret/fsi-kafka/{env}/{domain}/{sa-name}. | :heavy_check_mark: |
| Flexible with examples | Example paths with customizable scripts. | |
| You decide | Claude picks based on C4E philosophy. | |

**User's choice:** Prescriptive convention
**Notes:** Follows C4E golden-path philosophy.

### Q4: Secret Manager Support

| Option | Description | Selected |
|--------|-------------|----------|
| Vault primary, cloud-native documented | Vault golden path with full Terraform. Cloud-native gets per-scenario doc sections. | :heavy_check_mark: |
| All four equally supported | Terraform patterns for Vault + all 3 cloud-native managers. | |
| Vault only | Only Vault supported. Teams without Vault adapt on their own. | |

**User's choice:** Vault primary, cloud-native documented
**Notes:** Covers teams without Vault via documentation while keeping Vault as golden path.

---

## Data Classification Enforcement

### Q1: Confidential Topic Enforcement

| Option | Description | Selected |
|--------|-------------|----------|
| Terraform validation + RBAC tightening | Require consumer SAs, non-empty PII fields, restricted consumer groups. | |
| Full encryption enforcement | All of above PLUS Confluent CSFLE for PII fields, separate encryption key per classification. | :heavy_check_mark: |
| Metadata + documentation | Keep as metadata tag. Compliance docs explain what teams should do. | |

**User's choice:** Full encryption enforcement
**Notes:** Strongest enforcement -- PII encrypted at field level.

### Q2: Encryption Approach

| Option | Description | Selected |
|--------|-------------|----------|
| Confluent CSFLE via Schema Registry | Client-side field-level encryption with SR encryption rules. KMS integration required. | :heavy_check_mark: |
| Topic-level encryption at rest only | Built-in CC encryption at rest + TLS in transit. No field-level. | |
| You decide | Claude picks based on CSFLE maturity. | |

**User's choice:** Confluent CSFLE via Schema Registry
**Notes:** PII encrypted at producer, only authorized consumers decrypt.

### Q3: Enhanced Logging

| Option | Description | Selected |
|--------|-------------|----------|
| Audit log tagging + alert rules | Tag operations in CC audit logs. Alert templates for unauthorized access. | :heavy_check_mark: |
| Custom audit topic | Dedicated audit topic with producer interceptor logging access. | |
| You decide | Claude picks based on CC audit log capabilities. | |

**User's choice:** Audit log tagging + alert rules
**Notes:** Leverages CC built-in audit log rather than custom infrastructure.

### Q4: Compliance Retention

| Option | Description | Selected |
|--------|-------------|----------|
| Configurable retention override | Add retention_years variable. Default -1, teams can set 7/10/etc. CI validates >= 7 years. | :heavy_check_mark: |
| Keep infinite as-is | Compliance tier stays -1. Archival platform manages lifecycle. | |
| You decide | Claude picks based on regulatory requirements. | |

**User's choice:** Configurable retention override
**Notes:** Extends Phase 1 compliance tier with explicit year-based configuration.

---

## Audit Trail & Compliance Docs

### Q1: Audit Trail Form

| Option | Description | Selected |
|--------|-------------|----------|
| CI annotations + compliance guide | GH Actions annotations + docs/compliance-guide.md mapping steps to controls. | :heavy_check_mark: |
| Structured audit log output | JSON audit record per apply as workflow artifact. | |
| Both | Annotations AND JSON output. | |

**User's choice:** CI annotations + compliance guide
**Notes:** Examiners follow the doc, click links to GitHub artifacts.

### Q2: Regulatory Framework Mapping

| Option | Description | Selected |
|--------|-------------|----------|
| Generic FSI controls | Map to generic categories: change mgmt, access control, segregation, audit logging. | :heavy_check_mark: |
| Specific framework mapping | Explicit mapping to OCC, FFIEC, PRA. | |
| You decide | Claude picks based on C4E philosophy. | |

**User's choice:** Generic FSI controls
**Notes:** More reusable across jurisdictions. Teams map to their specific frameworks.

### Q3: PR Template Updates

| Option | Description | Selected |
|--------|-------------|----------|
| Enhanced PR template | Add compliance checkboxes: classification reviewed, RBAC verified, schema checked, tier justified. | :heavy_check_mark: |
| Separate compliance checklist | New COMPLIANCE_CHECKLIST.md referenced in PR template. | |
| No PR changes | Audit trail relies on CI outputs only. | |

**User's choice:** Enhanced PR template
**Notes:** Creates structured audit evidence in every PR.

### Q4: Apply Validation Receipts

| Option | Description | Selected |
|--------|-------------|----------|
| Workflow summary + annotations | Job summary with resources, PASS/FAIL, timestamp, PR link. | :heavy_check_mark: |
| Downloadable audit artifact | compliance-receipt.json as workflow artifact. | |
| You decide | Claude picks based on simplicity with existing reusable workflow. | |

**User's choice:** Workflow summary + annotations
**Notes:** Visible in workflow run page. No extra artifact management.

---

## Claude's Discretion

- API key creation for provisioned SAs (security vs convenience)
- CSFLE encryption rule syntax and KMS key reference format per cloud
- CI validation for compliance retention floor
- Rotation runbook structure
- Alert rule template format for confidential topic access

## Deferred Ideas

None -- discussion stayed within phase scope

---
phase: 03-access-control-and-compliance
plan: 02
subsystem: auth
tags: [oauth, oauthbearer, vault, csfle, kms, credential-rotation, identity-provider]

# Dependency graph
requires:
  - phase: 02-cc-multi-cloud-scenarios
    provides: "Scenario directories (cc-azure, cc-aws, cc-gcp) with Terraform configs"
  - phase: 01-shared-governance-foundation
    provides: "ADR-006 (OAuth vs API Keys), ADR-008 (DR tier classification)"
provides:
  - "OAuth identity provider + identity pool resources per CC scenario"
  - "Vault KV v2 reference patterns with prescriptive path convention"
  - "Credential rotation runbook with dual-credential window procedure"
  - "CSFLE setup guide covering all KMS providers"
affects: [03-access-control-and-compliance, 04-flink-runtime]

# Tech tracking
tech-stack:
  added: [confluent_identity_provider, confluent_identity_pool, vault_kv_secret_v2]
  patterns: [per-scenario-oauth-config, vault-path-convention, dual-credential-rotation]

key-files:
  created:
    - scenarios/cc-azure/oauth.tf
    - scenarios/cc-azure/variables-oauth.tf
    - scenarios/cc-azure/vault.tf.example
    - scenarios/cc-aws/oauth.tf
    - scenarios/cc-aws/variables-oauth.tf
    - scenarios/cc-aws/vault.tf.example
    - scenarios/cc-gcp/oauth.tf
    - scenarios/cc-gcp/variables-oauth.tf
    - scenarios/cc-gcp/vault.tf.example
    - docs/rotation-runbook.md
    - docs/csfle-guide.md
  modified: []

key-decisions:
  - "OAuth identity pools use group-based CEL filters (not broad audience-only) for security"
  - "Vault .tf.example files are commented-out HCL (not active Terraform) to avoid provider dependency"
  - "Cloud-native secret managers documented in runbook but not Terraform-ized (per D-07)"

patterns-established:
  - "Per-scenario OAuth: each CC scenario has oauth.tf + variables-oauth.tf for its cloud IdP"
  - "Vault path convention: secret/fsi-kafka/{env}/{domain}/{sa-name}"
  - "Dual-credential rotation: 7-step procedure with configurable overlap window"

requirements-completed: [RBAC-03, RBAC-04]

# Metrics
duration: 5min
completed: 2026-03-23
---

# Phase 03 Plan 02: OAuth/Vault/CSFLE Summary

**Per-scenario OAuth identity providers (Azure AD, AWS IAM, GCP Cloud Identity) with Vault credential rotation runbook and CSFLE setup guide covering all KMS providers**

## Performance

- **Duration:** 5 min
- **Started:** 2026-03-24T01:44:15Z
- **Completed:** 2026-03-24T01:49:02Z
- **Tasks:** 2
- **Files modified:** 11

## Accomplishments

- OAuth identity provider + identity pool resources for all three CC scenarios (Azure AD, AWS IAM Identity Center, GCP Cloud Identity) with group-based CEL filters
- Vault KV v2 reference patterns using prescriptive `secret/fsi-kafka/{env}/{domain}/{sa-name}` path convention with cloud-native alternatives documented
- Credential rotation runbook covering the 7-step dual-credential window procedure, Vault TTL enforcement, cloud-native alternatives (Azure Key Vault, AWS Secrets Manager, GCP Secret Manager), OAuth token rotation, and emergency rotation
- CSFLE setup guide with KEK/DEK architecture, per-provider KMS setup (AWS KMS, Azure Key Vault, GCP Cloud KMS, Vault Transit), Terraform configuration, Java/.NET client examples, and troubleshooting

## Task Commits

Each task was committed atomically:

1. **Task 1: Create per-scenario OAuth identity provider configs and Vault reference patterns** - `c23d3e5` (feat)
2. **Task 2: Create credential rotation runbook and CSFLE setup guide** - `d8fef2f` (docs)

## Files Created/Modified

- `scenarios/cc-azure/oauth.tf` - Azure AD identity provider + producer/consumer identity pools
- `scenarios/cc-azure/variables-oauth.tf` - Azure-specific OAuth variables (tenant ID, app ID, group IDs)
- `scenarios/cc-azure/vault.tf.example` - Vault reference pattern with Azure Key Vault alternative
- `scenarios/cc-aws/oauth.tf` - AWS IAM Identity Center provider + producer/consumer identity pools
- `scenarios/cc-aws/variables-oauth.tf` - AWS-specific OAuth variables (SSO instance ID, group names)
- `scenarios/cc-aws/vault.tf.example` - Vault reference pattern with AWS Secrets Manager alternative
- `scenarios/cc-gcp/oauth.tf` - GCP Cloud Identity provider + producer/consumer identity pools
- `scenarios/cc-gcp/variables-oauth.tf` - GCP-specific OAuth variables (org ID, group emails)
- `scenarios/cc-gcp/vault.tf.example` - Vault reference pattern with GCP Secret Manager alternative
- `docs/rotation-runbook.md` - Full credential rotation runbook with dual-credential window
- `docs/csfle-guide.md` - CSFLE setup guide with all KMS providers and troubleshooting

## Decisions Made

- OAuth identity pools use group-based CEL filters (e.g., `claims.groups.exists(g, g=="group-id")`) rather than broad audience-only matching, following Pitfall #4 guidance from research
- Vault reference patterns use commented-out HCL (not active Terraform) in `.example` files to avoid requiring the Vault provider during `terraform validate`
- Cloud-native secret managers (Azure Key Vault, AWS Secrets Manager, GCP Secret Manager) are documented in the rotation runbook with rotation approaches but no Terraform patterns, per D-07

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- OAuth identity providers ready for use once teams configure their IdP variables in terraform.tfvars
- Vault reference patterns ready for teams to copy and adapt to their Vault instance
- Rotation runbook and CSFLE guide provide documentation foundation for Plans 03-01 (SA provisioning), 03-03 (compliance retention), and 03-04 (audit trail)

## Self-Check: PASSED

All 11 created files verified present. Both task commits (c23d3e5, d8fef2f) verified in git log.

---
*Phase: 03-access-control-and-compliance*
*Completed: 2026-03-23*

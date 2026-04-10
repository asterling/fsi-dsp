---
phase: 3
slug: access-control-and-compliance
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-22
---

# Phase 3 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Terraform test (`terraform test`) + Python (pytest) + Shell (bats/manual) |
| **Config file** | `modules/topic/tests/*.tftest.hcl` (existing), `ci/scripts/validate-schemas.py` |
| **Quick run command** | `cd modules/topic && terraform test` |
| **Full suite command** | `cd modules/topic && terraform test && python ci/scripts/validate-schemas.py && bash scripts/validate-apply.sh --dry-run` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `cd modules/topic && terraform test`
- **After every plan wave:** Run full suite command
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 03-01-01 | 01 | 1 | RBAC-01 | terraform test | `terraform test -filter=access_control` | Wave 0 (Plan 01 Task 2) | pending |
| 03-01-02 | 01 | 1 | RBAC-02 | terraform test | `terraform test -filter=access_control` | Wave 0 (Plan 01 Task 2) | pending |
| 03-01-03 | 01 | 1 | RBAC-03 | terraform test | `terraform test -filter=access_control` | Wave 0 (Plan 01 Task 2) | pending |
| 03-01-04 | 01 | 1 | RBAC-04 | terraform test | `terraform test -filter=access_control` | Wave 0 (Plan 01 Task 2) | pending |
| 03-02-01 | 02 | 2 | COMP-01 | terraform test | `terraform test -filter=compliance` | Wave 0 (Plan 03 Task 2) | pending |
| 03-02-02 | 02 | 2 | COMP-02 | terraform test | `terraform test -filter=compliance` | Wave 0 (Plan 03 Task 2) | pending |
| 03-02-03 | 02 | 2 | COMP-04 | terraform test + python | `terraform test && python ci/scripts/validate-schemas.py` | N/A (CI workflow) | pending |

*Status: pending / green / red / flaky*

---

## Wave 0 Requirements

- [x] `modules/topic/tests/access-control.tftest.hcl` -- Plan 01 Task 2 creates this (SA creation/reference, RBAC binding correctness)
- [x] `modules/topic/tests/compliance.tftest.hcl` -- Plan 03 Task 2 creates this (retention_years calculation, confidential topic validation, CSFLE rule presence)

*Existing `governance.tftest.hcl` covers base governance. Wave 0 test files are created within their respective plans.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| OAuth IdP integration works end-to-end | RBAC-03 | Requires live IdP (Azure AD/AWS IAM/GCP) | Configure IdP, authenticate with OAUTHBEARER, produce/consume message |
| Vault credential rotation with dual-credential window | RBAC-04 | Requires live Vault instance | Create SA, rotate credential, verify both old+new work during window |
| CSFLE encrypt/decrypt with cloud KMS | COMP-02 | Requires live KMS and Schema Registry | Produce with PII encryption, consume with authorized consumer, verify field-level encryption |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 30s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** validated

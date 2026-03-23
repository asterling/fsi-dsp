---
phase: 3
slug: access-control-and-compliance
status: draft
nyquist_compliant: false
wave_0_complete: false
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
| 03-01-01 | 01 | 1 | RBAC-01 | terraform test | `terraform test -filter=access_control` | ❌ W0 | ⬜ pending |
| 03-01-02 | 01 | 1 | RBAC-02 | terraform test | `terraform test -filter=access_control` | ❌ W0 | ⬜ pending |
| 03-01-03 | 01 | 1 | RBAC-03 | terraform test | `terraform test -filter=access_control` | ❌ W0 | ⬜ pending |
| 03-01-04 | 01 | 1 | RBAC-04 | terraform test | `terraform test -filter=access_control` | ❌ W0 | ⬜ pending |
| 03-02-01 | 02 | 2 | COMP-01 | terraform test | `terraform test -filter=compliance` | ❌ W0 | ⬜ pending |
| 03-02-02 | 02 | 2 | COMP-02 | terraform test | `terraform test -filter=compliance` | ❌ W0 | ⬜ pending |
| 03-02-03 | 02 | 2 | COMP-04 | terraform test + python | `terraform test && python ci/scripts/validate-schemas.py` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `modules/topic/tests/access_control.tftest.hcl` — SA provisioning, RBAC bindings, create-or-reference
- [ ] `modules/topic/tests/compliance.tftest.hcl` — compliance tier retention, data classification enforcement
- [ ] `modules/topic/tests/oauth.tftest.hcl` — OAuth resource creation per scenario

*Existing `governance.tftest.hcl` covers base governance but not access control or compliance-specific behaviors.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| OAuth IdP integration works end-to-end | RBAC-03 | Requires live IdP (Azure AD/AWS IAM/GCP) | Configure IdP, authenticate with OAUTHBEARER, produce/consume message |
| Vault credential rotation with dual-credential window | RBAC-04 | Requires live Vault instance | Create SA, rotate credential, verify both old+new work during window |
| CSFLE encrypt/decrypt with cloud KMS | COMP-02 | Requires live KMS and Schema Registry | Produce with PII encryption, consume with authorized consumer, verify field-level encryption |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending

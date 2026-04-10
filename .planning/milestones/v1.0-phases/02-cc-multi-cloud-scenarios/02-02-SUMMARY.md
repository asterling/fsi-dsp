---
phase: 02-cc-multi-cloud-scenarios
plan: 02
subsystem: infra
tags: [github-actions, ci-cd, terraform, confluent-cloud, post-apply-validation, reusable-workflow]

# Dependency graph
requires:
  - phase: 02-cc-multi-cloud-scenarios/01
    provides: "Scenario directories (cc-azure, cc-aws, cc-gcp) with Terraform configs"
provides:
  - "Post-apply validation script (validate-apply.sh) checking 4 resource types"
  - "Reusable CI workflow (terraform-scenario.yml) with lint/plan/apply/validate"
  - "6 per-scenario caller workflows (plan+apply for azure/aws/gcp)"
  - "Deprecated old terraform-plan.yml and terraform-apply.yml"
affects: [03-advanced-governance, 04-observability, 05-dr-framework]

# Tech tracking
tech-stack:
  added: [curl-based-rest-validation]
  patterns: [reusable-github-actions-workflow, per-scenario-caller-pattern, post-apply-smoke-test]

key-files:
  created:
    - scripts/validate-apply.sh
    - .github/workflows/terraform-scenario.yml
    - .github/workflows/terraform-plan-azure.yml
    - .github/workflows/terraform-plan-aws.yml
    - .github/workflows/terraform-plan-gcp.yml
    - .github/workflows/terraform-apply-azure.yml
    - .github/workflows/terraform-apply-aws.yml
    - .github/workflows/terraform-apply-gcp.yml
  modified:
    - .github/workflows/terraform-plan.yml
    - .github/workflows/terraform-apply.yml

key-decisions:
  - "Reusable workflow uses mode input (plan/apply) to select job execution path"
  - "Post-apply validation is conditional on kafka-rest-endpoint input being provided"
  - "Old workflows deprecated with environments/** path trigger (no longer fires)"

patterns-established:
  - "Reusable workflow pattern: terraform-scenario.yml called by per-scenario callers"
  - "Post-apply validation pattern: curl-based REST API checks with PASS/FAIL/SKIP output"
  - "Caller workflow pattern: thin wrappers passing scenario-dir and mode to reusable workflow"

requirements-completed: [IAC-10]

# Metrics
duration: 3min
completed: 2026-03-22
---

# Phase 02 Plan 02: CI/CD Refactor and Post-Apply Validation Summary

**Reusable CI workflow with per-scenario callers and curl-based post-apply validation checking topics, schemas, RBAC, and DR mirrors via Confluent Cloud REST APIs**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-22T21:55:39Z
- **Completed:** 2026-03-22T21:58:39Z
- **Tasks:** 2
- **Files modified:** 10

## Accomplishments
- Created post-apply validation script (validate-apply.sh) that checks 4 resource types per topic with PASS/FAIL/SKIP output and actionable error messages
- Built reusable terraform-scenario.yml workflow consolidating all lint/validate/plan/apply/post-apply-validation logic
- Created 6 per-scenario caller workflows (plan + apply for azure, aws, gcp) with correct path triggers
- Deprecated old terraform-plan.yml and terraform-apply.yml with environments/** paths (no new triggers)

## Task Commits

Each task was committed atomically:

1. **Task 1: Create shared post-apply validation script** - `99248d3` (feat)
2. **Task 2: Create reusable CI workflow and per-scenario callers** - `fdfe2c6` (feat)

## Files Created/Modified
- `scripts/validate-apply.sh` - Post-apply validation: checks topic exists, schema registered, RBAC implicit, DR mirror conditional via Confluent Cloud REST APIs
- `.github/workflows/terraform-scenario.yml` - Reusable workflow with lint, plan, apply, and post-apply validation jobs
- `.github/workflows/terraform-plan-azure.yml` - Plan caller for CC-Azure scenario
- `.github/workflows/terraform-plan-aws.yml` - Plan caller for CC-AWS scenario
- `.github/workflows/terraform-plan-gcp.yml` - Plan caller for CC-GCP scenario
- `.github/workflows/terraform-apply-azure.yml` - Apply caller for CC-Azure scenario (env: fsi-cc-azure)
- `.github/workflows/terraform-apply-aws.yml` - Apply caller for CC-AWS scenario (env: fsi-cc-aws)
- `.github/workflows/terraform-apply-gcp.yml` - Apply caller for CC-GCP scenario (env: fsi-cc-gcp)
- `.github/workflows/terraform-plan.yml` - Deprecated, replaced by per-scenario plan workflows
- `.github/workflows/terraform-apply.yml` - Deprecated, replaced by per-scenario apply workflows

## Decisions Made
- Reusable workflow uses `mode` input (plan/apply) to conditionally run plan or apply job, keeping shared lint job always active
- Post-apply validation step is conditional on `kafka-rest-endpoint` input being non-empty (graceful skip if not configured)
- Old workflows retained in git with environments/** path trigger that will not fire on any current directory structure
- DR validation parameters are optional named args in validate-apply.sh; DR check shows SKIP (not FAIL) when not configured
- Topic names extracted from terraform output at runtime with fallback to reference-topics input

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None

## User Setup Required

None - no external service configuration required.

## Known Stubs

None - all workflows and scripts are fully wired with real logic.

## Next Phase Readiness
- Phase 02 is complete: 3 scenario directories with full Terraform configs + reusable CI with post-apply validation
- Ready for Phase 03 (advanced governance) or Phase 04 (observability)
- Apply callers need kafka-rest-endpoint/kafka-cluster-id inputs configured in GitHub environment settings to enable post-apply validation at runtime

## Self-Check: PASSED

All files verified present. Commits 99248d3 and fdfe2c6 confirmed in git log.

---
*Phase: 02-cc-multi-cloud-scenarios*
*Completed: 2026-03-22*

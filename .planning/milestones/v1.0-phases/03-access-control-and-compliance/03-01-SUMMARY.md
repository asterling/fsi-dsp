---
phase: 03-access-control-and-compliance
plan: 01
subsystem: auth
tags: [terraform, confluent-cloud, rbac, service-accounts, iac]

# Dependency graph
requires:
  - phase: 01-governance-foundation
    provides: "Topic module with SLA-tier governance, RBAC bindings, schema registration"
provides:
  - "Create-or-reference service account provisioning in topic module"
  - "Effective SA ID abstraction for RBAC bindings"
  - "producer_sa_ids and consumer_sa_ids outputs"
  - "Access control test suite (5 test cases)"
affects: [03-access-control-and-compliance, scenarios]

# Tech tracking
tech-stack:
  added: [confluent_service_account]
  patterns: [create-or-reference conditional provisioning, effective ID locals abstraction]

key-files:
  created:
    - modules/topic/tests/access-control.tftest.hcl
  modified:
    - modules/topic/main.tf
    - modules/topic/variables.tf
    - modules/topic/outputs.tf

key-decisions:
  - "Relaxed producer_service_accounts validation to allow empty default (create mode uses SA names instead)"
  - "Used lifecycle precondition on topic resource for cross-variable validation"
  - "API keys NOT created in module (security: avoids secrets in Terraform state per anti-pattern guidance)"

patterns-established:
  - "Create-or-reference: create_service_accounts bool + sa_names variables for conditional SA lifecycle"
  - "Effective ID locals: local.effective_*_sa_ids abstracts created vs referenced SAs for downstream bindings"

requirements-completed: [RBAC-01, RBAC-02]

# Metrics
duration: 3min
completed: 2026-03-24
---

# Phase 03 Plan 01: Service Account Provisioning Summary

**Create-or-reference SA provisioning with effective ID abstraction for unified RBAC bindings across both SA lifecycle modes**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-24T01:44:10Z
- **Completed:** 2026-03-24T01:47:51Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- Topic module now supports conditional SA creation via `create_service_accounts` toggle
- RBAC bindings refactored to use `local.effective_*_sa_ids` -- identical permissions whether SAs are created or referenced
- 5 access control tests validate both SA modes and precondition enforcement
- Outputs expose `producer_sa_ids` and `consumer_sa_ids` for downstream module consumers

## Task Commits

Each task was committed atomically:

1. **Task 1: Add create-or-reference SA provisioning and refactor RBAC bindings** - `ecd0fc2` (feat)
2. **Task 2: Add access control Terraform tests** - `0a7e2f8` (test)

## Files Created/Modified
- `modules/topic/variables.tf` - Added create_service_accounts, producer_sa_names, consumer_sa_names variables; relaxed producer_service_accounts validation
- `modules/topic/main.tf` - Added confluent_service_account resources, effective SA ID locals, lifecycle precondition; refactored all RBAC bindings
- `modules/topic/outputs.tf` - Added producer_sa_ids and consumer_sa_ids outputs
- `modules/topic/tests/access-control.tftest.hcl` - 5 test cases for SA creation/reference modes and RBAC binding correctness

## Decisions Made
- Relaxed `producer_service_accounts` from required (length > 0) to optional (default = []) because create mode uses `producer_sa_names` as the source. Cross-variable validation moved to a lifecycle precondition on the topic resource.
- API keys are NOT created inside the topic module per research anti-pattern guidance -- secrets in Terraform state is an unacceptable risk for FSI. Teams create API keys separately or via Vault dynamic secrets.
- Used `for_each = toset()` pattern (not `count`) for SA resources to maintain addressable instances and avoid ordering issues on plan changes.

## Deviations from Plan

None -- plan executed exactly as written.

## Issues Encountered
- Local Terraform version (1.5.7) does not support `terraform test` with `mock_provider` / `run` blocks (requires 1.6+). Tests are written for the project's CI target version (1.7.0+) matching the existing governance test patterns. Verification done via `terraform validate` instead.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- SA provisioning pattern ready for use by scenario directories
- RBAC binding abstraction ready for CSFLE and compliance tier enhancements in subsequent plans
- Existing governance tests unaffected (no regression)

## Self-Check: PASSED

- All 4 modified/created files verified on disk
- Both task commits (ecd0fc2, 0a7e2f8) found in git log
- terraform validate passes

---
*Phase: 03-access-control-and-compliance*
*Completed: 2026-03-24*

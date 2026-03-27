---
phase: 06-flink-on-confluent-cloud
plan: 01
subsystem: infra
tags: [terraform, flink, confluent-cloud, compute-pool, flink-sql, hcl]

# Dependency graph
requires:
  - phase: 02-cc-multi-cloud-scenarios
    provides: "CC scenario directories (cc-aws, cc-azure, cc-gcp) with topic module wiring pattern"
provides:
  - "modules/flink/ reusable Terraform module for CC Flink compute pool and SQL statement provisioning"
  - "Flink opt-in integration in all 3 CC scenario directories (AWS, AZURE, GCP)"
  - "Variable definitions for Flink configuration (cc_environment_id, flink_enabled, etc.)"
affects: [06-flink-on-confluent-cloud, observability, ci-cd]

# Tech tracking
tech-stack:
  added: [confluent_flink_compute_pool, confluent_flink_statement]
  patterns: [opt-in-module-via-count, for-each-statement-map, lifecycle-prevent-destroy]

key-files:
  created:
    - modules/flink/main.tf
    - modules/flink/variables.tf
    - modules/flink/outputs.tf
    - scenarios/cc-aws/flink.tf
    - scenarios/cc-aws/variables-flink.tf
    - scenarios/cc-azure/flink.tf
    - scenarios/cc-azure/variables-flink.tf
    - scenarios/cc-gcp/flink.tf
    - scenarios/cc-gcp/variables-flink.tf
  modified: []

key-decisions:
  - "Flink module uses for_each on flink_statements map allowing zero statements (pool-only provisioning)"
  - "Flink is opt-in via flink_enabled boolean (default false) using count conditional"
  - "max_cfu restricted to [5, 10, 20, 30, 40, 50] with validation block documenting increase-only constraint"
  - "cc_environment_id passed as dedicated variable, not extracted via regex from cluster ID"

patterns-established:
  - "Opt-in module pattern: count = var.feature_enabled ? 1 : 0 for scenario-level modules"
  - "Flink SQL statements as Terraform resources with prevent_destroy lifecycle"
  - "Shared variables-flink.tf across scenarios with cloud_provider hardcoded per scenario"

requirements-completed: [FLINK-01, FLINK-05]

# Metrics
duration: 3min
completed: 2026-03-27
---

# Phase 6 Plan 1: Flink Module & CC Scenario Wiring Summary

**Reusable Terraform module for CC Flink compute pool and SQL statement provisioning, wired into all 3 CC scenarios with opt-in flag and SR auto-discovery documented**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-27T01:23:44Z
- **Completed:** 2026-03-27T01:26:15Z
- **Tasks:** 2
- **Files modified:** 9

## Accomplishments
- Created modules/flink/ with confluent_flink_compute_pool and confluent_flink_statement resources following existing topic module pattern
- Wired Flink module into cc-aws, cc-azure, and cc-gcp scenario directories with correct cloud_provider per scenario
- All three scenarios pass terraform validate
- Documented SR auto-discovery (FLINK-05) so teams do not write manual CREATE TABLE for existing CC topics

## Task Commits

Each task was committed atomically:

1. **Task 1: Create modules/flink/ Terraform module** - `148f83a` (feat)
2. **Task 2: Wire Flink module into all three CC scenario directories** - `183c3f4` (feat)

## Files Created/Modified
- `modules/flink/main.tf` - Flink compute pool and SQL statement Terraform resources with lifecycle protection
- `modules/flink/variables.tf` - Module input variables with validation on compute_pool_name, cloud_provider, max_cfu
- `modules/flink/outputs.tf` - Module outputs: compute_pool_id, compute_pool_name, resource_name, statement_names
- `scenarios/cc-aws/flink.tf` - Flink module invocation with cloud_provider = AWS, opt-in via flink_enabled
- `scenarios/cc-aws/variables-flink.tf` - Flink variable declarations for AWS scenario
- `scenarios/cc-azure/flink.tf` - Flink module invocation with cloud_provider = AZURE
- `scenarios/cc-azure/variables-flink.tf` - Flink variable declarations for Azure scenario
- `scenarios/cc-gcp/flink.tf` - Flink module invocation with cloud_provider = GCP
- `scenarios/cc-gcp/variables-flink.tf` - Flink variable declarations for GCP scenario

## Decisions Made
- Flink module uses `for_each` on `flink_statements` map allowing zero statements (pool-only provisioning)
- Flink is opt-in via `flink_enabled` boolean (default false) using `count` conditional on the module call
- `max_cfu` restricted to [5, 10, 20, 30, 40, 50] with validation block documenting increase-only constraint (Pitfall 2)
- `cc_environment_id` passed as dedicated variable, not extracted via regex from cluster ID
- `lifecycle { prevent_destroy = true }` on both compute pool and statements (Pitfall 4)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Flink module ready for reference SQL templates (Plan 2: FLINK-04 SQL patterns)
- Flink module ready for observability integration (Plan 3: FLINK-06 metrics export)
- All three CC scenarios validated and ready for Flink provisioning when teams set flink_enabled = true

## Self-Check: PASSED

All 9 created files verified present. Both task commits (148f83a, 183c3f4) verified in git log.

---
*Phase: 06-flink-on-confluent-cloud*
*Completed: 2026-03-27*

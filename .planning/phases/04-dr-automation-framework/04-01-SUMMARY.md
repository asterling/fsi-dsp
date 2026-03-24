---
phase: 04-dr-automation-framework
plan: 01
subsystem: dr
tags: [bash, cli, dr-automation, cluster-linking, sla-tier, consul, connect, jq]

# Dependency graph
requires:
  - phase: 01-shared-governance-foundation
    provides: ADR-008 DR tier classification thresholds, ADR-003 Consul service discovery, ADR-005 Cluster Linking
provides:
  - Unified fsi-dr.sh CLI framework with pluggable backend dispatch
  - SLA tier threshold assessment functions (assess_lag, get_tier_threshold)
  - State file management with atomic writes (init_state, record_step, cleanup_state)
  - Connect state tracking (snapshot_connectors, get_running_connectors, pause/resume)
  - Pre-flight check suite (5 checks for cluster, mirror, Connect, Consul reachability)
  - Status command with per-topic lag table and SLA tier assessment
  - Backend dispatch pattern for cluster-linking (mm2 placeholder for Phase 8)
  - Unit test suite with 54 test cases for all pure functions
affects: [04-02, 04-03, 05-observability-templates, 08-cfk-cp-backends]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - Function dispatch for pluggable DR backends (FSI_DR_BACKEND env var)
    - Atomic state file writes via mktemp + mv pattern
    - SOURCED guard for test sourcing without main execution
    - Function-based threshold lookup for Bash 3.2 compatibility (replaces associative arrays)
    - Simple Bash assertion framework for unit testing (no external deps)

key-files:
  created:
    - scripts/fsi-dr.sh
    - tests/dr/test-fsi-dr-helpers.sh
  modified: []

key-decisions:
  - "Used function-based threshold lookup instead of declare -A associative arrays for Bash 3.2 compatibility (macOS default)"
  - "Corrected best-effort WARN test boundary: 3599 < 3600 threshold is OK, not WARN (plan had logical inconsistency)"
  - "Backend dispatch uses init_backend() function called at source time so tests get functions via sourcing"

patterns-established:
  - "Backend dispatch: FSI_DR_BACKEND selects cl_* or future mm2_* functions via init_backend() case statement"
  - "State file: /tmp/fsi-dr-state.json with atomic writes via mktemp + mv for crash safety"
  - "Test sourcing: SOURCED=true guard plus load_env() deferred loading prevents env var validation at source time"
  - "SLA tier thresholds: _tier_warn_threshold() and _tier_alert_threshold() functions encode ADR-008 values"

requirements-completed: [DR-03, DR-07, DR-08, DR-12]

# Metrics
duration: 5min
completed: 2026-03-24
---

# Phase 4 Plan 1: DR CLI Framework Summary

**Unified fsi-dr.sh CLI with pluggable backend dispatch, SLA-tier lag assessment per ADR-008, atomic state file tracking, and 54-test unit suite**

## Performance

- **Duration:** 5 min
- **Started:** 2026-03-24T03:33:37Z
- **Completed:** 2026-03-24T03:38:57Z
- **Tasks:** 2
- **Files created:** 2

## Accomplishments
- Created 630-line fsi-dr.sh CLI framework with all helper functions, backend dispatch, and status command
- Implemented SLA tier threshold assessment matching ADR-008 exactly (critical 30/60, standard 300/900, best-effort 3600/14400, compliance 10/30)
- Built atomic state file management for DR operation tracking (init, record_step, record_connectors, record_topics, cleanup)
- Created 54-test unit suite covering all pure functions with 0 failures

## Task Commits

Each task was committed atomically:

1. **Task 1: Create fsi-dr.sh CLI framework with helpers and status command** - `ad4967b` (feat)
2. **Task 2: Create unit tests for fsi-dr.sh helper functions** - `d92f937` (test)

## Files Created/Modified
- `scripts/fsi-dr.sh` - Unified DR CLI with framework, helpers, status command, backend dispatch (630 lines)
- `tests/dr/test-fsi-dr-helpers.sh` - Unit tests for all pure functions (345 lines, 54 test cases)

## Decisions Made
- **Bash 3.2 compatibility:** macOS ships Bash 3.2 which lacks associative arrays (`declare -A`). Replaced with function-based threshold lookups (`_tier_warn_threshold()`, `_tier_alert_threshold()`) that use case statements. Same interface, works on all Bash versions.
- **Test boundary correction:** Plan specified `assess_lag 3599 best-effort -> WARN` but 3599 < 3600 (warn threshold), so correct result is OK. Added additional test at boundary (3600 -> WARN) for completeness.
- **Backend initialization at source time:** `init_backend()` is called when script is sourced, so test files get backend functions defined. The `load_env()` for required env vars is deferred to command execution only.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Bash 3.2 compatibility for associative arrays**
- **Found during:** Task 1 (CLI framework creation)
- **Issue:** Plan specified `declare -A` associative arrays for SLA tier thresholds, but macOS ships Bash 3.2 which does not support associative arrays. Script failed with "unbound variable" error.
- **Fix:** Replaced associative array declarations with function-based lookups using case statements. Functions `_tier_warn_threshold()` and `_tier_alert_threshold()` provide identical interface.
- **Files modified:** scripts/fsi-dr.sh
- **Verification:** `bash scripts/fsi-dr.sh help` works; all 54 unit tests pass
- **Committed in:** ad4967b (Task 1 commit)

**2. [Rule 1 - Bug] Corrected best-effort WARN test boundary value**
- **Found during:** Task 2 (unit test creation)
- **Issue:** Plan specified `assess_lag 3599 best-effort -> WARN` but 3599 < 3600 (warn threshold), so the mathematically correct result is OK, not WARN.
- **Fix:** Changed test to expect OK for 3599, added additional boundary test at 3600 which correctly returns WARN.
- **Files modified:** tests/dr/test-fsi-dr-helpers.sh
- **Verification:** All 54 tests pass including corrected boundary tests
- **Committed in:** d92f937 (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (2 bugs)
**Impact on plan:** Both fixes necessary for correctness. Bash 3.2 compat is essential for macOS. Test boundary fix aligns test expectations with ADR-008 threshold math. No scope creep.

## Known Stubs

The following stubs are intentional and will be resolved by subsequent plans:

| File | Line | Stub | Resolving Plan |
|------|------|------|---------------|
| scripts/fsi-dr.sh | 430 | `cl_failover_mirrors()` prints "Not yet implemented -- see Plan 02" | 04-02 |
| scripts/fsi-dr.sh | 436 | `cl_failback_mirrors()` prints "Not yet implemented -- see Plan 03" | 04-03 |
| scripts/fsi-dr.sh | 564 | `cmd_failover()` prints "Not yet implemented -- see Plan 02" | 04-02 |
| scripts/fsi-dr.sh | 568 | `cmd_failback()` prints "Not yet implemented -- see Plan 03" | 04-03 |

These stubs do not prevent this plan's goal (CLI skeleton and helper functions). Plans 02 and 03 will implement the orchestration logic.

## Issues Encountered
None -- execution was clean after Bash 3.2 compatibility fix.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- CLI framework complete and tested; Plan 02 can implement failover orchestration by filling in `cmd_failover()` and `cl_failover_mirrors()`
- Plan 03 can implement failback by filling in `cmd_failback()` and `cl_failback_mirrors()`
- All helper functions (assess_lag, state management, Connect tracking, pre-flight) are ready for use
- Backend dispatch pattern established for Phase 8 MM2 adapter addition

## Self-Check: PASSED

- FOUND: scripts/fsi-dr.sh (630 lines, executable)
- FOUND: tests/dr/test-fsi-dr-helpers.sh (345 lines, 54 tests, 0 failures)
- FOUND: 04-01-SUMMARY.md
- FOUND: commit ad4967b (Task 1)
- FOUND: commit d92f937 (Task 2)

---
*Phase: 04-dr-automation-framework*
*Completed: 2026-03-24*

---
phase: 08-cfk-on-openshift
plan: 02
subsystem: dr
tags: [mirrormaker2, mm2, kafka-connect, failover, failback, dr, consul, bash]

# Dependency graph
requires:
  - phase: 04-dr-automation-framework
    provides: "fsi-dr.sh backend dispatch pattern, CL backend functions, state file, step orchestration"
provides:
  - "MM2 backend functions in fsi-dr.sh (mm2_preflight, mm2_failover_mirrors, mm2_failback_mirrors, mm2_get_mirror_lag, mm2_get_mirror_status)"
  - "MM2 backend unit test suite (22 tests)"
  - "DR runbook extended with MM2-specific procedures and comparison table"
affects: [09-cp-rhel-mrc, dr-operations]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "MM2 backend dispatch via init_backend() mm2 case"
    - "Connect REST API for MM2 connector lifecycle (pause/delete/create)"
    - "Reversed connector creation for MM2 failback (swap source/target aliases)"

key-files:
  created:
    - tests/dr/test-fsi-dr-mm2.sh
  modified:
    - scripts/fsi-dr.sh
    - tests/dr/test-fsi-dr-helpers.sh
    - docs/dr-runbook.md

key-decisions:
  - "MM2 failover pauses connectors without promotion (DR topics already writable per D-06)"
  - "MM2 failback reverses replication by deleting and recreating connectors with swapped source/target"
  - "MM2 per-topic lag reports -1 via REST API; Prometheus/JMX needed for granularity"
  - "curl mock pattern ordering critical -- specific patterns before generic URL match"
  - "Bash arithmetic uses || true guard for set -e compatibility"

patterns-established:
  - "MM2 backend function naming: mm2_{action} matching cl_{action} pattern"
  - "Mock curl pattern ordering: specific endpoint patterns before generic host patterns"

requirements-completed: [DR-05]

# Metrics
duration: 10min
completed: 2026-03-27
---

# Phase 8 Plan 02: MM2 DR Backend Summary

**MirrorMaker 2 backend for fsi-dr.sh with 5 backend functions, 22-test unit suite, and DR runbook extended with MM2 failover/failback procedures and CL vs MM2 comparison table**

## Performance

- **Duration:** 10 min
- **Started:** 2026-03-27T22:30:53Z
- **Completed:** 2026-03-27T22:40:57Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- Implemented all 5 MM2 backend functions in fsi-dr.sh, wired into backend dispatch
- Created comprehensive test suite with 22 passing tests covering dry-run and live modes
- Extended DR runbook with MM2 procedures, environment variables, comparison table, and troubleshooting
- All existing CL tests pass (54 helper + 33 dry-run = 87 regression tests green)

## Task Commits

Each task was committed atomically:

1. **Task 1: Implement MM2 backend functions** - `e43a8cb` (feat)
2. **Task 2: MM2 tests and DR runbook extension** - `1c02fb5` (feat)

## Files Created/Modified
- `scripts/fsi-dr.sh` - Added 5 MM2 backend functions (mm2_preflight, mm2_failover_mirrors, mm2_failback_mirrors, mm2_get_mirror_lag, mm2_get_mirror_status), MM2 env var defaults, updated backend dispatch
- `tests/dr/test-fsi-dr-mm2.sh` - 22 unit tests covering all MM2 backend functions with mocked Connect REST API
- `tests/dr/test-fsi-dr-helpers.sh` - Updated mm2 init_backend test assertion (was expecting failure, now expects success)
- `docs/dr-runbook.md` - Extended with MirrorMaker 2 DR Procedures section, MM2 env vars, comparison table, troubleshooting

## Decisions Made
- MM2 failover pauses all 3 connectors (source, checkpoint, heartbeat) -- DR topics are standard writable topics, no promotion needed (per D-06)
- MM2 failback deletes existing connectors and creates reversed ones with swapped source.cluster.alias/target.cluster.alias and bootstrap servers
- MM2 mirror lag reports connector-level state via REST API with lag=-1 sentinel to indicate per-topic granularity requires Prometheus/JMX
- Used `|| true` guard on all bash arithmetic increments for `set -e` compatibility (existing CL functions had same latent issue, fixed only in new MM2 functions)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed curl mock pattern ordering in test file**
- **Found during:** Task 2 (creating test file)
- **Issue:** Generic `*"8084/"*` pattern matched before specific `*/connectors/mm2-source-east-west/status*` because URLs like `http://localhost:8084/connectors/...` contain `8084/`
- **Fix:** Reordered case patterns to put specific connector endpoint patterns before generic health check pattern
- **Files modified:** tests/dr/test-fsi-dr-mm2.sh
- **Verification:** All 22 tests pass
- **Committed in:** 1c02fb5

**2. [Rule 1 - Bug] Fixed Bash arithmetic for set -e compatibility**
- **Found during:** Task 2 (running tests)
- **Issue:** `((pass++))` when pass=0 evaluates `((0))` which returns exit code 1, killing script under `set -e`
- **Fix:** Added `|| true` guard to all arithmetic increments in mm2_preflight and mm2_failover_mirrors
- **Files modified:** scripts/fsi-dr.sh
- **Verification:** mm2_preflight callable directly under set -e without unexpected exit
- **Committed in:** 1c02fb5

**3. [Rule 1 - Bug] Updated existing test assertion for mm2 backend**
- **Found during:** Task 1 (running regression tests)
- **Issue:** test-fsi-dr-helpers.sh asserted `FSI_DR_BACKEND=mm2 init_backend` should exit 1 (was a stub), now exits 0 (implemented)
- **Fix:** Changed assertion from expecting exit code 1 to expecting exit code 0
- **Files modified:** tests/dr/test-fsi-dr-helpers.sh
- **Verification:** All 54 helper tests pass
- **Committed in:** e43a8cb

---

**Total deviations:** 3 auto-fixed (3 bugs)
**Impact on plan:** All auto-fixes necessary for correctness. No scope creep.

## Issues Encountered
None beyond the auto-fixed deviations above.

## User Setup Required
None - no external service configuration required.

## Known Stubs
None - all functions are fully implemented.

## Next Phase Readiness
- MM2 backend is fully operational via `FSI_DR_BACKEND=mm2`
- DR runbook covers both CL and MM2 backends
- Ready for Phase 8 Plan 03 (CFK scenario directory) which can reference MM2 connector CRDs

---
*Phase: 08-cfk-on-openshift*
*Completed: 2026-03-27*

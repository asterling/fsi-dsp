---
phase: 11-core-governance-roles
plan: 01
subsystem: infra
tags: [ansible, confluent-platform, admin-rest-v3, topic-lifecycle, governance, molecule, sla-tier]

# Dependency graph
requires:
  - phase: 10-ansible-foundation-and-governance-scaffolding
    provides: "filter_plugins/fsi_governance.py (fsi_validate_topic_name, fsi_sla_lookup), vars/sla_tiers.yml, vars/naming_rules.yml, ansible-lint config, conftest.py"
provides:
  - "cp_topic Ansible role: create, update, delete topics on CP via Admin REST v3"
  - "GET-before-POST idempotent topic creation pattern"
  - "Config convergence via configs:alter endpoint"
  - "Check mode with GET-only state diff reporting"
  - "Guarded deletion with SLA tier protection"
  - "Error collection pattern (ignore_errors per-topic, summary at end)"
  - "Shared test fixtures: Admin REST v3 mock responses and CPTopic YAML samples"
  - "Molecule delegated driver scenario with idempotency verification"
affects: [11-02, 11-03, 12-orchestration, cp-topic-consumers]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "ansible.builtin.uri with retries/delay/until for transient error retry"
    - "check_mode: false on GET tasks to force execution in --check mode"
    - "Config values cast to string via | string filter for Admin REST v3 API"
    - "Error collection: ignore_errors on loop, set_fact for results summary, fail at end"
    - "Molecule delegated driver with Python http.server mock for CI-friendly testing"

key-files:
  created:
    - ansible/roles/cp_topic/defaults/main.yml
    - ansible/roles/cp_topic/meta/main.yml
    - ansible/roles/cp_topic/tasks/main.yml
    - ansible/roles/cp_topic/tasks/validate.yml
    - ansible/roles/cp_topic/tasks/create.yml
    - ansible/roles/cp_topic/tasks/update.yml
    - ansible/roles/cp_topic/tasks/delete.yml
    - ansible/roles/cp_topic/tasks/check.yml
    - ansible/roles/cp_topic/tasks/process_one.yml
    - ansible/roles/cp_topic/molecule/default/molecule.yml
    - ansible/roles/cp_topic/molecule/default/converge.yml
    - ansible/roles/cp_topic/molecule/default/verify.yml
    - tests/ansible/test_cp_topic.py
    - tests/ansible/fixtures/mock_responses/admin_rest_v3/topic_exists.json
    - tests/ansible/fixtures/mock_responses/admin_rest_v3/topic_not_found.json
    - tests/ansible/fixtures/mock_responses/admin_rest_v3/topic_configs.json
    - tests/ansible/fixtures/mock_responses/admin_rest_v3/topic_created.json
    - tests/ansible/fixtures/cptopic_samples/corebanking-account-txn.yml
    - tests/ansible/fixtures/cptopic_samples/compliance-screening-result.yml
  modified: []

key-decisions:
  - "Added process_one.yml dispatcher to separate per-topic logic from main loop"
  - "Task names use Jinja only at end of string to pass ansible-lint name[template] rule"
  - "Task names start with uppercase to pass ansible-lint name[casing] rule"
  - "Removed ansible/roles/.gitkeep since actual role content now exists"

patterns-established:
  - "cp_topic role pattern: defaults/meta/tasks(6)/molecule(3) structure for CP governance roles"
  - "GET-before-POST idempotent creation: GET topic -> 404 means CREATE, 200 means UPDATE configs"
  - "Config convergence: build diff list, POST only changed configs to configs:alter"
  - "Check mode: include validate.yml + GET-only operations with check_mode: false"
  - "Error collection: ignore_errors on include_tasks loop, count failures, fail at end"

requirements-completed: [ATOPIC-01, ATOPIC-02, ATOPIC-03, ATOPIC-04, ATOPIC-05, ATOPIC-06, ATOPIC-07]

# Metrics
duration: 6min
completed: 2026-04-09
---

# Phase 11 Plan 01: cp_topic Role Summary

**Ansible role for CP topic lifecycle management via Admin REST v3 with SLA-tier governance, idempotent CRUD, check mode, and 40 unit tests**

## Performance

- **Duration:** 6 min
- **Started:** 2026-04-09T01:17:24Z
- **Completed:** 2026-04-09T01:23:31Z
- **Tasks:** 2
- **Files modified:** 20

## Accomplishments
- Complete cp_topic role with 9 task files (defaults, meta, 6 task files + process_one dispatcher)
- Full governance enforcement: fsi_validate_topic_name for naming, fsi_sla_lookup for SLA tier derivation
- Idempotent CRUD: GET-before-POST creation, configs:alter convergence, guarded deletion
- Check mode: GET-only state diff with changed_when for CAB approval workflows
- 40 unit tests across 9 test classes, all passing; 186 total test suite passes (zero regressions)
- Molecule delegated driver scenario with mock HTTP server and idempotency verification
- Shared test fixtures: 4 Admin REST v3 JSON mock responses, 2 CPTopic YAML samples

## Task Commits

Each task was committed atomically:

1. **Task 1: Create cp_topic role structure** - `a6e19ec` (feat)
2. **Task 2: Create test fixtures, molecule, and unit tests** - `0346ecc` (test)

## Files Created/Modified
- `ansible/roles/cp_topic/defaults/main.yml` - Default variable values (REST URL, cluster ID, credentials, topics input)
- `ansible/roles/cp_topic/meta/main.yml` - Galaxy-style role metadata
- `ansible/roles/cp_topic/tasks/main.yml` - Entry point: load vars, discover topics, loop with error collection
- `ansible/roles/cp_topic/tasks/validate.yml` - Pre-flight governance validation (name regex, SLA tier derivation)
- `ansible/roles/cp_topic/tasks/create.yml` - GET-before-POST idempotent creation via Admin REST v3
- `ansible/roles/cp_topic/tasks/update.yml` - Config convergence via configs:alter with SET operation
- `ansible/roles/cp_topic/tasks/delete.yml` - Guarded deletion (confirm_deletion + tier protection)
- `ansible/roles/cp_topic/tasks/check.yml` - Check-mode GET-only state diff reporting
- `ansible/roles/cp_topic/tasks/process_one.yml` - Per-topic dispatcher (validate then route)
- `ansible/roles/cp_topic/molecule/default/molecule.yml` - Delegated driver config (no Docker)
- `ansible/roles/cp_topic/molecule/default/converge.yml` - Test playbook with mock HTTP server
- `ansible/roles/cp_topic/molecule/default/verify.yml` - Idempotency assertion (second run = zero changes)
- `tests/ansible/test_cp_topic.py` - 40 unit tests across 9 test classes
- `tests/ansible/fixtures/mock_responses/admin_rest_v3/topic_exists.json` - Mock 200 response
- `tests/ansible/fixtures/mock_responses/admin_rest_v3/topic_not_found.json` - Mock 404 response
- `tests/ansible/fixtures/mock_responses/admin_rest_v3/topic_configs.json` - Mock config list
- `tests/ansible/fixtures/mock_responses/admin_rest_v3/topic_created.json` - Mock creation response
- `tests/ansible/fixtures/cptopic_samples/corebanking-account-txn.yml` - Critical tier sample
- `tests/ansible/fixtures/cptopic_samples/compliance-screening-result.yml` - Standard tier sample

## Decisions Made
- Added `process_one.yml` as a per-topic dispatcher to keep `main.yml` clean (routes validate -> create/update/delete)
- Task names reformatted to start with uppercase and place Jinja templates at end of string only (ansible-lint name[casing] and name[template] rules)
- Removed `ansible/roles/.gitkeep` since actual role content now exists

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed ansible-lint name[casing] and name[template] violations**
- **Found during:** Task 1
- **Issue:** Initial task names used lowercase "cp_topic |" prefix and had Jinja templates mid-string, violating ansible-lint shared profile rules
- **Fix:** Reformatted all task names to start with uppercase and move Jinja templates to end of name string
- **Files modified:** All 7 task files
- **Verification:** ansible-lint passes at production profile with zero violations
- **Committed in:** a6e19ec (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Minor naming convention fix required by ansible-lint. No scope creep.

## Issues Encountered
None -- plan executed smoothly after ansible-lint naming fix.

## Known Stubs
None -- all role task files contain complete implementation logic.

## User Setup Required
None -- no external service configuration required.

## Next Phase Readiness
- cp_topic role complete and tested, ready for orchestration (Phase 12)
- Shared test fixtures in tests/ansible/fixtures/ available for cp_schema (11-02) and cp_rbac (11-03) roles
- Error collection pattern established for reuse in sibling roles
- Molecule delegated driver pattern documented for cp_schema and cp_rbac scenarios

## Self-Check: PASSED

All 19 created files verified present on disk. Both task commits (a6e19ec, 0346ecc) verified in git log.

---
*Phase: 11-core-governance-roles*
*Completed: 2026-04-09*

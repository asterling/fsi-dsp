---
phase: 12-orchestration-pipeline-observability-and-ci-cd
plan: 01
subsystem: infra
tags: [ansible, kafka-connect, orchestration, playbook, connector-lifecycle]

# Dependency graph
requires:
  - phase: 11-ansible-governance-roles
    provides: cp_topic, cp_schema, cp_rbac roles for governance
provides:
  - site.yml 4-play orchestration pipeline with disjoint tag architecture
  - deploy-governance.yml Day-2 governance-only playbook
  - cp_connect role for Kafka Connect connector lifecycle via REST API
  - connectors-example.yml JDBC source/sink reference definitions
  - Connect REST API mock fixtures (4 response types)
affects: [12-02, 12-03, phase-13, phase-14]

# Tech tracking
tech-stack:
  added: []
  patterns: [import_playbook-tag-isolation, PUT-idempotent-connector-management, health-validation-with-restart]

key-files:
  created:
    - ansible/site.yml
    - ansible/playbooks/deploy-governance.yml
    - ansible/vars/connectors-example.yml
    - ansible/roles/cp_connect/defaults/main.yml
    - ansible/roles/cp_connect/meta/main.yml
    - ansible/roles/cp_connect/tasks/main.yml
    - ansible/roles/cp_connect/tasks/deploy.yml
    - ansible/roles/cp_connect/tasks/validate.yml
    - ansible/roles/cp_connect/tasks/check.yml
    - ansible/roles/cp_connect/molecule/default/molecule.yml
    - ansible/roles/cp_connect/molecule/default/converge.yml
    - ansible/roles/cp_connect/molecule/default/verify.yml
    - tests/ansible/test_orchestration.py
    - tests/ansible/test_cp_connect.py
    - tests/ansible/fixtures/mock_responses/connect/connectors_list.json
    - tests/ansible/fixtures/mock_responses/connect/connector_status_running.json
    - tests/ansible/fixtures/mock_responses/connect/connector_status_failed.json
    - tests/ansible/fixtures/mock_responses/connect/connector_created.json
  modified: []

key-decisions:
  - "Disjoint tag sets per play in site.yml to prevent import_playbook tag inheritance leakage"
  - "PUT /connectors/{name}/config for idempotent create-or-update (201 new, 200 update)"
  - "Health validation with automatic restart of FAILED tasks before retry loop"
  - "Tasks 1 and 2 merged into single TDD cycle since cp_connect role must exist for tests to pass"

patterns-established:
  - "Tag isolation: each play in site.yml uses exclusive top-level tags to prevent import_playbook tag inheritance"
  - "Connector lifecycle: PUT idempotent with status_code [200, 201], health validation with restart and backoff"
  - "Check mode pattern for cp_connect: GET-only operations, no mutations"

requirements-completed: [APIPE-01, APIPE-02, APIPE-03, APIPE-04, ACI-02]

# Metrics
duration: 5min
completed: 2026-04-09
---

# Phase 12 Plan 01: Orchestration Pipeline and cp_connect Summary

**4-play orchestration pipeline (site.yml) with tag-isolated selective execution and cp_connect role for idempotent connector lifecycle via PUT REST API**

## Performance

- **Duration:** 5 min
- **Started:** 2026-04-09T16:00:59Z
- **Completed:** 2026-04-09T16:06:06Z
- **Tasks:** 2
- **Files modified:** 18

## Accomplishments
- site.yml chains 4 plays (cluster, governance, connectors, observability) with disjoint tag architecture preventing import_playbook tag inheritance leakage
- deploy-governance.yml provides Day-2 governance-only execution without cluster deployment
- cp_connect role deploys connectors via idempotent PUT, validates health with automatic FAILED task restart, and supports check mode with GET-only operations
- 87 new tests covering orchestration structure, tag isolation, cp_connect role, and mock fixtures; 321 total tests pass

## Task Commits

Each task was committed atomically:

1. **Task 1: Tests, mock fixtures, and orchestration playbooks (RED)** - `c75ce86` (test)
2. **Task 1+2: Orchestration playbooks and cp_connect role (GREEN)** - `3e92195` (feat)

_Note: TDD tasks merged -- cp_connect role required in Task 1 GREEN phase for tests to pass_

## Files Created/Modified
- `ansible/site.yml` - Top-level 4-play orchestration pipeline with disjoint tag architecture
- `ansible/playbooks/deploy-governance.yml` - Governance-only Day-2 playbook (no cluster deploy)
- `ansible/vars/connectors-example.yml` - JDBC source/sink connector reference definitions
- `ansible/roles/cp_connect/defaults/main.yml` - Default variables (url, connectors, health settings)
- `ansible/roles/cp_connect/meta/main.yml` - Galaxy metadata with role_name: cp_connect
- `ansible/roles/cp_connect/tasks/main.yml` - Entry point routing to check/deploy/validate
- `ansible/roles/cp_connect/tasks/deploy.yml` - PUT /connectors/{name}/config idempotent create-or-update
- `ansible/roles/cp_connect/tasks/validate.yml` - Health validation with restart and retry backoff
- `ansible/roles/cp_connect/tasks/check.yml` - GET-only check mode (no mutations)
- `ansible/roles/cp_connect/molecule/default/molecule.yml` - Delegated driver molecule scenario
- `ansible/roles/cp_connect/molecule/default/converge.yml` - Converge playbook with mock API
- `ansible/roles/cp_connect/molecule/default/verify.yml` - Verify cp_connect_results fact
- `tests/ansible/test_orchestration.py` - 39 tests for site.yml and deploy-governance.yml
- `tests/ansible/test_cp_connect.py` - 48 tests for cp_connect role
- `tests/ansible/fixtures/mock_responses/connect/connectors_list.json` - GET /connectors mock
- `tests/ansible/fixtures/mock_responses/connect/connector_status_running.json` - Healthy status mock
- `tests/ansible/fixtures/mock_responses/connect/connector_status_failed.json` - Failed status with trace
- `tests/ansible/fixtures/mock_responses/connect/connector_created.json` - PUT 201 response mock

## Decisions Made
- **Disjoint tag architecture**: Each play in site.yml has exclusive top-level tags (cluster, governance, connectors, observability) to prevent import_playbook tag inheritance from causing `--tags connectors` to trigger cluster deployment
- **PUT for connector idempotency**: Using PUT to /connectors/{name}/config rather than POST+PUT for true idempotent create-or-update (201 for new, 200 for existing)
- **Health validation with auto-restart**: FAILED connectors are automatically restarted via POST /restart?includeTasks=true&onlyFailed=true before the retry loop checks RUNNING state
- **Task consolidation**: Tasks 1 and 2 were implemented together since the TDD cycle required the cp_connect role to exist for tests to pass

## Deviations from Plan

None - plan executed exactly as written. Tasks 1 and 2 were consolidated into a single TDD cycle since both test files require the cp_connect role implementation to pass (tests validate role file existence).

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Known Stubs
None - all implementations are complete with no placeholder data.

## Next Phase Readiness
- Orchestration pipeline ready for observability role integration (Plan 02)
- cp_connect role ready for CI/CD workflow integration (Plan 03)
- Tag architecture verified for selective execution safety

## Self-Check: PASSED

- All 18 created files verified present on disk
- Commit c75ce86 (test RED) verified in git log
- Commit 3e92195 (feat GREEN) verified in git log
- 87/87 plan tests pass, 321/321 total tests pass

---
*Phase: 12-orchestration-pipeline-observability-and-ci-cd*
*Completed: 2026-04-09*

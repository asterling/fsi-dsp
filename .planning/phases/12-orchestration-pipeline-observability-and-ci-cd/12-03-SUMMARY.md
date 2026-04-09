---
phase: 12-orchestration-pipeline-observability-and-ci-cd
plan: 03
subsystem: ci-cd
tags: [github-actions, ansible-lint, yamllint, molecule, governance-parity, ci]
dependency_graph:
  requires: [12-01, 12-02]
  provides: [ansible-ci-workflow, ci-quality-gates]
  affects: [ansible/, tests/ansible/]
tech_stack:
  added: [ansible-ci.yml workflow]
  patterns: [matrix-strategy-per-role, three-job-pipeline, yaml-on-boolean-workaround]
key_files:
  created:
    - .github/workflows/ansible-ci.yml
    - tests/ansible/test_ci_workflows.py
  modified: []
decisions:
  - "PyYAML parses YAML 'on' key as boolean True; tests use wf.get('on') or wf.get(True) for portability"
  - "yamllint config referenced as ansible/.yamllint in workflow (consistent with ansible-lint config path)"
metrics:
  duration: 2min
  completed: 2026-04-09T17:52:04Z
  tasks_completed: 1
  tasks_total: 1
  files_created: 2
  files_modified: 0
---

# Phase 12 Plan 03: Ansible CI Workflow Summary

GitHub Actions CI workflow with three quality-gate jobs: lint (yamllint + ansible-lint), molecule (5-role matrix), and governance parity (pytest validation of Ansible/Terraform constant sync).

## What Was Built

### Task 1: GitHub Actions CI Workflow for Ansible Content (TDD)

**RED phase** -- wrote 14 pytest tests in `tests/ansible/test_ci_workflows.py` covering:
- `TestAnsibleLintWorkflow` (7 tests): workflow existence, valid YAML, trigger paths (ansible/**, tests/ansible/**), lint job presence, yamllint execution, ansible-lint execution with config reference, dependency installation
- `TestMoleculeScenarios` (5 tests): molecule job existence, 5-role matrix (cp_topic, cp_schema, cp_rbac, cp_connect, cp_observability), ansible-galaxy collection install, working-directory referencing matrix.role, all roles have molecule/default/ directories
- `TestParityValidation` (2 tests): parity job existence, pytest invocation with test_governance_parity.py

**GREEN phase** -- implemented `.github/workflows/ansible-ci.yml` with three jobs:
1. **lint** -- installs ansible-core, ansible-lint, yamllint via pip; runs yamllint with ansible/.yamllint config; runs ansible-lint with ansible/.ansible-lint config
2. **molecule** -- depends on lint; matrix strategy across 5 governance roles with fail-fast: false; installs ansible-core, molecule, pytest, pyyaml plus ansible-galaxy collection install; runs molecule test with working-directory per role
3. **parity** -- independent job; installs pytest and pyyaml; runs pytest tests/ansible/test_governance_parity.py -v

## Commits

| # | Hash | Message |
|---|------|---------|
| 1 | c5761d0 | test(12-03): add failing tests for Ansible CI workflow structure |
| 2 | 01c2ab5 | feat(12-03): implement Ansible CI workflow with lint, molecule, parity jobs |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] PyYAML 'on' key parsed as boolean True**
- **Found during:** Task 1 GREEN phase
- **Issue:** PyYAML's safe_load parses the YAML key `on:` (used by GitHub Actions) as Python boolean `True`, causing `wf['on']` to raise KeyError
- **Fix:** Changed test to use `wf.get('on') or wf.get(True)` which handles both PyYAML behavior and potential future fixes
- **Files modified:** tests/ansible/test_ci_workflows.py
- **Commit:** 01c2ab5

## Verification

All 14 tests pass:
```
tests/ansible/test_ci_workflows.py::TestAnsibleLintWorkflow::test_workflow_exists PASSED
tests/ansible/test_ci_workflows.py::TestAnsibleLintWorkflow::test_workflow_valid_yaml PASSED
tests/ansible/test_ci_workflows.py::TestAnsibleLintWorkflow::test_trigger_paths PASSED
tests/ansible/test_ci_workflows.py::TestAnsibleLintWorkflow::test_lint_job_exists PASSED
tests/ansible/test_ci_workflows.py::TestAnsibleLintWorkflow::test_lint_runs_yamllint PASSED
tests/ansible/test_ci_workflows.py::TestAnsibleLintWorkflow::test_lint_runs_ansible_lint PASSED
tests/ansible/test_ci_workflows.py::TestAnsibleLintWorkflow::test_lint_installs_deps PASSED
tests/ansible/test_ci_workflows.py::TestMoleculeScenarios::test_molecule_job_exists PASSED
tests/ansible/test_ci_workflows.py::TestMoleculeScenarios::test_molecule_matrix PASSED
tests/ansible/test_ci_workflows.py::TestMoleculeScenarios::test_molecule_installs_collections PASSED
tests/ansible/test_ci_workflows.py::TestMoleculeScenarios::test_molecule_working_directory PASSED
tests/ansible/test_ci_workflows.py::TestMoleculeScenarios::test_all_roles_have_molecule PASSED
tests/ansible/test_ci_workflows.py::TestParityValidation::test_parity_job_exists PASSED
tests/ansible/test_ci_workflows.py::TestParityValidation::test_parity_runs_pytest PASSED
```

All 11 acceptance criteria grep checks pass.

## Known Stubs

None -- all workflow jobs are fully wired to real tools and test files.

## Self-Check: PASSED

- FOUND: .github/workflows/ansible-ci.yml
- FOUND: tests/ansible/test_ci_workflows.py
- FOUND: c5761d0 (RED commit)
- FOUND: 01c2ab5 (GREEN commit)

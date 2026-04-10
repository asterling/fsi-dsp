---
phase: 14-cfk-on-openshift-governance
plan: 01
subsystem: infra
tags: [ansible, cfk, openshift, helm, kubernetes, confluent]

requires:
  - phase: 10-ansible-foundation
    provides: Ansible role structure, conventions, requirements.yml, site.yml
  - phase: 12-connect-observability
    provides: cp_connect role pattern, molecule conventions, CI matrix
provides:
  - cfk_operator Ansible role with Helm-based CFK operator deployment
  - CR application (Kafka, SchemaRegistry, Connect) with k8s_info readiness polling
  - Check-mode audit for operator and CR state
  - deploy-cfk.yml playbook chaining operator + topic governance
  - kubernetes.core collection dependency in requirements.yml
  - site.yml CFK play with disjoint tag
affects: [14-02-cfk-topic-governance, cfk-deployment-pipeline]

tech-stack:
  added: [kubernetes.core collection]
  patterns: [kubernetes.core.helm for operator install, k8s_info+until for CR readiness polling]

key-files:
  created:
    - ansible/roles/cfk_operator/defaults/main.yml
    - ansible/roles/cfk_operator/meta/main.yml
    - ansible/roles/cfk_operator/tasks/main.yml
    - ansible/roles/cfk_operator/tasks/deploy.yml
    - ansible/roles/cfk_operator/tasks/apply_crs.yml
    - ansible/roles/cfk_operator/tasks/check.yml
    - ansible/roles/cfk_operator/molecule/default/molecule.yml
    - ansible/roles/cfk_operator/molecule/default/converge.yml
    - ansible/roles/cfk_operator/molecule/default/verify.yml
    - ansible/playbooks/deploy-cfk.yml
    - tests/ansible/test_cfk_operator.py
  modified:
    - ansible/requirements.yml
    - ansible/site.yml
    - .github/workflows/ansible-ci.yml

key-decisions:
  - "k8s_info+until/retries/delay pattern for CR readiness (not wait_condition -- CFK uses .status.phase)"
  - "molecule converge runs in check mode (no real k8s cluster needed for structure validation)"

patterns-established:
  - "kubernetes.core.helm for Helm-based operator deployment on OpenShift"
  - "kubernetes.core.k8s + k8s_info until loop for CFK CR lifecycle"
  - "Disjoint 'cfk' tag in site.yml for CFK-specific plays"

requirements-completed: [ACFK-01, ACFK-02]

duration: 3min
completed: 2026-04-10
---

# Phase 14 Plan 01: CFK Operator Role Summary

**CFK operator Ansible role with Helm deployment, platform CR readiness gates (k8s_info+until), check-mode audit, and deploy-cfk.yml orchestration playbook**

## Performance

- **Duration:** 3 min
- **Started:** 2026-04-10T13:14:24Z
- **Completed:** 2026-04-10T13:17:14Z
- **Tasks:** 2
- **Files modified:** 14

## Accomplishments
- Created cfk_operator role deploying CFK via kubernetes.core.helm with configurable chart version and namespace
- Implemented CR readiness gates for Kafka, SchemaRegistry, and Connect using k8s_info+until polling pattern
- Check mode queries Helm release and CR status without mutations
- deploy-cfk.yml playbook chains operator deployment, CR application, and topic governance plays
- 37 unit tests covering role structure, defaults, deploy tasks, readiness gates, FQCN, task naming

## Task Commits

Each task was committed atomically:

1. **Task 1: Create cfk_operator role with Helm deployment, CR readiness gates, and check mode** - `032ebbc` (feat)
2. **Task 2: Create unit tests for cfk_operator role and update CI molecule matrix** - `f1c7312` (test)

## Files Created/Modified
- `ansible/roles/cfk_operator/defaults/main.yml` - Helm chart settings, CR paths, readiness polling config
- `ansible/roles/cfk_operator/meta/main.yml` - Galaxy metadata for cfk_operator role
- `ansible/roles/cfk_operator/tasks/main.yml` - Entry point routing check/normal mode
- `ansible/roles/cfk_operator/tasks/deploy.yml` - Helm repo add + operator install via kubernetes.core.helm
- `ansible/roles/cfk_operator/tasks/apply_crs.yml` - CR application with k8s_info readiness polling
- `ansible/roles/cfk_operator/tasks/check.yml` - Read-only audit of operator and CR state
- `ansible/roles/cfk_operator/molecule/default/molecule.yml` - Delegated driver molecule config
- `ansible/roles/cfk_operator/molecule/default/converge.yml` - Check-mode converge playbook
- `ansible/roles/cfk_operator/molecule/default/verify.yml` - Defaults validation verify playbook
- `ansible/playbooks/deploy-cfk.yml` - Two-play CFK deployment pipeline
- `ansible/requirements.yml` - Added kubernetes.core collection dependency
- `ansible/site.yml` - Added CFK play with disjoint 'cfk' tag
- `tests/ansible/test_cfk_operator.py` - 37 unit tests across 9 test classes
- `.github/workflows/ansible-ci.yml` - Added cfk_operator to molecule matrix

## Decisions Made
- Used k8s_info+until/retries/delay for CR readiness polling (not wait_condition) per CFK research pitfall analysis -- CFK CRDs use .status.phase rather than standard conditions
- Molecule converge runs in ansible_check_mode since no real k8s cluster available in CI

## Deviations from Plan

None - plan executed exactly as written.

## Known Stubs

None - all role files are fully implemented.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- cfk_operator role complete and tested, ready for Plan 02 (cfk_topic role for KafkaTopic CRD governance)
- kubernetes.core collection available for cfk_topic role to use
- deploy-cfk.yml already includes Play 2 stub for cfk_topic role

---
*Phase: 14-cfk-on-openshift-governance*
*Completed: 2026-04-10*

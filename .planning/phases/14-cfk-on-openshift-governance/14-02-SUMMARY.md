---
phase: 14-cfk-on-openshift-governance
plan: 02
subsystem: infra
tags: [ansible, cfk, openshift, kafkatopic, crd, governance, kubernetes]

requires:
  - phase: 10-ansible-foundation
    provides: Ansible foundation with governance filter plugins, sla_tiers.yml, naming_rules.yml
  - phase: 11-cp-governance-roles
    provides: cp_topic role pattern (validate.yml, process_one.yml, check mode)
provides:
  - cfk_topic Ansible role generating KafkaTopic CRDs from CPTopic YAML
  - Governance parity between CP REST (cp_topic) and CFK CRD (cfk_topic) topic creation
  - String-typed CRD config values per CFK requirement
  - Check mode audit showing computed CRDs without cluster mutation
affects: [14-cfk-on-openshift-governance, onboarding, ci]

tech-stack:
  added: [kubernetes.core.k8s, kubernetes.core.k8s_info]
  patterns: [CPTopic-to-KafkaTopic CRD transformation, string-typed CFK configs]

key-files:
  created:
    - ansible/roles/cfk_topic/defaults/main.yml
    - ansible/roles/cfk_topic/meta/main.yml
    - ansible/roles/cfk_topic/tasks/main.yml
    - ansible/roles/cfk_topic/tasks/validate.yml
    - ansible/roles/cfk_topic/tasks/generate.yml
    - ansible/roles/cfk_topic/tasks/process_one.yml
    - ansible/roles/cfk_topic/tasks/check.yml
    - ansible/roles/cfk_topic/molecule/default/molecule.yml
    - ansible/roles/cfk_topic/molecule/default/converge.yml
    - ansible/roles/cfk_topic/molecule/default/verify.yml
    - tests/ansible/test_cfk_topic.py
  modified:
    - .github/workflows/ansible-ci.yml

key-decisions:
  - "Mirrored cp_topic validate.yml exactly for governance parity -- same filters, same override pattern"
  - "Added process_one.yml dispatcher to match cp_topic pattern"
  - "CFK string-typed configs via | string filter on retention.ms, min.insync.replicas, cleanup.policy"

patterns-established:
  - "CPTopic-to-KafkaTopic transformation: same CPTopic YAML input, different output target (CRD vs REST)"
  - "kubernetes.core.k8s with inline definition for CFK CRD generation"
  - "k8s_info for non-mutating check mode queries"

requirements-completed: [ACFK-03]

duration: 3min
completed: 2026-04-10
---

# Phase 14 Plan 02: CFK Topic Role Summary

**cfk_topic Ansible role generating KafkaTopic CRDs from CPTopic YAML with governance parity via fsi_sla_lookup/fsi_validate_topic_name and string-typed CFK configs**

## Performance

- **Duration:** 3 min
- **Started:** 2026-04-10T13:14:28Z
- **Completed:** 2026-04-10T13:17:16Z
- **Tasks:** 2
- **Files modified:** 12

## Accomplishments
- cfk_topic role with full CPTopic-to-KafkaTopic CRD transformation
- Governance parity with cp_topic: identical fsi_validate_topic_name, fsi_sla_lookup, SLA tier override logic
- String-typed config values (| string) per CFK requirement -- retention.ms, min.insync.replicas, cleanup.policy
- Check mode shows computed CRDs via k8s_info without cluster mutation
- 45 unit tests covering structure, defaults, governance wiring, CRD generation, parity, FQCN, task naming
- CI matrix updated with cfk_topic in molecule job

## Task Commits

Each task was committed atomically:

1. **Task 1: Create cfk_topic role with CPTopic-to-KafkaTopic transformation** - `2dfc8b7` (feat)
2. **Task 2: Create unit tests and update CI matrix** - `6e9b14a` (test)

## Files Created/Modified
- `ansible/roles/cfk_topic/defaults/main.yml` - CFK topic defaults (namespace, cluster ref, replication factor, API version)
- `ansible/roles/cfk_topic/meta/main.yml` - Galaxy metadata for cfk_topic role
- `ansible/roles/cfk_topic/tasks/main.yml` - Entry point: load governance vars, discover topics, route to process/check
- `ansible/roles/cfk_topic/tasks/validate.yml` - Governance validation: naming + SLA tier derivation with overrides
- `ansible/roles/cfk_topic/tasks/generate.yml` - KafkaTopic CRD application via kubernetes.core.k8s
- `ansible/roles/cfk_topic/tasks/process_one.yml` - Per-topic dispatcher (validate then generate)
- `ansible/roles/cfk_topic/tasks/check.yml` - Check mode: show computed CRD + query existing via k8s_info
- `ansible/roles/cfk_topic/molecule/default/molecule.yml` - Delegated driver molecule scenario
- `ansible/roles/cfk_topic/molecule/default/converge.yml` - Converge with inline CPTopic examples
- `ansible/roles/cfk_topic/molecule/default/verify.yml` - Verify governance constants loaded
- `tests/ansible/test_cfk_topic.py` - 45 unit tests for role structure, governance, CRD patterns, parity
- `.github/workflows/ansible-ci.yml` - Added cfk_topic to molecule matrix

## Decisions Made
- Mirrored cp_topic validate.yml exactly (same filter calls, same override pattern) for governance parity
- Added process_one.yml dispatcher to match cp_topic per-topic routing pattern
- All CFK config values use `| string` filter per CFK CRD requirement (Research Pitfall 2)
- namespace always injected per Research Pitfall 3

## Deviations from Plan

None -- plan executed exactly as written.

## Known Stubs

None -- all governance filters, SLA tier lookups, and CRD generation are fully wired.

## Issues Encountered

Pre-existing test failure in test_orchestration.py (expects 4 plays in site.yml, but Plan 01 added a 5th CFK play). Out of scope for Plan 02 -- logged for Plan 01 verifier.

## User Setup Required

None -- no external service configuration required.

## Next Phase Readiness
- cfk_topic role ready for integration into CFK deployment playbook
- Governance parity confirmed between cp_topic (CP REST) and cfk_topic (CFK CRD) paths

## Self-Check: PASSED

All created files verified present. Both task commits (2dfc8b7, 6e9b14a) confirmed in git log. 45/45 unit tests pass.

---
*Phase: 14-cfk-on-openshift-governance*
*Completed: 2026-04-10*

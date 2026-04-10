---
phase: 15-mrc-failover-and-dr-drill
plan: 01
subsystem: dr
tags: [kafka, mrc, leader-election, ansible, consul, failover, failback]

# Dependency graph
requires:
  - phase: 13-dr-automation-playbooks-mm2
    provides: cp_dr_mm2 role pattern (consul_flip, check mode, validate_state, molecule)
provides:
  - cp_dr_mrc Ansible role for MRC observer promotion failover/failback
  - UNCLEAN leader election via kafka-leader-election.sh with JSON partition file
  - PREFERRED leader election with --all-topic-partitions for failback
  - Operator-facing playbooks dr-failover-mrc.yml and dr-failback-mrc.yml
  - Check mode audit log (4 failover steps, 3 failback steps)
  - Consul KV active-region flip (identical pattern to cp_dr_mm2)
affects: [15-02-dr-drill-automation]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "MRC observer promotion via kafka-leader-election.sh UNCLEAN/PREFERRED"
    - "Election JSON template for per-partition UNCLEAN election"
    - "Primary DC reachability check before failback"

key-files:
  created:
    - ansible/roles/cp_dr_mrc/defaults/main.yml
    - ansible/roles/cp_dr_mrc/meta/main.yml
    - ansible/roles/cp_dr_mrc/tasks/main.yml
    - ansible/roles/cp_dr_mrc/tasks/failover.yml
    - ansible/roles/cp_dr_mrc/tasks/failback.yml
    - ansible/roles/cp_dr_mrc/tasks/check.yml
    - ansible/roles/cp_dr_mrc/tasks/validate_state.yml
    - ansible/roles/cp_dr_mrc/tasks/consul_flip.yml
    - ansible/roles/cp_dr_mrc/templates/unclean_election.json.j2
    - ansible/roles/cp_dr_mrc/molecule/default/molecule.yml
    - ansible/roles/cp_dr_mrc/molecule/default/converge.yml
    - ansible/roles/cp_dr_mrc/molecule/default/verify.yml
    - ansible/playbooks/dr-failover-mrc.yml
    - ansible/playbooks/dr-failback-mrc.yml
    - tests/ansible/test_cp_dr_mrc.py
  modified:
    - .github/workflows/ansible-ci.yml

key-decisions:
  - "UNCLEAN election requires --path-to-json-file (not --all-topic-partitions), so template generates per-partition JSON"
  - "PREFERRED election uses --all-topic-partitions (simpler, no partition enumeration needed)"
  - "Primary DC reachability check via kafka-broker-api-versions.sh before failback"
  - "Molecule converge runs in check_mode: true (no CLI binaries in CI, matching Phase 14 CFK pattern)"

patterns-established:
  - "MRC DR role: kafka-leader-election.sh for observer promotion instead of connector management"
  - "Election JSON template: Jinja2 rendering of partition list for UNCLEAN election"
  - "Pre-failback reachability gate: fail-fast if primary DC unreachable"

requirements-completed: [ADR-05]

# Metrics
duration: 5min
completed: 2026-04-10
---

# Phase 15 Plan 01: MRC Observer Promotion DR Summary

**cp_dr_mrc Ansible role with UNCLEAN/PREFERRED leader election, Consul flip, check-mode audit, and operator playbooks**

## Performance

- **Duration:** 5 min
- **Started:** 2026-04-10T13:49:24Z
- **Completed:** 2026-04-10T13:53:59Z
- **Tasks:** 1 (TDD: RED + GREEN)
- **Files modified:** 16

## Accomplishments
- Complete cp_dr_mrc role with 6 task files mirroring cp_dr_mm2 structure but replacing connector management with leader election operations
- Failover uses UNCLEAN leader election with dynamically generated JSON partition file from kafka-topics.sh describe output
- Failback uses PREFERRED leader election with --all-topic-partitions after primary DC reachability check
- Check mode produces structured audit log (4 failover steps, 3 failback steps) without CLI execution
- Consul KV active-region flip follows identical pattern to cp_dr_mm2
- 89 unit tests across 15 test classes, zero regressions in full test suite (631 tests)
- CI molecule matrix updated with cp_dr_mrc

## Task Commits

Each task was committed atomically:

1. **Task 1 RED: Tests for cp_dr_mrc role** - `b672068` (test)
2. **Task 1 GREEN: Implement cp_dr_mrc role** - `407c415` (feat)

## Files Created/Modified
- `ansible/roles/cp_dr_mrc/defaults/main.yml` - All cp_dr_mrc_* variables with MRC-specific defaults (bootstrap, rack assignments, election config)
- `ansible/roles/cp_dr_mrc/meta/main.yml` - Galaxy metadata (role_name: cp_dr_mrc, author: fsi-c4e)
- `ansible/roles/cp_dr_mrc/tasks/main.yml` - Entry point routing to check/failover/failback with pre/post validation
- `ansible/roles/cp_dr_mrc/tasks/failover.yml` - UNCLEAN leader election via kafka-leader-election.sh with JSON partition file
- `ansible/roles/cp_dr_mrc/tasks/failback.yml` - PREFERRED leader election with --all-topic-partitions and primary DC check
- `ansible/roles/cp_dr_mrc/tasks/check.yml` - GET-only audit log (4 failover + 3 failback planned steps)
- `ansible/roles/cp_dr_mrc/tasks/validate_state.yml` - Topic availability, SLA-tier mirror lag, and writability checks
- `ansible/roles/cp_dr_mrc/tasks/consul_flip.yml` - Consul KV read/update/verify (cp_dr_mm2 pattern)
- `ansible/roles/cp_dr_mrc/templates/unclean_election.json.j2` - Dynamic partition list for UNCLEAN election JSON
- `ansible/roles/cp_dr_mrc/molecule/default/molecule.yml` - Delegated driver with localhost
- `ansible/roles/cp_dr_mrc/molecule/default/converge.yml` - Check-mode converge (no CLI binaries needed)
- `ansible/roles/cp_dr_mrc/molecule/default/verify.yml` - Asserts cp_dr_mrc_results fact with all fields
- `ansible/playbooks/dr-failover-mrc.yml` - Operator-facing failover playbook (kafka_broker[0])
- `ansible/playbooks/dr-failback-mrc.yml` - Operator-facing failback playbook (kafka_broker[0])
- `tests/ansible/test_cp_dr_mrc.py` - 89 tests across 15 classes
- `.github/workflows/ansible-ci.yml` - Added cp_dr_mrc to molecule matrix

## Decisions Made
- UNCLEAN election requires --path-to-json-file with per-partition entries (cannot use --all-topic-partitions for UNCLEAN type per Kafka CLI contract)
- PREFERRED election uses --all-topic-partitions (simpler, no partition enumeration needed for rebalance)
- kafka-broker-api-versions.sh used for primary DC reachability check before failback (lightweight, no topic dependencies)
- Molecule converge runs in check_mode: true following Phase 14 CFK pattern (no real Kafka CLI binaries in CI)
- MRC playbooks target kafka_broker[0] (not kafka_connect[0] like MM2) since leader election runs on broker host

## Deviations from Plan
None - plan executed exactly as written.

## Known Stubs
None - all task files contain complete implementation logic.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- cp_dr_mrc role is complete and tested, ready for DR drill automation in 15-02
- DR drill playbook can orchestrate failover (cp_dr_mrc) -> validate -> failback (cp_dr_mrc) -> report
- Pre-existing test_site_yml_has_four_plays failure (expects 4 plays, finds 5 from Phase 14 CFK addition) is unrelated to this plan

## Self-Check: PASSED

---
*Phase: 15-mrc-failover-and-dr-drill*
*Completed: 2026-04-10*

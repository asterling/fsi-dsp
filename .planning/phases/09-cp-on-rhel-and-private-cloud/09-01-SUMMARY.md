---
phase: 09-cp-on-rhel-and-private-cloud
plan: 01
subsystem: infra
tags: [ansible, cp-ansible, rhel, kafka, schema-registry, connect, mds, rbac, tls, fips, cptopic, governance]

# Dependency graph
requires:
  - phase: 08-cfk-on-openshift
    provides: "CFK KafkaTopic CRD pattern with FSI governance labels"
provides:
  - "CP-RHEL Ansible scenario directory with inventory, group vars, playbook"
  - "CPTopic YAML format with FSI governance labels matching CFK KafkaTopic format"
  - "3 reference CPTopic definitions (corebanking, fraud, compliance)"
affects: [09-02, 09-03, 09-04]

# Tech tracking
tech-stack:
  added: [cp-ansible 7.6.x, confluent.platform collection, CPTopic YAML format]
  patterns: [Ansible inventory with group_vars, CPTopic governance labels, multi-rack broker deployment]

key-files:
  created:
    - scenarios/cp-rhel/README.md
    - scenarios/cp-rhel/inventory/hosts.yml.example
    - scenarios/cp-rhel/inventory/group_vars/all.yml
    - scenarios/cp-rhel/inventory/group_vars/kafka_broker.yml
    - scenarios/cp-rhel/inventory/group_vars/schema_registry.yml
    - scenarios/cp-rhel/inventory/group_vars/kafka_connect.yml
    - scenarios/cp-rhel/playbooks/deploy-cp.yml
    - scenarios/cp-rhel/topics/corebanking-account-txn.yml
    - scenarios/cp-rhel/topics/fraud-alert-signal.yml
    - scenarios/cp-rhel/topics/compliance-screening-result.yml
  modified: []

key-decisions:
  - "CPTopic YAML format uses same FSI governance labels as CFK KafkaTopic CRDs for cross-deployment parity"
  - "Playbook split into separate plays per component group for tag-based selective deployment"
  - "replicationFactor 5 with min.insync.replicas 3 for critical/compliance tiers (MRC-ready topology)"

patterns-established:
  - "CPTopic YAML: kind=CPTopic with metadata.labels for FSI governance and spec for topic config"
  - "Ansible group_vars: all.yml for common settings, per-component yml for specifics"
  - "Multi-rack broker topology: 3 brokers across 3 AZs with broker.rack assignment"

requirements-completed: [IAC-04]

# Metrics
duration: 2min
completed: 2026-03-28
---

# Phase 09 Plan 01: CP-RHEL Ansible Scenario Summary

**CP-RHEL Ansible scaffold with cp-ansible inventory, MDS RBAC group vars, deploy playbook, and 3 CPTopic governance definitions matching CFK label parity**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-28T00:52:04Z
- **Completed:** 2026-03-28T00:54:32Z
- **Tasks:** 1
- **Files modified:** 10

## Accomplishments

- Created complete CP-RHEL scenario directory with Ansible inventory (3 multi-rack brokers, 2 SR, 2 Connect), group vars (TLS, MDS RBAC, FIPS toggle, JMX exporter), and deployment playbook
- Established CPTopic YAML format with FSI governance labels matching CFK KafkaTopic CRDs for cross-deployment parity
- Created 3 reference CPTopic definitions covering critical (corebanking, fraud) and compliance (screening) tiers with appropriate partition, replication, and retention settings
- README with prerequisites, quickstart (4 steps), architecture, topic governance, and security sections

## Task Commits

Each task was committed atomically:

1. **Task 1: Create CP-RHEL Ansible scenario directory with inventory, playbook, and CPTopic definitions** - `e1dc632` (feat)

## Files Created/Modified

- `scenarios/cp-rhel/README.md` - Quickstart guide with prerequisites, architecture, security, and governance sections
- `scenarios/cp-rhel/inventory/hosts.yml.example` - Ansible inventory: 3 brokers (multi-rack), 2 SR, 2 Connect
- `scenarios/cp-rhel/inventory/group_vars/all.yml` - Common vars: CP 7.6.0, TLS mutual auth, MDS RBAC, FIPS toggle, JMX exporter
- `scenarios/cp-rhel/inventory/group_vars/kafka_broker.yml` - Broker config: replication factors, retention, MRC placeholders
- `scenarios/cp-rhel/inventory/group_vars/schema_registry.yml` - SR config: default BACKWARD compatibility
- `scenarios/cp-rhel/inventory/group_vars/kafka_connect.yml` - Connect config: replication factors, plugin path
- `scenarios/cp-rhel/playbooks/deploy-cp.yml` - Deployment playbook with preflight checks and confluent.platform roles
- `scenarios/cp-rhel/topics/corebanking-account-txn.yml` - CPTopic: critical tier, 12 partitions, 7-day retention
- `scenarios/cp-rhel/topics/fraud-alert-signal.yml` - CPTopic: critical tier, 12 partitions, 7-day retention
- `scenarios/cp-rhel/topics/compliance-screening-result.yml` - CPTopic: compliance tier, 6 partitions, infinite retention

## Decisions Made

- **CPTopic YAML format:** Uses `kind: CPTopic` with `metadata.labels` for FSI governance and `spec` for topic configuration, mirroring the structure of CFK KafkaTopic CRDs for cross-deployment parity
- **Playbook structure:** Split into separate plays per component group (kafka_broker, schema_registry, kafka_connect) with tags, enabling selective deployment
- **Replication factor 5 with ISR 3:** Critical and compliance tier topics use RF=5 and min.insync.replicas=3 for MRC-ready topology matching ADR-008 DR tier classification
- **replicaPlacement field:** Included in CPTopic spec to reference MRC placement constraint JSON files for multi-region deployments

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- CP-RHEL scenario directory complete with Ansible scaffold
- Ready for Plan 02 (DR and MRC automation) to build on this inventory structure
- CPTopic format established for validation by c4e-precheck.py (future plan)

## Self-Check: PASSED

All 10 files verified present. Commit e1dc632 verified in git log.

---
*Phase: 09-cp-on-rhel-and-private-cloud*
*Completed: 2026-03-28*

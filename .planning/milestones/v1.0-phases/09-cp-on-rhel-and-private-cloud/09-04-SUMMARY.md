---
phase: 09-cp-on-rhel-and-private-cloud
plan: 04
subsystem: infra
tags: [ansible, flink, systemd, fips, rhel, openshift, avro-confluent]

requires:
  - phase: 09-01
    provides: CP on RHEL scenario directory with inventory, group vars, and deploy-cp.yml playbook
  - phase: 08-03
    provides: CFK Flink pattern (FlinkDeployment CRDs, JMX exporter, avro-confluent connector)
provides:
  - Standalone Flink Ansible role with systemd service management and SR integration
  - FIPS 140-2 compliance validation for both CP on RHEL and CFK on OpenShift
  - .env.example Section 16 for CP on RHEL and Private Cloud environment variables
affects: [observability, dr-framework, onboarding]

tech-stack:
  added: [apache-flink-1.20.1, flink-sql-avro-confluent-3.2.0-1.20, BCFKS-keystore, bouncy-castle-fips]
  patterns: [ansible-role-with-systemd, fips-validation-playbook, multi-deployment-fips-check]

key-files:
  created:
    - scenarios/cp-rhel/roles/flink_standalone/tasks/main.yml
    - scenarios/cp-rhel/roles/flink_standalone/templates/flink-jobmanager.service.j2
    - scenarios/cp-rhel/roles/flink_standalone/templates/flink-taskmanager.service.j2
    - scenarios/cp-rhel/roles/flink_standalone/templates/flink-conf.yaml.j2
    - scenarios/cp-rhel/roles/flink_standalone/defaults/main.yml
    - scenarios/cp-rhel/roles/flink_standalone/handlers/main.yml
    - scenarios/cp-rhel/playbooks/deploy-flink.yml
    - scenarios/cp-rhel/playbooks/validate-fips.yml
    - scenarios/cp-rhel/inventory/group_vars/flink.yml
    - scripts/validate-fips.sh
  modified:
    - scenarios/cp-rhel/inventory/hosts.yml.example
    - scenarios/cp-rhel/README.md
    - .env.example

key-decisions:
  - "Standalone Apache Flink 1.20 used because CP Flink requires Kubernetes -- RHEL must use open-source standalone mode"
  - "Flink SR integration via connector JAR in lib/, not flink-conf.yaml (SR URL is a Flink SQL DDL property, not a native config key)"
  - "FIPS validation covers both CP-RHEL (5 checks) and CFK-OpenShift (3 checks) in a single playbook with separate plays"
  - "validate-fips.sh has --check mode for CI syntax validation without requiring a FIPS-enabled host"

patterns-established:
  - "Custom Ansible role pattern: defaults, tasks, templates, handlers structure for non-cp-ansible components"
  - "FIPS validation pattern: OS-level + keystore type + crypto provider checks per CP component"
  - "Multi-deployment FIPS validation: same playbook covers both Ansible-managed and Kubernetes-managed deployments"

requirements-completed: [FLINK-03, COMP-03]

duration: 4min
completed: 2026-03-27
---

# Phase 09 Plan 04: Flink Standalone and FIPS Validation Summary

**Standalone Flink 1.20 Ansible role with systemd services, avro-confluent SR connector, FIPS 140-2 validation playbook for CP-RHEL and CFK-OpenShift, and .env.example Section 16 for CP/Private Cloud variables**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-27T01:00:00Z
- **Completed:** 2026-03-27T01:04:00Z
- **Tasks:** 2
- **Files modified:** 13

## Accomplishments
- Custom Ansible role deploys standalone Apache Flink with JobManager/TaskManager systemd services, JMX metrics, and flink-sql-avro-confluent connector JAR for Schema Registry integration
- FIPS 140-2 validation playbook checks 5 items on CP-RHEL (OS FIPS mode, Java 17+, BCFKS keystore per component, BC FIPS provider, result report) and 3 items on CFK-OpenShift (node FIPS, operator deployment, fipsmode flag)
- Standalone validate-fips.sh script provides CI-safe --check mode and --cfk mode for OpenShift clusters
- .env.example Section 16 covers CP deployment (Ansible), Private Cloud (Terraform), MRC backend, standalone Flink, and FIPS settings

## Task Commits

Each task was committed atomically:

1. **Task 1: Create standalone Flink Ansible role with systemd and SR integration** - `ba5cb5c` (feat)
2. **Task 2: Add FIPS 140-2 compliance validation and .env.example CP/Private Cloud section** - `a33f1c3` (feat)

## Files Created/Modified
- `scenarios/cp-rhel/roles/flink_standalone/defaults/main.yml` - Default variables: Flink version, SR connector, cluster config, JMX, systemd settings
- `scenarios/cp-rhel/roles/flink_standalone/tasks/main.yml` - Ansible tasks for user/group, download, extract, connector JAR, templates, systemd
- `scenarios/cp-rhel/roles/flink_standalone/templates/flink-jobmanager.service.j2` - systemd unit for Flink JobManager with JMX env
- `scenarios/cp-rhel/roles/flink_standalone/templates/flink-taskmanager.service.j2` - systemd unit for Flink TaskManager with JMX env (port+1)
- `scenarios/cp-rhel/roles/flink_standalone/templates/flink-conf.yaml.j2` - Flink config with JM/TM settings, REST endpoint, JMX metrics reporter, SR URL documented
- `scenarios/cp-rhel/roles/flink_standalone/handlers/main.yml` - Handlers for systemd reload and service restart
- `scenarios/cp-rhel/playbooks/deploy-flink.yml` - Playbook targeting flink_jobmanager and flink_taskmanager groups
- `scenarios/cp-rhel/playbooks/validate-fips.yml` - FIPS validation for CP-RHEL and CFK-OpenShift
- `scenarios/cp-rhel/inventory/group_vars/flink.yml` - Flink-specific group vars (SR URL, REST port, JMX)
- `scenarios/cp-rhel/inventory/hosts.yml.example` - Added flink_jobmanager and flink_taskmanager host groups
- `scenarios/cp-rhel/README.md` - Added Standalone Flink section with deploy instructions and Flink SQL example
- `scripts/validate-fips.sh` - Standalone FIPS validation script with --check, --cfk modes
- `.env.example` - Added Section 16 for CP on RHEL and Private Cloud

## Decisions Made
- Standalone Apache Flink 1.20 used because CP Flink requires Kubernetes -- RHEL must use open-source standalone mode
- Flink SR integration via connector JAR in $FLINK_HOME/lib/, not flink-conf.yaml (SR URL is a Flink SQL DDL property, not a native config key)
- FIPS validation covers both CP-RHEL (OS-level + component config) and CFK-OpenShift (node + operator) in a single playbook
- validate-fips.sh --check mode enables CI syntax validation without requiring a FIPS-enabled host

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Phase 09 is now complete (4/4 plans executed)
- CP on RHEL scenario has full component coverage: Kafka, SR, Connect, Flink, FIPS validation
- All four deployment models now have scenario directories: CC (AWS/Azure/GCP), CFK-OpenShift, CP-RHEL, Private Cloud

## Self-Check: PASSED

All 13 created/modified files verified on disk. Task commits ba5cb5c and a33f1c3 recorded in git log.

---
*Phase: 09-cp-on-rhel-and-private-cloud*
*Completed: 2026-03-27*

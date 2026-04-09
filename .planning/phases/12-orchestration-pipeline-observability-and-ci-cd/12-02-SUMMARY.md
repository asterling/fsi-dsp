---
phase: 12-orchestration-pipeline-observability-and-ci-cd
plan: 02
subsystem: observability
tags: [ansible, jmx-exporter, prometheus, grafana, alerting, file-sd-configs, cp-observability]

# Dependency graph
requires:
  - phase: 05-observability
    provides: Grafana dashboards (dashboard-*.json), alerts.yaml, jmx-exporter-stub.yaml
  - phase: 10-ansible-foundation
    provides: ansible/ directory structure, requirements.yml, ansible-lint config, conftest.py
provides:
  - cp_observability role deploying JMX exporter configs, Prometheus targets, Grafana dashboards, alert rules
  - community.grafana collection added to requirements.yml
  - Molecule test scenario for cp_observability
  - 48 pytest unit tests for role structure and wiring validation
affects: [12-orchestration-pipeline-observability-and-ci-cd, site.yml orchestration]

# Tech tracking
tech-stack:
  added: [community.grafana >= 1.7.0]
  patterns: [file_sd_configs for Prometheus auto-discovery, dual-method Grafana provisioning, JMX exporter templates per CP component]

key-files:
  created:
    - ansible/roles/cp_observability/defaults/main.yml
    - ansible/roles/cp_observability/meta/main.yml
    - ansible/roles/cp_observability/tasks/main.yml
    - ansible/roles/cp_observability/tasks/jmx_exporter.yml
    - ansible/roles/cp_observability/tasks/prometheus.yml
    - ansible/roles/cp_observability/tasks/grafana.yml
    - ansible/roles/cp_observability/tasks/check.yml
    - ansible/roles/cp_observability/templates/prometheus_targets.json.j2
    - ansible/roles/cp_observability/templates/jmx_exporter_broker.yml.j2
    - ansible/roles/cp_observability/templates/jmx_exporter_connect.yml.j2
    - ansible/roles/cp_observability/templates/jmx_exporter_schema_registry.yml.j2
    - ansible/roles/cp_observability/templates/grafana_dashboard_provider.yml.j2
    - ansible/roles/cp_observability/molecule/default/molecule.yml
    - ansible/roles/cp_observability/molecule/default/converge.yml
    - ansible/roles/cp_observability/molecule/default/verify.yml
    - tests/ansible/test_cp_observability.py
  modified:
    - ansible/requirements.yml

key-decisions:
  - "JMX exporter ports follow cp-ansible defaults: broker=8080, SR=8078, Connect=8077, ZK=8079"
  - "Prometheus targets use file_sd_configs for zero-restart service discovery from inventory"
  - "Grafana dual-method: file_provisioning (default) for production, api for development/testing"
  - "FQCN test uses YAML parsing instead of text scanning to avoid false positives on parameter keys"

patterns-established:
  - "Observability role pattern: deploy flags for selective Day-2 operations (cp_obs_deploy_jmx, etc.)"
  - "Jinja2 template for Prometheus file_sd_configs iterating over Ansible inventory groups"
  - "JMX exporter templates per component derived from Phase 5 jmx-exporter-stub.yaml"

requirements-completed: [AOBS-01, AOBS-02, AOBS-03, AOBS-04, ACI-02]

# Metrics
duration: 5min
completed: 2026-04-09
---

# Phase 12 Plan 02: cp_observability Summary

**Ansible role deploying JMX exporter configs per CP component, auto-generating Prometheus file_sd_configs from inventory, importing Grafana dashboards via file provisioning or API, and deploying SLA-tier-aware alert rules from alerts.yaml**

## Performance

- **Duration:** 5 min
- **Started:** 2026-04-09T16:01:02Z
- **Completed:** 2026-04-09T16:05:42Z
- **Tasks:** 1 (TDD: RED + GREEN)
- **Files modified:** 17

## Accomplishments

- JMX exporter configs deployed per component with correct default ports (broker:8080, SR:8078, Connect:8077) using Jinja2 templates derived from Phase 5 jmx-exporter-stub.yaml
- Prometheus scrape targets auto-generated from inventory host groups (kafka_broker, schema_registry, kafka_connect, zookeeper) via file_sd_configs JSON template
- Grafana dashboards imported from observability/grafana/ with dual-method support (file_provisioning for production, community.grafana API for development)
- SLA-tier-aware alert rules deployed from alerts.yaml to Grafana alert provisioning directory
- 48 pytest unit tests covering role structure, default values, template wiring, FQCN enforcement, and task naming conventions

## Task Commits

Each task was committed atomically:

1. **Task 1 (RED): Failing tests for cp_observability** - `c75ce86` (test)
2. **Task 1 (GREEN): Implement cp_observability role** - `a0f43c2` (feat)

_TDD task with RED and GREEN commits._

## Files Created/Modified

- `ansible/roles/cp_observability/defaults/main.yml` - Default variables: JMX ports, directories, Grafana config, deploy flags
- `ansible/roles/cp_observability/meta/main.yml` - Galaxy metadata: role_name, platforms (EL 8/9), tags
- `ansible/roles/cp_observability/tasks/main.yml` - Entry point: conditional dispatch based on cp_obs_deploy_* flags
- `ansible/roles/cp_observability/tasks/jmx_exporter.yml` - JMX exporter config deployment to broker, SR, Connect nodes
- `ansible/roles/cp_observability/tasks/prometheus.yml` - Prometheus file_sd_configs generation from inventory
- `ansible/roles/cp_observability/tasks/grafana.yml` - Dashboard import (file/api) + alert rule deployment
- `ansible/roles/cp_observability/tasks/check.yml` - GET-only state reporting for check mode
- `ansible/roles/cp_observability/templates/prometheus_targets.json.j2` - Jinja2 template for file_sd JSON targets
- `ansible/roles/cp_observability/templates/jmx_exporter_broker.yml.j2` - Broker JMX exporter with ReplicaManager, BrokerTopicMetrics rules
- `ansible/roles/cp_observability/templates/jmx_exporter_connect.yml.j2` - Connect JMX exporter with worker-metrics, connector-metrics rules
- `ansible/roles/cp_observability/templates/jmx_exporter_schema_registry.yml.j2` - SR JMX exporter with jersey-metrics, schema count rules
- `ansible/roles/cp_observability/templates/grafana_dashboard_provider.yml.j2` - Grafana auto-provisioning config
- `ansible/roles/cp_observability/molecule/default/molecule.yml` - Delegated driver molecule scenario
- `ansible/roles/cp_observability/molecule/default/converge.yml` - Converge with deploy flags disabled
- `ansible/roles/cp_observability/molecule/default/verify.yml` - Verify cp_observability_results fact
- `ansible/requirements.yml` - Added community.grafana >= 1.7.0
- `tests/ansible/test_cp_observability.py` - 48 unit tests across 10 test classes

## Decisions Made

- **JMX exporter ports follow cp-ansible defaults**: broker=8080, SR=8078, Connect=8077, ZK=8079 -- matches cp-ansible 7.7.x conventions for consistency
- **Prometheus file_sd_configs over static config**: Prometheus watches JSON target files and auto-discovers new nodes without restart -- ideal for Ansible-managed inventory changes
- **Grafana dual-method provisioning**: file_provisioning as default (reliable, no API key needed), api as optional for teams with Grafana API access
- **FQCN test refined to YAML parsing**: Text-based scanning produced false positives on parameter keys (e.g., `file:` under `include_tasks`); switched to YAML-parsed task action key detection

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Refined FQCN test to avoid false positives on parameter keys**
- **Found during:** Task 1 GREEN phase
- **Issue:** Text-based bare module scanning flagged `file: check.yml` (a parameter of `ansible.builtin.include_tasks`) as a bare module reference
- **Fix:** Switched to YAML-parsed task key detection instead of line-by-line text scanning
- **Files modified:** tests/ansible/test_cp_observability.py
- **Verification:** All 48 tests pass including FQCN check
- **Committed in:** a0f43c2

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Minor test refinement for correctness. No scope creep.

## Issues Encountered

None.

## Known Stubs

None -- all role functionality is fully wired to existing observability assets.

## Next Phase Readiness

- cp_observability role ready for inclusion in site.yml orchestration playbook (Plan 12-01 or 12-03)
- Role registers cp_observability_results fact for downstream pipeline reporting
- community.grafana collection added to requirements.yml for API-based dashboard import

## Self-Check: PASSED

- All 17 files verified present on disk
- Both commit hashes (c75ce86, a0f43c2) verified in git log
- 48/48 pytest tests passing

---
*Phase: 12-orchestration-pipeline-observability-and-ci-cd*
*Completed: 2026-04-09*

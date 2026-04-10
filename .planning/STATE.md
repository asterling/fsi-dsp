---
gsd_state_version: 1.0
milestone: v2.0
milestone_name: Ansible Based Automation
status: verifying
stopped_at: Completed 13-02-PLAN.md (cp_dr_mm2 failback sequence)
last_updated: "2026-04-10T12:59:13.041Z"
last_activity: 2026-04-10
progress:
  total_phases: 15
  completed_phases: 13
  total_plans: 38
  completed_plans: 38
  percent: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-07)

**Core value:** Any FSI team can stand up a fully governed, observable, DR-ready Kafka/Flink/SR cluster in their deployment model of choice with a single automation run -- and onboard their first topic in under a day.
**Current focus:** Phase 13 — dr-automation-playbooks-mm2

## Current Position

Phase: 14
Plan: Not started
Status: Phase complete — ready for verification
Last activity: 2026-04-10

Progress: [░░░░░░░░░░] 0%

## Performance Metrics

**v1.0 Summary:**

- 9 phases, 28 plans completed
- Average plan duration: ~4.5 min

**v2.0 Velocity:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| - | - | - | - |

*Updated after each plan completion*
| Phase 10 P01 | 2min | 2 tasks | 16 files |
| Phase 10 P02 | 3min | 2 tasks | 7 files |
| Phase 11 P02 | 5min | 2 tasks | 16 files |
| Phase 11 P01 | 6min | 2 tasks | 20 files |
| Phase 11 P03 | 5min | 2 tasks | 17 files |
| Phase 12 P02 | 5min | 1 tasks | 17 files |
| Phase 12 P01 | 5min | 2 tasks | 18 files |
| Phase 12 P03 | 2min | 1 tasks | 2 files |
| Phase 13 P01 | 4min | 1 tasks | 19 files |
| Phase 13 P02 | 4min | 1 tasks | 5 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.

**v2.0 decisions:**

- Same repo with `ansible/` directory (shared governance artifacts, schemas, ADRs, validation scripts)
- CC stays Terraform-only (no native Ansible provider)
- Confluent Platform only (cp-ansible collection, MDS RBAC, Confluent CLI)
- Build order: foundation -> governance roles -> orchestration/DR/CFK/drill
- `ansible.builtin.uri` over custom modules for all REST API operations
- Standalone roles (not Galaxy collection) -- tightly coupled to repo governance data

**v1.0 decisions carried forward (relevant to v2.0):**

- Topic naming: {domain}.{application}.{version}.{entity} with dot separators (ADR-007)
- SLA tiers: critical/standard/best-effort/compliance with mapped defaults (ADR-008)
- CPTopic YAML format mirrors CFK KafkaTopic CRD with kind: CPTopic
- MRC uses kafka-leader-election.sh with PREFERRED election type
- [Phase 10]: CP version 7.7.0 in inventories (upgraded from cp-rhel 7.6.0 to match cp-ansible 7.7.x collection)
- [Phase 10]: ansible-lint shared profile plus explicit FQCN enforcement (not in shared by default)
- [Phase 10]: conftest.py over __init__.py for tests/ansible/ to avoid ansible namespace collision
- [Phase 10]: Embedded SLA_TIERS dict in filter plugin for O(1) runtime lookups; parity test validates sync with YAML
- [Phase 11]: Used failed_when: false instead of ignore_errors: true for ansible-lint shared profile compliance in cp_schema role
- [Phase 11]: Added process_one.yml dispatcher to separate per-topic logic from main loop
- [Phase 11]: Task names start with uppercase and Jinja at end only (ansible-lint name[casing] and name[template] rules)
- [Phase 11]: noqa ignore-errors on include_tasks for locked error collection decision
- [Phase 11]: MDS token refresh reads actual expires_in from response, not hardcoded TTL
- [Phase 12]: JMX exporter ports follow cp-ansible 7.7.x defaults (broker=8080, SR=8078, Connect=8077, ZK=8079)
- [Phase 12]: Prometheus file_sd_configs for zero-restart service discovery from Ansible inventory
- [Phase 12]: Grafana dual-method: file_provisioning (default/production) and API (development)
- [Phase 12]: Disjoint tag sets per play in site.yml to prevent import_playbook tag inheritance leakage
- [Phase 12]: PUT /connectors/{name}/config for idempotent create-or-update (201 new, 200 update)
- [Phase 12]: PyYAML parses YAML on key as boolean True; CI workflow tests use wf.get(on) or wf.get(True)
- [Phase 13]: sla_tier_mirror_lag as separate top-level key in sla_tiers.yml to avoid breaking parity test
- [Phase 13]: Connector-level health validation via REST API; per-topic lag deferred to Prometheus/JMX
- [Phase 13]: Reuse consul_flip.yml with vars override for failback region cutback
- [Phase 13]: Jinja replace filter for connector name reversal (east-west -> west-east)

### Pending Todos

None yet.

### Blockers/Concerns

- MDS REST API binding enumeration pattern needs validation against running CP 7.7 instance (Phase 11)
- Admin REST v3 config:alter request body needs confirmation (Phase 11)
- RHEL 8 vs RHEL 9 customer prevalence unknown -- affects ansible-core version target

## Session Continuity

Last session: 2026-04-10T12:54:20.983Z
Stopped at: Completed 13-02-PLAN.md (cp_dr_mm2 failback sequence)
Resume file: None

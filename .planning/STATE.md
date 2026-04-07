---
gsd_state_version: 1.0
milestone: v2.0
milestone_name: Ansible Based Automation
status: defining-requirements
stopped_at: Milestone v2.0 started
last_updated: "2026-04-07T00:00:00.000Z"
progress:
  total_phases: 0
  completed_phases: 0
  total_plans: 0
  completed_plans: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-07)

**Core value:** Any FSI team can stand up a fully governed, observable, DR-ready Kafka/Flink/SR cluster in their deployment model of choice with a single automation run -- and onboard their first topic in under a day.
**Current focus:** Milestone v2.0 — Ansible Based Automation

## Current Position

Phase: Not started (defining requirements)
Plan: —
Status: Defining requirements
Last activity: 2026-04-07 — Milestone v2.0 started

## Performance Metrics

**v1.0 Summary:**
- 9 phases, 28 plans completed
- Average plan duration: ~4.5 min

**v2.0 Velocity:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| - | - | - | - |

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.

**v2.0 decisions:**
- Same repo with `ansible/` directory (shared governance artifacts, schemas, ADRs, validation scripts)
- CC stays Terraform-only (no native Ansible provider)
- Confluent Platform only (cp-ansible collection, MDS RBAC, Confluent CLI)
- Build order: governance roles first → deployment pipeline → DR automation

**v1.0 decisions carried forward (relevant to v2.0):**
- Topic naming: {domain}.{application}.{version}.{entity} with dot separators (ADR-007)
- SLA tiers: critical/standard/best-effort/compliance with mapped defaults (ADR-008)
- DR tier classification: RPO/RTO per SLA tier, deployment-model-specific backends
- Schema namespace: org.fsi.{domain}.{app}.v{N}
- Python stdlib only for schema validation (no pip deps in CI)
- CP-RHEL: Playbook split per component group for tag-based selective deployment
- CP-RHEL: RF=5 with min.insync.replicas=3 for critical/compliance tiers
- CPTopic YAML format mirrors CFK KafkaTopic CRD with kind: CPTopic
- MRC uses kafka-leader-election.sh with PREFERRED election type
- FIPS validation covers both CP-RHEL and CFK-OpenShift

### Pending Todos

None yet.

### Blockers/Concerns

- cp-ansible v8.2.0 role structure needs investigation for integration points
- MDS REST API for RBAC provisioning needs documented endpoints
- Molecule test infrastructure for Ansible roles needs design decision

## Session Continuity

Last session: 2026-04-07
Stopped at: Milestone v2.0 initialization — defining requirements
Resume file: None

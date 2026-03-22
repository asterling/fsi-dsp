---
phase: 01-shared-governance-foundation
plan: 03
subsystem: governance
tags: [adr, oauth, topic-naming, dr, sla-tier, rpo, rto, cluster-linking, mrc]

# Dependency graph
requires:
  - phase: none
    provides: existing ADR template and numbering (000-005)
provides:
  - ADR-006 OAuth vs API Keys authentication decision with per-deployment-model guidance
  - ADR-007 Topic Naming Convention with regex validation and dot separator rationale
  - ADR-008 DR Tier Classification with RPO/RTO targets per SLA tier
affects: [02-cc-aws-scenario, 03-cc-azure-scenario, 04-dr-automation, 05-observability, 08-cfk-openshift, 09-cp-rhel]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "ADR template: Context/Decision/Consequences with Status/Date/Author header"
    - "Per-deployment-model guidance tables in architectural decisions"

key-files:
  created:
    - docs/adr/006-oauth-vs-api-keys.md
    - docs/adr/007-topic-naming.md
    - docs/adr/008-dr-tier-classification.md
  modified: []

key-decisions:
  - "OAuth/OAUTHBEARER is primary auth for CC; API keys as fallback for on-prem and Terraform provider"
  - "Topic naming follows {domain}.{application}.{version}.{entity} with dot separators"
  - "DR tier classification maps 4 SLA tiers to RPO/RTO targets with deployment-model-specific backends"

patterns-established:
  - "ADR authoring: follow 000-template.md, sequential numbering, FSI C4E as author"
  - "Per-deployment-model tables: CC/CFK/CP columns for cross-cutting decisions"

requirements-completed: [GOV-01, GOV-02, GOV-03]

# Metrics
duration: 2min
completed: 2026-03-22
---

# Phase 01 Plan 03: Governance ADRs Summary

**Three ADRs documenting OAuth auth strategy, topic naming convention with regex validation, and DR tier classification with RPO/RTO targets per SLA tier and deployment model**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-22T02:16:08Z
- **Completed:** 2026-03-22T02:18:31Z
- **Tasks:** 2
- **Files created:** 3

## Accomplishments
- ADR-006 documents OAuth/OAUTHBEARER as primary auth for CC with per-deployment-model table (CC: OAuth, CFK: LDAP/MDS, CP: MDS/LDAP) and credential rotation guidance
- ADR-007 documents topic naming convention `{domain}.{application}.{version}.{entity}` with regex per segment, dot separator rationale, version rationale, and Avro namespace mapping
- ADR-008 maps all 4 SLA tiers to RPO/RTO targets (critical: <5m/<15m, standard: <2h/<1h, best-effort: <24h/<4h, compliance: RPO=0/<15m) with DR backend per deployment model

## Task Commits

Each task was committed atomically:

1. **Task 1: Write ADR-006 OAuth vs API Keys and ADR-007 Topic Naming** - `40d6413` (docs)
2. **Task 2: Write ADR-008 DR Tier Classification** - `ac8abd3` (docs)

## Files Created/Modified
- `docs/adr/006-oauth-vs-api-keys.md` - OAuth/OAUTHBEARER auth recommendation with deployment-model table and credential rotation guidance
- `docs/adr/007-topic-naming.md` - Topic naming convention with regex validation, dot separator rationale, and Avro namespace mapping
- `docs/adr/008-dr-tier-classification.md` - DR tier classification with RPO/RTO targets, backend selection, and compliance RPO=0 strategy

## Decisions Made
- Followed plan exactly as specified for all three ADRs
- Used existing ADR template structure (Context/Decision/Consequences) with Status/Date/Author header
- Referenced existing ADRs (ADR-002 for SLA tiers, ADR-005 for Cluster Linking) in ADR-008

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- ADRs 006-008 establish governance decisions that Phase 2+ scenarios must follow
- ADR-006 provides auth guidance for each deployment model scenario
- ADR-007 provides naming convention enforced by the topic module (already implemented in `modules/topic/variables.tf`)
- ADR-008 provides DR tier targets for the DR automation framework (Phase 4) and observability templates (Phase 5)

## Self-Check: PASSED

All files verified present. All commit hashes verified in git log.

---
*Phase: 01-shared-governance-foundation*
*Completed: 2026-03-22*

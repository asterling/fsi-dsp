---
phase: 01-shared-governance-foundation
plan: 02
subsystem: ci, schema-governance
tags: [python, avro, schema-registry, github-actions, ci-pipeline, bash]

# Dependency graph
requires:
  - phase: none
    provides: existing schemas in schemas/examples/, existing CI workflow
provides:
  - ci/scripts/validate-schemas.py for Avro schema structure, namespace, and SR compatibility validation
  - ci/scripts/check-overrides.sh for compatibility_override detection with ADR/JIRA enforcement
  - Enhanced CI workflow with schema validation pipeline (structure + SR compat + override check)
  - Breaking Change Runbook (5-step process) in docs/schema-guide.md
affects: [01-shared-governance-foundation, 02-cc-aws-scenario, 03-cc-azure-migration, 04-cc-gcp-scenario]

# Tech tracking
tech-stack:
  added: []
  patterns: [schema-CI-validation-pipeline, SR-compatibility-graceful-degradation, override-detection-with-audit-trail]

key-files:
  created:
    - ci/scripts/validate-schemas.py
    - ci/scripts/check-overrides.sh
  modified:
    - .github/workflows/terraform-plan.yml
    - docs/schema-guide.md

key-decisions:
  - "Used Python stdlib only (json, re, urllib) instead of fastavro/requests -- zero pip dependencies in CI"
  - "SR compatibility check is continue-on-error to prevent SR outages from blocking all PRs"
  - "Override detection only checks environments/ and scenarios/ .tf files, not modules/ (avoids false positives on variable definitions)"
  - "Namespace pattern validated as org.fsi.{domain}.{application}.v{N} -- entity is the Avro record name, not part of namespace"

patterns-established:
  - "Schema CI Validation Pipeline: structure/namespace always blocks, SR compat degrades gracefully"
  - "Override governance: compatibility_override in scenario files requires ADR/JIRA reference in PR body"
  - "Breaking change process: 5-step runbook (versioned topic, dual-write, migrate, deprecate, decommission)"

requirements-completed: [SCHEMA-01, SCHEMA-02, SCHEMA-03, SCHEMA-04]

# Metrics
duration: 3min
completed: 2026-03-22
---

# Phase 01 Plan 02: Schema CI Validation Pipeline Summary

**Python schema validation script with namespace/compatibility checks, override detection in CI, and 5-step breaking change runbook**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-22T02:16:10Z
- **Completed:** 2026-03-22T02:19:23Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- Schema validation script validates all 7 existing .avsc files for structure (JSON, record type, fields) and namespace convention (org.fsi.{domain}.{app}.v{N})
- CI workflow enhanced with three new validation steps: schema structure/namespace (always blocks), SR compatibility (graceful degradation), and override detection (requires ADR/JIRA)
- Breaking Change Runbook added to schema-guide.md with 5-step process covering versioned topics, dual-write, consumer migration, deprecation, and decommission
- Override checker excludes modules/ directory to avoid false positives on variable definitions

## Task Commits

Each task was committed atomically:

1. **Task 1: Create schema validation Python script and override checker** - `fcf23d1` (feat)
2. **Task 2: Enhance CI workflow and add breaking change runbook** - `3f765f1` (feat)

## Files Created/Modified
- `ci/scripts/validate-schemas.py` - Avro schema validation: structure, namespace convention, optional SR compatibility check (stdlib only)
- `ci/scripts/check-overrides.sh` - Detects compatibility_override in environment/scenario .tf files, requires ADR/JIRA reference in PR body
- `.github/workflows/terraform-plan.yml` - Enhanced with schema validation pipeline steps, ci/** path trigger, expanded naming convention checks
- `docs/schema-guide.md` - Added Breaking Change Runbook section with 5-step migration process

## Decisions Made
- Used Python stdlib only (json, re, urllib, argparse, glob, base64) -- no pip install needed in CI runners, matching the existing inline Python pattern
- SR compatibility check runs as separate step with continue-on-error: true per Research Pitfall 2 (SR outage should not block all PRs)
- Override detection greps only environments/ and scenarios/ paths, excluding modules/ per Research Pitfall 6 (avoid matching the variable declaration itself)
- Namespace pattern follows org.fsi.{domain}.{application}.v{N} per Research Pitfall 4 (entity is the Avro record name, not part of the namespace)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Schema CI validation pipeline ready for all future schema changes
- CI workflow triggers on ci/** changes so script updates are automatically validated
- Breaking change runbook provides self-service guidance for teams needing incompatible schema changes
- Override detection ready for when teams start using compatibility_override in scenario files

## Self-Check: PASSED

All files verified present. All commit hashes found in git log.

---
*Phase: 01-shared-governance-foundation*
*Completed: 2026-03-22*

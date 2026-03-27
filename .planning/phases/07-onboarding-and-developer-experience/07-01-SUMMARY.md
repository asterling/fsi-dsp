---
phase: 07-onboarding-and-developer-experience
plan: 01
subsystem: governance
tags: [github-issue-forms, c4e-automation, python, ci-cd, naming-validation, rbac, pii-audit]

# Dependency graph
requires:
  - phase: 01-governance-foundation
    provides: "Topic naming convention (ADR-007), SLA tier classification (ADR-008), schema validation scripts"
  - phase: 02-cc-multi-cloud-scenarios
    provides: "Reusable terraform-scenario.yml workflow, scenario directory structure"
provides:
  - "YAML issue form with structured dropdowns for deployment model, SLA tier, data classification, and Flink"
  - "C4E pre-check Python script with 5 validation categories (naming, schema, RBAC, SLA tier, PII)"
  - "CI workflow integration running pre-checks on PRs before Terraform init"
affects: [07-02, 07-03, future-c4e-enhancements]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "GitHub issue forms (YAML) for structured intake"
    - "C4E pre-check automation before human review gate"
    - "Regex-based Terraform source file parsing for module argument extraction"

key-files:
  created:
    - ".github/ISSUE_TEMPLATE/new-topic-request.yml"
    - ".github/ISSUE_TEMPLATE/new-topic-request-legacy.md"
    - "ci/scripts/c4e-precheck.py"
  modified:
    - ".github/workflows/terraform-scenario.yml"

key-decisions:
  - "YAML issue form uses generic FSI examples (corebanking, fraud, compliance) -- no client-specific references per D-02"
  - "C4E pre-check parses .tf source files via regex -- does not require Terraform init or state access per Pitfall 7"
  - "C4E pre-check blocks PRs on failure (no continue-on-error) -- human review is final gate, not first check per D-04"
  - "Legacy .md template preserved as new-topic-request-legacy.md with DEPRECATED comment for reference"

patterns-established:
  - "C4E pre-check pattern: parse .tf source -> extract module args -> validate against tier/naming/RBAC rules"
  - "Variable reference detection: var.* references treated as non-empty (CI cannot resolve Terraform variables)"

requirements-completed: [ONBOARD-01, ONBOARD-02]

# Metrics
duration: 3min
completed: 2026-03-27
---

# Phase 7 Plan 1: Intake Form & C4E Automation Summary

**YAML issue form with deployment model/SLA/Flink dropdowns plus Python C4E pre-check automating 5 validation categories (naming, schema, RBAC, SLA tier, PII) in CI before human review**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-27T14:34:51Z
- **Completed:** 2026-03-27T14:38:07Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- Converted freeform markdown intake form to structured YAML issue form with dropdowns for all 5 deployment models, 4 SLA tiers, 3 data classifications, and optional Flink section
- Built C4E pre-check script with 5 validation categories using Python stdlib only, matching existing validate-schemas.py pattern
- Wired C4E pre-check into CI workflow as a blocking step on PRs, running after schema validation and before Terraform init

## Task Commits

Each task was committed atomically:

1. **Task 1: Convert intake form + create C4E pre-check script** - `8480e35` (feat)
2. **Task 2: Wire C4E pre-check into CI workflow** - `42da5d8` (feat)

## Files Created/Modified
- `.github/ISSUE_TEMPLATE/new-topic-request.yml` - YAML issue form with structured dropdowns for deployment model, SLA tier, data classification, Flink, access control, and schema
- `.github/ISSUE_TEMPLATE/new-topic-request-legacy.md` - Renamed old markdown template with DEPRECATED comment
- `ci/scripts/c4e-precheck.py` - Python C4E pre-check script with 5 checks: naming, schema, RBAC, SLA tier, PII audit
- `.github/workflows/terraform-scenario.yml` - Added C4E Pre-Check Suite step in lint job

## Decisions Made
- YAML issue form uses generic FSI examples (corebanking, fraud, compliance) with no client-specific references (D-02)
- C4E pre-check parses .tf source files via regex, does not require Terraform init or state (Pitfall 7)
- C4E pre-check blocks PRs on failure (no continue-on-error) -- human review is the final gate, not the first check (D-04)
- Legacy .md template preserved as new-topic-request-legacy.md for reference during transition
- Variable references (var.*) treated as non-empty since CI cannot resolve Terraform variables

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Intake form and C4E automation foundation complete
- Ready for Plan 2 (Python reference producer/consumer) and Plan 3 (error-path tests, DLQ, local dev Flink)
- C4E pre-check script can be extended with additional checks as needed

## Self-Check: PASSED

All files exist. All commit hashes verified.

---
*Phase: 07-onboarding-and-developer-experience*
*Completed: 2026-03-27*

---
phase: 09-cp-on-rhel-and-private-cloud
plan: 02
subsystem: infra
tags: [terraform, confluent-platform, private-cloud, c4e-precheck, cptopic, yaml]

requires:
  - phase: 01-governance-foundation
    provides: shared modules/topic module with governance variables
  - phase: 07-onboarding-and-developer-experience
    provides: c4e-precheck.py with TF and CFK parsers
  - phase: 08-cfk-on-openshift
    provides: CFK KafkaTopic YAML pattern and parse_cfk_topics function

provides:
  - Private Cloud Terraform scenario directory (scenarios/private-cloud/)
  - CPTopic YAML parser in c4e-precheck.py (parse_cp_topics function)
  - 3 CPTopic YAML definitions for cp-rhel scenario
  - C4E validation parity across all 3 deployment model types (TF, CFK, CP)

affects: [09-cp-on-rhel-and-private-cloud, ci-cd-pipelines]

tech-stack:
  added: []
  patterns: [CPTopic YAML CRD format for CP-RHEL topic definitions, kafka_rest_endpoint provider mode for Private Cloud]

key-files:
  created:
    - scenarios/private-cloud/README.md
    - scenarios/private-cloud/main.tf
    - scenarios/private-cloud/variables.tf
    - scenarios/private-cloud/example-topics.tf
    - scenarios/private-cloud/terraform.tfvars.example
    - scenarios/cp-rhel/topics/corebanking-account-txn.yml
    - scenarios/cp-rhel/topics/fraud-alert-signal.yml
    - scenarios/cp-rhel/topics/compliance-screening-result.yml
  modified:
    - ci/scripts/c4e-precheck.py

key-decisions:
  - "Private Cloud provider uses kafka_rest_endpoint mode (no cloud_api_key) for self-managed CP clusters"
  - "CPTopic YAML format mirrors CFK KafkaTopic CRD structure with kind: CPTopic for parser differentiation"
  - "CP topics RBAC placeholder is <cp-mds> since MDS manages RBAC outside YAML definitions"
  - "Terraform version constraint lowered to >= 1.5 matching cc-aws pattern for local validation compatibility"

patterns-established:
  - "CPTopic YAML: kind: CPTopic with fsi.* governance labels in metadata.labels"
  - "Three-parser C4E precheck: parse_tf_modules + parse_cfk_topics + parse_cp_topics"

requirements-completed: [IAC-05]

duration: 4min
completed: 2026-03-28
---

# Phase 09 Plan 02: Private Cloud Scenario and CPTopic Precheck Summary

**Private Cloud Terraform scenario with kafka_rest_endpoint provider and CPTopic YAML parser extending C4E precheck to validate all 3 deployment model types**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-28T00:51:57Z
- **Completed:** 2026-03-28T00:55:46Z
- **Tasks:** 2
- **Files modified:** 9

## Accomplishments

- Private Cloud scenario directory with Confluent provider configured via kafka_rest_endpoint for self-managed CP clusters
- 3 example topic modules reusing shared governance module (identical to CC and CFK scenarios)
- CPTopic YAML parser (parse_cp_topics) integrated into c4e-precheck.py
- 3 CPTopic YAML definitions created for cp-rhel scenario
- All 4 scenarios validate without regression: cp-rhel (3 CP topics), private-cloud (3 TF modules), cfk-openshift (3 CFK topics), cc-aws (3 TF modules)

## Task Commits

Each task was committed atomically:

1. **Task 1: Create Private Cloud Terraform scenario directory** - `b793d3a` (feat)
2. **Task 2: Extend c4e-precheck.py with CPTopic YAML parser** - `a8b78aa` (feat)

## Files Created/Modified

- `scenarios/private-cloud/README.md` - Private Cloud scenario documentation with Quick Start
- `scenarios/private-cloud/main.tf` - Confluent provider with kafka_rest_endpoint for CP cluster
- `scenarios/private-cloud/variables.tf` - CP cluster endpoint and credential variables (sensitive)
- `scenarios/private-cloud/example-topics.tf` - 3 reference topic modules using shared governance
- `scenarios/private-cloud/terraform.tfvars.example` - Example values for CP REST endpoints
- `scenarios/cp-rhel/topics/corebanking-account-txn.yml` - CPTopic YAML for corebanking topic
- `scenarios/cp-rhel/topics/fraud-alert-signal.yml` - CPTopic YAML for fraud detection topic
- `scenarios/cp-rhel/topics/compliance-screening-result.yml` - CPTopic YAML for compliance topic
- `ci/scripts/c4e-precheck.py` - Added parse_cp_topics(), updated main() to combine all 3 parsers

## Decisions Made

- Private Cloud provider uses kafka_rest_endpoint mode (no cloud_api_key) for self-managed CP clusters
- CPTopic YAML format mirrors CFK KafkaTopic CRD structure with `kind: CPTopic` for parser differentiation
- CP topics RBAC placeholder is `<cp-mds>` since MDS manages RBAC outside YAML definitions
- Terraform version constraint lowered to `>= 1.5` matching cc-aws pattern for local validation compatibility

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Lowered Terraform required_version from >= 1.7.0 to >= 1.5**
- **Found during:** Task 1 (terraform validate)
- **Issue:** Plan specified >= 1.7.0 but local Terraform is 1.5.7; validate fails on version constraint
- **Fix:** Changed to >= 1.5 matching the cc-aws scenario pattern
- **Files modified:** scenarios/private-cloud/main.tf
- **Verification:** terraform init -backend=false && terraform validate exits 0
- **Committed in:** b793d3a (Task 1 commit)

**2. [Rule 3 - Blocking] Created CPTopic YAML files for cp-rhel scenario**
- **Found during:** Task 2 (c4e-precheck validation)
- **Issue:** scenarios/cp-rhel/topics/ directory existed but was empty; precheck needs topic files to validate
- **Fix:** Created 3 CPTopic YAML definitions matching governance label pattern
- **Files modified:** scenarios/cp-rhel/topics/*.yml (3 files)
- **Verification:** c4e-precheck.py --scenario-dir scenarios/cp-rhel/ --verbose finds 3 CPTopic definitions, all pass
- **Committed in:** a8b78aa (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (1 bug, 1 blocking)
**Impact on plan:** Both fixes necessary for validation. No scope creep.

## Issues Encountered

None beyond the auto-fixed deviations above.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Private Cloud scenario ready for teams to adopt
- C4E precheck validates all 3 deployment model types with same 5 governance checks
- Ready for Phase 09 Plan 03 (if any remaining plans)

---
*Phase: 09-cp-on-rhel-and-private-cloud*
*Completed: 2026-03-28*

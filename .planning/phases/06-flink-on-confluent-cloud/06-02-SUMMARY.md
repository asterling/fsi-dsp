---
phase: 06-flink-on-confluent-cloud
plan: 02
subsystem: reference
tags: [flink, sql, cc-flink, tumbling-window, stream-table-join, filter-route, dlq, avro]

# Dependency graph
requires:
  - phase: 06-flink-on-confluent-cloud
    provides: "06-RESEARCH.md with CC Flink SQL patterns, DLQ handling, and anti-patterns"
provides:
  - "Four Flink SQL reference templates (tumbling window, stream-table join, filter-and-route, DLQ)"
  - "README with SR auto-discovery, Terraform submission, common pitfalls"
affects: [06-flink-on-confluent-cloud, cc-aws, cc-azure, cc-gcp]

# Tech tracking
tech-stack:
  added: [CC Flink SQL]
  patterns: [tumbling-window-aggregation, stream-table-join-enrichment, filter-and-route-statement-set, dlq-via-table-properties]

key-files:
  created:
    - reference/flink-sql/tumbling-window-aggregation.sql
    - reference/flink-sql/stream-table-join-enrichment.sql
    - reference/flink-sql/filter-and-route.sql
    - reference/flink-sql/dlq-pattern.sql
    - reference/flink-sql/README.md
  modified: []

key-decisions:
  - "CC Flink SQL templates use auto-discovered tables (no CREATE TABLE with connector/format)"
  - "DLQ pattern uses CC-specific error-handling.mode table properties, not Apache Flink side outputs"
  - "FSI domain examples span corebanking, fraud, and compliance domains"

patterns-established:
  - "Reference SQL templates in reference/flink-sql/ with header comments explaining prerequisites, CC context, and adaptation guidance"
  - "DLQ via ALTER TABLE SET error-handling.mode/log.target (CC-specific pattern)"
  - "EXECUTE STATEMENT SET for multi-output filter-and-route patterns"

requirements-completed: [FLINK-04, FLINK-07]

# Metrics
duration: 2min
completed: 2026-03-27
---

# Phase 6 Plan 2: Flink SQL Reference Templates Summary

**Four CC Flink SQL templates (tumbling window, stream-table join, filter-and-route, DLQ) with FSI domain examples and usage README**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-27T01:23:43Z
- **Completed:** 2026-03-27T01:25:41Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments

- Created four Flink SQL reference templates covering the most common FSI stream processing patterns
- All templates use CC Flink syntax (auto-discovered tables, no CREATE TABLE anti-pattern)
- DLQ template demonstrates CC-specific error-handling.mode table properties with governance recommendation
- README covers SR auto-discovery, Terraform submission, and 6 common pitfalls

## Task Commits

Each task was committed atomically:

1. **Task 1: Create Flink SQL reference templates** - `eb20ed6` (feat)
2. **Task 2: Create Flink SQL reference README** - `a4a9bf3` (docs)

## Files Created/Modified

- `reference/flink-sql/tumbling-window-aggregation.sql` - 1-minute transaction volume aggregation using TUMBLE() TVF
- `reference/flink-sql/stream-table-join-enrichment.sql` - Fraud detection enrichment via temporal JOIN with customer profile
- `reference/flink-sql/filter-and-route.sql` - Compliance screening routing via EXECUTE STATEMENT SET
- `reference/flink-sql/dlq-pattern.sql` - Poison pill handling via CC error-handling.mode table properties
- `reference/flink-sql/README.md` - Usage guide with SR auto-discovery, Terraform submission example, common pitfalls

## Decisions Made

- CC Flink SQL templates use auto-discovered tables (no CREATE TABLE with connector/format) -- CC Flink handles schema mapping automatically
- DLQ pattern uses CC-specific error-handling.mode table properties, not Apache Flink side outputs -- CC Flink does not expose the DataStream side output API
- FSI domain examples span corebanking (transactions, analytics), fraud (enrichment), and compliance (screening) to demonstrate breadth

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- SQL templates ready for reference by modules/flink Terraform module (Plan 01)
- DLQ pattern ready for integration with observability dashboards (Plan 03)
- README cross-references modules/flink and observability dashboards

## Self-Check: PASSED

- All 5 created files verified present on disk
- Commit eb20ed6 (Task 1) verified in git log
- Commit a4a9bf3 (Task 2) verified in git log

---
*Phase: 06-flink-on-confluent-cloud*
*Completed: 2026-03-27*

---
phase: 07-onboarding-and-developer-experience
plan: 03
subsystem: testing-and-local-dev
tags: [error-path-tests, docker-compose, flink, flink-sql, kafka-connect, integration-testing, local-dev]

# Dependency graph
requires:
  - phase: 07-onboarding-and-developer-experience
    provides: "Python reference implementations and DLQ handlers (plan 02)"
  - phase: 06-flink-on-confluent-cloud
    provides: "Flink SQL templates and connector patterns"
provides:
  - "Error-path integration test script covering 4 failure scenarios (serialization, RBAC, schema compat, broker failure)"
  - "Docker Compose extended with Flink jobmanager, taskmanager, and SQL client behind --profile flink"
  - "Custom Flink 1.20 Dockerfile with Kafka + Avro-Confluent connector JARs"
  - "Local dev README documenting all services, Flink SQL examples, and troubleshooting"
affects: [07-onboarding-and-developer-experience, local-dev, integration-testing]

# Tech tracking
tech-stack:
  added: [flink-1.20-java17, flink-sql-connector-kafka-3.2.0-1.20, flink-sql-avro-confluent-1.20.0]
  patterns: [docker-compose-profiles, error-path-testing, broker-failure-recovery, acl-rbac-testing]

key-files:
  created:
    - reference/integration-test/error-path-tests.sh
    - reference/local-dev/flink-sql/Dockerfile
  modified:
    - reference/local-dev/docker-compose.yml
    - reference/local-dev/README.md

key-decisions:
  - "Flink connector version 3.2.0-1.20 chosen over 3.4.0-1.20 for Kafka 3.6/7.6 protocol compatibility"
  - "Flink UI mapped to port 8085 (8081 taken by Schema Registry)"
  - "RBAC denial test uses ACL authorizer with ANONYMOUS super user + DENY ACL on separate topic"
  - "Flink services use Docker Compose profiles (--profile flink) so default startup is unchanged"

patterns-established:
  - "Error-path test pattern: numbered [N/M] sections, set +e per test block, record_pass/record_fail, trap cleanup EXIT"
  - "Docker Compose profile pattern: optional services behind named profiles for progressive environment complexity"
  - "Flink local dev: custom Dockerfile downloads connector JARs at build time for reproducibility"

requirements-completed: [ONBOARD-04, ONBOARD-05]

# Metrics
duration: 4min
completed: 2026-03-27
---

# Phase 07 Plan 03: Error-Path Tests & Flink Local Dev Summary

**Shell-based error-path integration tests covering 4 failure scenarios (serialization, RBAC, schema incompat, broker failure) plus Docker Compose extended with Flink 1.20 SQL client behind --profile flink**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-27T14:47:31Z
- **Completed:** 2026-03-27T14:51:30Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- Error-path test script with 4 numbered scenarios: serialization failure (malformed Avro), RBAC denial (ACL-based), schema incompatibility (FULL mode rejection), and broker failure with recovery verification
- Docker Compose extended with Flink jobmanager, taskmanager, and SQL client -- all behind `--profile flink` so default `docker compose up -d` behavior is completely unchanged
- Custom Flink 1.20 Dockerfile that downloads flink-sql-connector-kafka 3.2.0-1.20 and flink-sql-avro-confluent 1.20.0 JARs at build time
- Comprehensive local dev README with services table, quick start, Flink SQL examples, integration test instructions, and troubleshooting

## Task Commits

Each task was committed atomically:

1. **Task 1: Create error-path integration test script** - `a7bce84` (feat)
2. **Task 2: Extend Docker Compose with Flink and add local dev README** - `d117dfa` (feat)

## Files Created/Modified

- `reference/integration-test/error-path-tests.sh` - 4 error-path test scenarios with cleanup, helpers, and PASS/FAIL reporting
- `reference/local-dev/flink-sql/Dockerfile` - Custom Flink 1.20 image with Kafka + Avro-Confluent connector JARs
- `reference/local-dev/docker-compose.yml` - Extended with flink-jobmanager, flink-taskmanager, flink-sql-client services under flink profile
- `reference/local-dev/README.md` - Complete local dev documentation with services, Flink SQL examples, troubleshooting

## Decisions Made

- **Flink connector 3.2.0-1.20 over 3.4.0-1.20:** The 3.2.0 version aligns the embedded Kafka client with our broker version (CP 7.6.0 = Kafka 3.6.x), avoiding protocol negotiation issues that the newer 3.4.0 connector could introduce
- **Port 8085 for Flink UI:** Schema Registry already uses 8081, so Flink JobManager's native UI is remapped to 8085 on the host
- **RBAC test approach:** Uses AclAuthorizer with ANONYMOUS as super user, then adds a DENY ACL on a separate test topic -- avoids breaking the broker for other tests while still validating authorization enforcement
- **Docker Compose profiles:** Flink services are opt-in via `--profile flink`, keeping the default startup lean (broker + SR + Connect only)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None

## User Setup Required

None - no external service configuration required.

## Known Stubs

None - all code is fully wired with real logic. Error-path tests target real Docker Compose services. Flink Dockerfile downloads real Maven Central JARs.

## Next Phase Readiness

- All Phase 7 plans (01, 02, 03) are now complete
- Full integration test suite: roundtrip-test.sh (happy path) + error-path-tests.sh (failure scenarios)
- Local dev environment supports full stream processing development with Flink SQL
- Ready for phase verification via `/gsd:verify-work`

## Self-Check: PASSED

All created files verified on disk. All commit hashes found in git log.

---
*Phase: 07-onboarding-and-developer-experience*
*Completed: 2026-03-27*

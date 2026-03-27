---
phase: 08-cfk-on-openshift
plan: 03
subsystem: infra
tags: [flink, kubernetes-operator, flinkdeployment, avro-confluent, jmx, prometheus, openshift, cfk]

# Dependency graph
requires:
  - phase: 08-01
    provides: CFK scenario directory with Kafka, SR, Connect CRs, topics, ACLs, and observability base
  - phase: 06-flink-runtime
    provides: CC Flink SQL templates (tumbling window, stream-table join, filter-and-route)
  - phase: 05-observability
    provides: JMX exporter stub and dashboard templates for on-prem metrics
provides:
  - Flink Kubernetes Operator 1.14.0 Helm values for CFK scenario
  - FlinkDeployment CRDs porting 3 CC Flink SQL templates to CFK with explicit CREATE TABLE
  - Custom Flink Docker image with avro-confluent and kafka-connector JARs
  - Flink JMX exporter ConfigMap and PodMonitor for observability
  - CFK scenario README with Flink installation, examples, and CC-CFK template mapping
  - .env.example Section 15 with CFK, Flink, and MM2 environment variables
affects: [09-cp-on-rhel]

# Tech tracking
tech-stack:
  added: [flink-kubernetes-operator-1.14.0, flink-1.20, flink-sql-avro-confluent-registry, flink-sql-connector-kafka-3.2.0-1.20]
  patterns: [FlinkDeployment-with-ConfigMap-SQL, podTemplate-volumeMount-for-JMX-exporter, custom-flink-docker-image]

key-files:
  created:
    - scenarios/cfk-openshift/flink/flink-operator-values.yaml
    - scenarios/cfk-openshift/flink/flink-session-cluster.yaml
    - scenarios/cfk-openshift/flink/examples/tumbling-window.yaml
    - scenarios/cfk-openshift/flink/examples/stream-table-join.yaml
    - scenarios/cfk-openshift/flink/examples/filter-and-route.yaml
    - scenarios/cfk-openshift/flink/flink-docker/Dockerfile
    - scenarios/cfk-openshift/observability/jmx-exporter-flink.yaml
    - scenarios/cfk-openshift/observability/pod-monitor-flink.yaml
  modified:
    - scenarios/cfk-openshift/README.md
    - .env.example

key-decisions:
  - "FlinkDeployment CRDs use Application mode with SQL mounted via ConfigMap (not embedded in JAR)"
  - "All FlinkDeployment CRDs include podTemplate volumeMount for flink-jmx-exporter-config (D-11 compliance)"
  - "Custom Flink Docker image uses wget for JAR downloads with air-gapped alternative documented"
  - ".env.example uses Section 15 (not 12 as originally planned) to avoid collision with existing Section 12 Connect"

patterns-established:
  - "FlinkDeployment + ConfigMap SQL: Each Flink job uses a separate ConfigMap for SQL scripts, mounted via podTemplate volumeMount"
  - "JMX exporter sidecar pattern: All FlinkDeployments mount flink-jmx-exporter-config ConfigMap at /opt/jmx-exporter"
  - "CC-to-CFK SQL porting: Replace auto-discovered tables with explicit CREATE TABLE using avro-confluent format connector"

requirements-completed: [IAC-03, FLINK-02]

# Metrics
duration: 4min
completed: 2026-03-27
---

# Phase 08 Plan 03: Flink Operator & FlinkDeployment CRDs Summary

**Flink Kubernetes Operator 1.14.0 with 3 FlinkDeployment examples porting CC Flink SQL templates to CFK via explicit CREATE TABLE with avro-confluent format, custom Docker image with connector JARs, and JMX metrics export for observability**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-27T22:55:23Z
- **Completed:** 2026-03-27T22:59:31Z
- **Tasks:** 2
- **Files modified:** 10

## Accomplishments

- Created Flink Kubernetes Operator Helm values with webhook validation and Prometheus metrics defaults
- Ported all 3 CC Flink SQL templates (tumbling window, stream-table join, filter-and-route) to CFK FlinkDeployment CRDs with explicit CREATE TABLE statements using avro-confluent format connector pointing to CFK Schema Registry
- Built custom Flink Docker image specification with flink-sql-avro-confluent-registry and flink-sql-connector-kafka JARs (resolving Pitfall 7)
- All 4 FlinkDeployment CRDs (session + 3 examples) include podTemplate volumeMount for JMX exporter sidecar config (D-11 compliance)
- Flink JMX exporter ConfigMap exports TaskManager throughput, JobManager health, checkpoint, backpressure, and Kafka connector offset metrics
- README documents complete Flink deployment workflow with CC-to-CFK SQL template mapping table
- Completed the "platform in a box" scenario: Kafka + SR + Connect + MM2 + Flink in a single CFK scenario directory

## Task Commits

Each task was committed atomically:

1. **Task 1: Flink Kubernetes Operator values, FlinkDeployment examples, and custom Dockerfile** - `ee543ab` (feat)
2. **Task 2: Flink JMX observability, README update, and .env.example CFK section** - `6c3ef61` (feat)

## Files Created/Modified

- `scenarios/cfk-openshift/flink/flink-operator-values.yaml` - Helm values for Flink K8s Operator 1.14.0 with webhook and Prometheus defaults
- `scenarios/cfk-openshift/flink/flink-session-cluster.yaml` - FlinkDeployment for interactive SQL session mode
- `scenarios/cfk-openshift/flink/examples/tumbling-window.yaml` - FlinkDeployment + ConfigMap: 1-minute transaction volume aggregation
- `scenarios/cfk-openshift/flink/examples/stream-table-join.yaml` - FlinkDeployment + ConfigMap: temporal join enrichment with account master
- `scenarios/cfk-openshift/flink/examples/filter-and-route.yaml` - FlinkDeployment + ConfigMap: EXECUTE STATEMENT SET for multi-output routing
- `scenarios/cfk-openshift/flink/flink-docker/Dockerfile` - Custom Flink 1.20 image with avro-confluent and kafka-connector JARs
- `scenarios/cfk-openshift/observability/jmx-exporter-flink.yaml` - Flink JMX exporter ConfigMap with 11 metric rules
- `scenarios/cfk-openshift/observability/pod-monitor-flink.yaml` - PodMonitor scraping Flink Prometheus metrics on port 9249
- `scenarios/cfk-openshift/README.md` - Updated with Flink Operator section, Observability section, and expanded Files table
- `.env.example` - Added Section 15: CFK on OpenShift with CFK, Flink, and MM2 environment variables

## Decisions Made

- **FlinkDeployment SQL mounting pattern:** Each example uses a ConfigMap containing the SQL file, mounted via podTemplate volumeMount at `/opt/flink/sql/`. This allows SQL changes without rebuilding the Docker image.
- **D-11 compliance via podTemplate:** All FlinkDeployment CRDs include volumeMount for `flink-jmx-exporter-config` ConfigMap at `/opt/jmx-exporter`, matching the RESEARCH.md Pattern 3.
- **Custom Docker image with wget:** Uses `wget` to download connector JARs from Maven Central, with documented alternative for air-gapped environments using `COPY`.
- **.env.example section numbering:** Used Section 15 instead of Section 12 as originally planned, because Section 12 (Connect) and Section 13 (Terraform Backend) and Section 14 (Flink) already exist. This avoids numbering collisions.
- **Kafka connector version 3.2.0-1.20:** Matches Phase 7 decision for Kafka 3.6/7.6 protocol compatibility.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] .env.example section number adjusted from 12 to 15**
- **Found during:** Task 2 (.env.example update)
- **Issue:** Plan specified "Section 12: CFK on OpenShift" but .env.example already has sections 12 (Connect), 13 (Terraform Backend), and 14 (Flink)
- **Fix:** Used Section 15 instead to avoid collision with existing sections
- **Files modified:** .env.example
- **Verification:** Section 15 header present, no numbering conflicts
- **Committed in:** 6c3ef61 (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Minor section numbering adjustment for correctness. No scope creep.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Phase 08 CFK scenario is complete: all 3 plans delivered (infrastructure, DR/MM2, Flink)
- CFK scenario directory contains 22+ files covering Kafka, SR, Connect, MM2, Flink, topics, ACLs, and observability
- Ready for Phase 09 (Confluent Platform on RHEL) which follows a different deployment model (Ansible/systemd)
- Flink patterns established here (explicit CREATE TABLE, JMX sidecar volumeMount) can be referenced by Phase 09 if Flink is included

## Self-Check: PASSED

- All 10 created/modified files verified present on disk
- Commit ee543ab verified in git log (Task 1)
- Commit 6c3ef61 verified in git log (Task 2)
- SUMMARY.md verified present at .planning/phases/08-cfk-on-openshift/08-03-SUMMARY.md

---
*Phase: 08-cfk-on-openshift*
*Completed: 2026-03-27*

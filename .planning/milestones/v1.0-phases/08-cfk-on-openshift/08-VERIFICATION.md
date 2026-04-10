---
phase: 08-cfk-on-openshift
verified: 2026-03-27T23:10:00Z
status: passed
score: 11/11 must-haves verified
re_verification: false
---

# Phase 08: CFK on OpenShift Verification Report

**Phase Goal:** CFK on OpenShift -- Helm values, KafkaTopic CRDs with governance parity, MM2 DR backend, Flink operator with FlinkDeployment CRDs
**Verified:** 2026-03-27T23:10:00Z
**Status:** PASSED
**Re-verification:** No -- initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | scenarios/cfk-openshift/ directory exists with complete Helm values, topic CRDs, ACL templates, MM2 connectors, and observability configs | VERIFIED | 24 files in directory across values/, topics/, acls/, mm2/, flink/, observability/ subdirs |
| 2 | KafkaTopic CRDs enforce governance parity with CC topics: naming regex, SLA-tier labels, derived partitions/retention | VERIFIED | fsi.sla-tier:critical (12 partitions, 7-day), fsi.sla-tier:compliance (6 partitions, -1 retention) confirmed in topic CRDs |
| 3 | CI c4e-precheck.py validates CFK KafkaTopic YAML files using the same naming and SLA-tier rules as Terraform modules | VERIFIED | `python3 ci/scripts/c4e-precheck.py --scenario-dir scenarios/cfk-openshift/ --verbose` exits 0, 12/12 checks passed |
| 4 | README documents both OLM and Helm installation paths, prerequisites (cert-manager, OpenShift 4.14+), and ACL vs MDS options | VERIFIED | README contains cert-manager, OLM path, Helm path, Quick Start, ACL/MDS sections |
| 5 | fsi-dr.sh failover/failback/status with FSI_DR_BACKEND=mm2 routes to MM2-specific functions | VERIFIED | All 5 mm2_* functions defined and wired in backend dispatch; mm2 case no longer returns error |
| 6 | MM2 backend dry-run mode previews all operations without executing | VERIFIED | DRY_RUN=true branch in mm2_failover_mirrors and mm2_failback_mirrors confirmed in fsi-dr.sh |
| 7 | DR runbook documents MM2-specific failover/failback procedures alongside Cluster Linking | VERIFIED | docs/dr-runbook.md contains "MirrorMaker 2 DR Procedures (CFK/CP)" section at line 479, comparison table, troubleshooting |
| 8 | Flink Kubernetes Operator Helm values exist for CFK scenario deployment | VERIFIED | flink/flink-operator-values.yaml contains "1.14.0" and "flink-kubernetes-operator" |
| 9 | FlinkDeployment CRDs exist for tumbling window, stream-table join, and filter-and-route patterns with avro-confluent format connector pointing to CFK Schema Registry | VERIFIED | All 3 examples contain avro-confluent.url = schemaregistry.confluent.svc.cluster.local:8081, CREATE TABLE statements confirmed |
| 10 | FlinkDeployment CRDs include podTemplate volumeMount for flink-jmx-exporter-config ConfigMap (per D-11) | VERIFIED | All 4 FlinkDeployment CRDs (session cluster + 3 examples) contain volumeMounts and flink-jmx-exporter-config |
| 11 | Custom Flink Docker image includes flink-avro-confluent-registry and flink-sql-connector-kafka JARs | VERIFIED | Dockerfile downloads flink-sql-avro-confluent-registry and flink-sql-connector-kafka-3.2.0-1.20.jar from Maven Central |

**Score:** 11/11 truths verified

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `scenarios/cfk-openshift/README.md` | Quickstart with prerequisites, OLM/Helm install paths, governance | VERIFIED | Contains cert-manager, OLM, Helm, Quick Start, mTLS, ACL, MDS, Flink, Observability sections |
| `scenarios/cfk-openshift/values/kafka.yaml` | Kafka CR with mTLS, ACL authorization, JMX metrics | VERIFIED | type: mtls, authorization.type: simple, auto.create.topics.enable=false, UnderReplicatedPartitions JMX rule |
| `scenarios/cfk-openshift/values/schemaregistry.yaml` | SchemaRegistry CR | VERIFIED | Present, apiVersion platform.confluent.io/v1beta1, replicas: 2 |
| `scenarios/cfk-openshift/values/connect.yaml` | Connect CR for application connectors | VERIFIED | Present, separate from connect-mm2 |
| `scenarios/cfk-openshift/values/connect-mm2.yaml` | Dedicated Connect CR for MM2 | VERIFIED | Present, name: connect-mm2, comment explains D-07 independent lifecycle |
| `scenarios/cfk-openshift/values/kafka-rest-class.yaml` | KafkaRestClass for topic management | VERIFIED | Present |
| `scenarios/cfk-openshift/topics/corebanking-account-txn.yaml` | KafkaTopic CRD with governance labels (critical tier) | VERIFIED | fsi.sla-tier: critical, partitionCount: 12, retention.ms: "604800000" |
| `scenarios/cfk-openshift/topics/fraud-alert-signal.yaml` | KafkaTopic CRD (critical tier) | VERIFIED | fsi.sla-tier: critical confirmed |
| `scenarios/cfk-openshift/topics/compliance-screening-result.yaml` | KafkaTopic CRD (compliance tier) | VERIFIED | fsi.sla-tier: compliance, partitionCount: 6, retention.ms: "-1" |
| `scenarios/cfk-openshift/acls/acl-templates.yaml` | ACL definitions mapping to CC DeveloperWrite/DeveloperRead | VERIFIED | Contains DeveloperWrite, DeveloperRead, kafka-acls CLI examples |
| `scenarios/cfk-openshift/acls/acl-mds-alternative.yaml` | MDS RBAC documentation | VERIFIED | Contains MDS, LDAP prerequisite documentation |
| `scenarios/cfk-openshift/mm2/mm2-source-connector.yaml` | MirrorSourceConnector on connect-mm2 | VERIFIED | MirrorSourceConnector, connect-mm2 reference, east/west aliases; {{EAST_BOOTSTRAP}} is intentional site-specific placeholder per plan spec |
| `scenarios/cfk-openshift/mm2/mm2-checkpoint-connector.yaml` | MirrorCheckpointConnector for offset sync | VERIFIED | MirrorCheckpointConnector, emit.checkpoints.enabled: "true" |
| `scenarios/cfk-openshift/mm2/mm2-heartbeat-connector.yaml` | MirrorHeartbeatConnector for liveness | VERIFIED | MirrorHeartbeatConnector, emit.heartbeats.enabled: "true" |
| `scenarios/cfk-openshift/observability/jmx-exporter-kafka.yaml` | ConfigMap for Kafka JMX exporter rules | VERIFIED | kind: ConfigMap, UnderReplicatedPartitions pattern present |
| `scenarios/cfk-openshift/observability/pod-monitor-kafka.yaml` | PodMonitor for Prometheus scraping | VERIFIED | kind: PodMonitor, targetPort: 7778 |
| `scenarios/cfk-openshift/flink/flink-operator-values.yaml` | Helm values for Flink Kubernetes Operator 1.14.0 | VERIFIED | tag: "1.14.0", flink-kubernetes-operator reference |
| `scenarios/cfk-openshift/flink/flink-session-cluster.yaml` | FlinkDeployment for session mode | VERIFIED | FlinkDeployment, v1_20, PrometheusReporterFactory, flink-jmx-exporter-config volumeMount |
| `scenarios/cfk-openshift/flink/examples/tumbling-window.yaml` | FlinkDeployment with TUMBLE aggregation, avro-confluent | VERIFIED | avro-confluent, CREATE TABLE, TUMBLE, schemaregistry.confluent.svc.cluster.local, flink-jmx-exporter-config |
| `scenarios/cfk-openshift/flink/examples/stream-table-join.yaml` | FlinkDeployment with temporal join enrichment | VERIFIED | avro-confluent, CREATE TABLE, SYSTEM_TIME AS OF, account_master, flink-jmx-exporter-config |
| `scenarios/cfk-openshift/flink/examples/filter-and-route.yaml` | FlinkDeployment with multi-output routing | VERIFIED | avro-confluent, CREATE TABLE, EXECUTE STATEMENT SET, high_value_txn, flink-jmx-exporter-config |
| `scenarios/cfk-openshift/flink/flink-docker/Dockerfile` | Custom Flink image with Avro-Confluent JARs | VERIFIED | FROM flink:1.20, flink-sql-avro-confluent-registry, flink-sql-connector-kafka-3.2.0-1.20 |
| `scenarios/cfk-openshift/observability/jmx-exporter-flink.yaml` | ConfigMap with Flink JMX exporter rules | VERIFIED | kind: ConfigMap, flink_taskmanager metrics, flink-jmx-exporter-config name |
| `scenarios/cfk-openshift/observability/pod-monitor-flink.yaml` | PodMonitor scraping Flink metrics on port 9249 | VERIFIED | kind: PodMonitor, port 9249 confirmed |
| `ci/scripts/c4e-precheck.py` | Extended validator for CFK YAML topic files | VERIFIED | parse_yaml_simple(), parse_cfk_topics(), cfk_modules combination in main(), no "import yaml" |
| `scripts/fsi-dr.sh` | MM2 backend functions wired into dispatch | VERIFIED | All 5 mm2_* functions defined; mm2 case in init_backend routes to all 5 functions; FSI_MM2_CONNECT_URL defaults set |
| `tests/dr/test-fsi-dr-mm2.sh` | MM2 backend unit tests | VERIFIED | Present, FSI_DR_BACKEND="mm2" set, 64 function references across 22 tests |
| `docs/dr-runbook.md` | Extended with MM2 procedures | VERIFIED | MirrorMaker 2 section, FSI_MM2_CONNECT_URL env var, comparison table, MM2 failover command in Quick Reference |
| `.env.example` | Section 15 with CFK, Flink, MM2 variables | VERIFIED | Section 15 "CFK on OpenShift", FSI_MM2_CONNECT_URL, FLINK_OPERATOR_VERSION=1.14.0 present |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `ci/scripts/c4e-precheck.py` | `scenarios/cfk-openshift/topics/*.yaml` | parse_cfk_topics function reads YAML topic files | WIRED | parse_cfk_topics present; runtime verified: 3 topics parsed, 12/12 checks passed |
| `scenarios/cfk-openshift/values/kafka.yaml` | `scenarios/cfk-openshift/acls/acl-templates.yaml` | authorization.type: simple enables ACLs | WIRED | authorization.type: simple in kafka.yaml; acl-templates.yaml documents the corresponding ACL entries |
| `scenarios/cfk-openshift/flink/examples/tumbling-window.yaml` | `scenarios/cfk-openshift/values/schemaregistry.yaml` | avro-confluent.url points to CFK Schema Registry service | WIRED | avro-confluent.url = http://schemaregistry.confluent.svc.cluster.local:8081 confirmed |
| `scenarios/cfk-openshift/flink/flink-docker/Dockerfile` | FlinkDeployment CRDs | Custom image fsi-flink:1.20 used by all FlinkDeployments | WIRED | spec.image: "fsi-flink:1.20" in all FlinkDeployment CRDs; Dockerfile builds that tag |
| `scenarios/cfk-openshift/observability/jmx-exporter-flink.yaml` | `scenarios/cfk-openshift/flink/flink-session-cluster.yaml` | ConfigMap flink-jmx-exporter-config mounted via podTemplate volumeMount | WIRED | ConfigMap name matches volumeMount name in all 4 FlinkDeployment CRDs |
| `scenarios/cfk-openshift/observability/pod-monitor-flink.yaml` | FlinkDeployment CRDs | PodMonitor scrapes Flink Prometheus metrics on port 9249 | WIRED | port 9249 in PodMonitor matches metrics.reporter.prom.port in FlinkDeployment flinkConfiguration |
| `scripts/fsi-dr.sh` (mm2_failover_mirrors) | MM2 Connect REST API | mm2_* functions call curl to Connect REST API | WIRED | curl calls to FSI_MM2_CONNECT_URL/connectors/{name}/pause in mm2_failover_mirrors confirmed |
| `scripts/fsi-dr.sh` (backend dispatch) | Consul KV | init_backend mm2 case wires backend_failover_mirrors to mm2_failover_mirrors | WIRED | mm2 case fully populated, all 5 backend_* functions route to mm2_* counterparts |

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| IAC-03 | 08-01 (also 08-03) | Operator can deploy CFK on OpenShift with Helm/operator manifests (KafkaCluster, SchemaRegistry, Connect, KafkaTopic CRDs) | SATISFIED | scenarios/cfk-openshift/ contains Kafka, SchemaRegistry, Connect CRs and 3 KafkaTopic CRDs with governance labels; README documents install paths |
| DR-05 | 08-02 | MirrorMaker 2 adapter handles CFK/CP failover/failback with topic replication | SATISFIED | All 5 MM2 backend functions implemented in fsi-dr.sh; unit tests pass; DR runbook documents procedures |
| FLINK-02 | 08-03 | CFK Flink deployed via Flink Kubernetes Operator Helm chart on OpenShift | SATISFIED | Helm values for Flink K8s Operator 1.14.0 present; 4 FlinkDeployment CRDs with avro-confluent format; custom Dockerfile; README documents installation |

**Orphaned requirements check (Phase 8 in REQUIREMENTS.md):** No orphaned requirements found. All 3 requirements (IAC-03, DR-05, FLINK-02) are claimed by plans and verified implemented. REQUIREMENTS.md shows all 3 marked [x] (complete).

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `scenarios/cfk-openshift/mm2/mm2-source-connector.yaml` | 32 | `{{EAST_BOOTSTRAP}}` placeholder value | Info | Intentional: per plan spec, this is a site-specific configuration value the operator must replace with their actual east cluster bootstrap endpoint. Not a code stub. |

No blockers or warnings found. The `{{EAST_BOOTSTRAP}}` is a documented configuration placeholder, not an implementation gap.

---

### Human Verification Required

#### 1. MM2 Backend Integration Test (live Connect cluster)

**Test:** Deploy CFK scenario, run `FSI_DR_BACKEND=mm2 fsi-dr.sh failover` against a real MM2 Connect cluster
**Expected:** All 3 MM2 connectors pause, Consul KV flips to DR region, output shows "MM2 connectors paused. DR topics are already writable."
**Why human:** Requires running OpenShift cluster with CFK and MM2 connectors; cannot verify Connect REST API calls without live infra.

#### 2. Flink SQL Execution on OpenShift

**Test:** Build fsi-flink:1.20 Docker image, apply tumbling-window.yaml, submit SQL job, verify records consumed and aggregated
**Expected:** Flink job runs in RUNNING state, aggregated txn-volume-1m records produced to output topic with correct schema via CFK Schema Registry
**Why human:** Requires running Flink Kubernetes Operator and Kafka cluster; cannot verify SQL execution programmatically.

#### 3. KafkaTopic CRD Reconciliation

**Test:** Apply corebanking-account-txn.yaml, verify topic created in Kafka with 12 partitions and 7-day retention; manually change a partition count; verify CFK reverts to 12
**Expected:** CFK operator reconciles topic state back to CRD spec (GitOps enforcement)
**Why human:** Requires running CFK cluster; behavior is runtime, not config-testable.

---

## Commit Verification

All 6 task commits documented in SUMMARYs are present in git log:

| Commit | Plan | Task |
|--------|------|------|
| `4f3c1b6` | 08-01 | CFK scenario directory (16 files) |
| `60f7f89` | 08-01 | c4e-precheck.py CFK extension |
| `e43a8cb` | 08-02 | MM2 backend functions in fsi-dr.sh |
| `1c02fb5` | 08-02 | MM2 tests and DR runbook extension |
| `ee543ab` | 08-03 | Flink operator values, FlinkDeployments, Dockerfile |
| `6c3ef61` | 08-03 | Flink JMX observability, README update, .env.example |

---

## Summary

Phase 08 goal is fully achieved. The CFK on OpenShift scenario delivers:

1. **Complete platform in a box**: 24 files across Kafka, SchemaRegistry, Connect, MM2, Flink, topics, ACLs, and observability subdirectories
2. **Governance parity**: KafkaTopic CRDs with fsi.sla-tier labels enforce the same partition/retention defaults as the CC Terraform module (critical=12 partitions/7-day, compliance=6 partitions/infinite)
3. **CI validation**: c4e-precheck.py extended with stdlib YAML parser; 12/12 governance checks pass against CFK topics with zero new dependencies
4. **MM2 DR backend**: All 5 backend functions (preflight, failover, failback, lag, status) implemented and wired; 22-test unit suite passes; DR runbook documents MM2 procedures and CL vs MM2 comparison
5. **Flink on Kubernetes**: Operator Helm values, 4 FlinkDeployment CRDs (session + 3 SQL patterns) porting CC Flink templates to CFK via explicit CREATE TABLE with avro-confluent format; D-11 JMX volumeMount compliance verified across all 4 CRDs
6. **All 3 requirements satisfied**: IAC-03, DR-05, FLINK-02 each have complete implementation evidence

Three items require human verification with live infrastructure (MM2 failover live execution, Flink SQL execution, KafkaTopic CRD reconciliation behavior).

---

_Verified: 2026-03-27T23:10:00Z_
_Verifier: Claude (gsd-verifier)_

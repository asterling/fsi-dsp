# Layer 05: Flink Stream Processing

Adds governed Apache Flink stream processing to the `confluent-on-linuxone`
accelerator as a self-contained Kustomize Component. Layer 05 is purely additive —
it patches nothing in layers 01-04.

---

## FSI rationale

### Stream-processing governance

Flink consumes from and produces to governed Kafka topics. Without explicit RBAC
scoping, the Flink job runtime has unrestricted cluster access — any topic, any
subject. This layer scopes the job runtime to exactly: read `corebanking.*` source
topics and `corebanking.*` SR subjects, write `flink.output.*` sink topics. SOX §
409 and FFIEC IT Handbook (IS) require that data processing systems enforce least
privilege at the workload level, not just at the human-user level.

### Exactly-once for regulatory reporting

Windowed aggregations (e.g., 1-minute transaction volume) and enrichment outputs
(e.g., enriched-transaction for fraud scoring) are consumed by downstream regulatory
systems (OFAC/AML screening, risk reporting). Duplicate events in these outputs
cause double-counting in regulatory reports. The production overlay patches
`checkpointing.mode: EXACTLY_ONCE` and enables transactional sinks (`TransactionalId`
RBAC grant in `rolebindings/flink-job-runtime.yaml`) to provide exactly-once
end-to-end semantics from Kafka source to Kafka sink.

### Checkpoint state encryption (G-13)

Flink checkpoints serialise in-flight job state to storage. On LinuxONE / OCP,
`state.checkpoints.dir` must point at an encrypted StorageClass (OCP `storageClass`
with `encryption: true`) or an S3-compatible endpoint with SSE-KMS. Unencrypted
checkpoint state is a regulatory finding (PCI-DSS 3.4, GLBA). See KNOWN-GAPS.md G-13
for the cluster-dependent verification item.

---

## CRs in this layer

| Kind | Name | Purpose |
|------|------|---------|
| `FlinkEnvironment` | `fsi-flink-env` | CMF-managed Flink compute environment (defaults: image, RocksDB, s390x affinity) |
| `CMFRestClass` | `fsi-cmf-rest` | mTLS control channel — CFK → CMF REST API |
| `ConfluentRolebinding` | `flink-developer` | LDAP group → FlinkEnvironmentAdmin (submit/cancel jobs) |
| `ConfluentRolebinding` | `flink-job-runtime-source-read` | Service account → DeveloperRead on `corebanking.*` topics |
| `ConfluentRolebinding` | `flink-job-runtime-sink-write` | Service account → DeveloperWrite on `flink.output.*` topics + TransactionalId |
| `ConfluentRolebinding` | `flink-job-runtime-sr-read` | Service account → DeveloperRead on `corebanking.*` SR subjects |
| `Certificate` | `cmf-tls` | cert-manager CR for CMF mTLS cert (signed by `confluent-ca-issuer`) |
| `Certificate` | `flink-kafka-client-tls` | cert-manager CR for Flink → Kafka mTLS client cert |
| `FlinkApplication` | `fsi-txn-volume-tumbling-window` | 1-minute transaction volume tumbling window + SQL ConfigMap |
| `FlinkApplication` | `fsi-account-txn-enrichment` | Account transaction enrichment (temporal join) + SQL ConfigMap |
| `KafkaTopic` | `flink-output-txn-volume-1m` | Sink topic for windowed aggregation output |
| `KafkaTopic` | `flink-output-enriched-transaction` | Sink topic for enriched transaction output |

---

## Self-contained hardening

Layer 05 owns all its hardening CRs. No Flink CRs are added to layers 01-04.

- **mTLS**: `tls/certificate-crs.yaml` creates `cmf-tls` and `flink-kafka-client-tls`
  Certificates. Both reference layer 02's existing `confluent-ca-issuer` ClusterIssuer —
  the same CA that signs broker, SR, and Connect certs. No new PKI infrastructure.
- **RBAC**: `rolebindings/` scopes the Flink developer group and job runtime service
  account to the minimum required access. All bindings use LDAP groups (never individuals).
- **Topic governance**: `topics/kafkatopic-flink-output.yaml` pre-creates Flink sink topics
  with `min.insync.replicas=2`, `retention.ms=$(FLINK_OUTPUT_RETENTION_MS)` (patched per overlay).

---

## Audit by layer 04 (automatic — no layer-04 change needed)

Flink authenticates to Kafka using the `flink-kafka-client-tls` mTLS certificate. The
`ConfluentServerAuthorizer` (enabled by layer 01) fires on every Flink topic access and
emits an authz decision event to `confluent-audit-log-events` (layer 04's topic). Flink
job-lifecycle operations (FlinkApplication submit/cancel) are captured in the OCP audit
log and the GitOps trail (kustomize apply). No change to layers 01-04 is required — the
audit is automatic once the mTLS identity is established.

---

## Dependency order

Layer 05 is appended LAST in `overlays/*/kustomization.yaml components:`:

- **After layer 01**: MDS `ConfluentServerAuthorizer` must be active for the Flink
  `ConfluentRolebinding` CRs to take effect.
- **After layer 02**: `confluent-ca-issuer` ClusterIssuer must exist for `tls/certificate-crs.yaml`
  to be signed. Broker mTLS listener must be configured for Flink's client cert to be accepted.

---

## Per-overlay sizing

| Setting | Production | Development |
|---------|------------|-------------|
| `execution.checkpointing.mode` | `EXACTLY_ONCE` | `AT_LEAST_ONCE` |
| `execution.checkpointing.interval` | 30 000 ms | 60 000 ms |
| `parallelism` | 2 | 1 |
| `retention.ms` (output topics) | 220 752 000 000 ms (7y) | 2 592 000 000 ms (30d) |

Patches are in `overlays/{dev,prod}/kustomization.yaml`.

---

## Observability

- **Prometheus**: Flink TaskManager / JobManager pods expose metrics on port 9249
  (`metrics.reporter.prom.factory.class`). Add a `ServiceMonitor` pointing at port 9249
  to scrape into cluster Prometheus.
- **Grafana**: `observability/grafana/dashboard-flink-jobs.json` provides job-level
  dashboards (checkpoint lag, throughput, backpressure, restarts). Import via the
  Grafana operator or UI.
- **JMX**: Port 9249 also exposes JMX metrics compatible with Dynatrace's JMX extension
  (see `observability/dynatrace/`).

---

## Single-namespace vs multi-namespace

This layer uses the `confluent` namespace (consistent with all other CFK components).
Multi-namespace Flink (separate `flink` namespace for job isolation) is a valid
operational variant — it requires additional `ConfluentRolebinding` cross-namespace
configuration and is not implemented here.

---

## Operator prerequisites

FKO and CMF must be installed before applying this layer (RUNBOOK Step 1b):

```bash
ansible-playbook ansible/playbooks/flink_operators.yml
```

---

## Validation

Run `validate-flink.sh` against a live OCP-on-LinuxONE cluster after applying:

```bash
KAFKA_BOOTSTRAP=kafka.confluent.svc.cluster.local:9092 \
SR_URL=https://schemaregistry.confluent.svc.cluster.local:8081 \
FLINK_CERT=/path/to/flink-client.pem \
FLINK_KEY=/path/to/flink-client-key.pem \
FLINK_CA_CERT=/path/to/ca.pem \
bash layers/05-flink/validate-flink.sh
```

Checks: FlinkEnvironment + CMFRestClass reconciled; both FlinkApplications RUNNING;
Flink→Kafka mTLS handshake; SR Avro-Confluent reachable; output topic KafkaTopic CRs;
RBAC ConfluentRolebinding CRs; Flink Kafka access in `confluent-audit-log-events`.

---

## Known gaps

See KNOWN-GAPS.md:

- **G-10**: FKO + CMF are parallel Helm operators — overlay is not self-sufficient
  without RUNBOOK Step 1b
- **G-11**: CFK 3.2.0+ on s390x supported only for managing Flink Applications
  (layers 01-04 are run-at-your-own-risk)
- **G-12**: Custom s390x SQL-runner image required — see `sql-runner/Dockerfile` +
  `sql-runner/README.md`
- **G-13**: Flink checkpoint state encryption — cluster-dependent verification item

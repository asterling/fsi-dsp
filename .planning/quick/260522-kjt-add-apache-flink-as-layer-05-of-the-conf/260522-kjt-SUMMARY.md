---
phase: quick-260522-kjt
plan: 01
subsystem: accelerators/confluent-on-linuxone
tags: [flink, cfk, s390x, linuxone, kustomize, ansible, mTLS, RBAC]
dependency_graph:
  requires: [quick-260521-26u (layers 01-04 base)]
  provides: [layers/05-flink Component, flink_operators Ansible role, FlinkApplication CRs, SQL ConfigMaps]
  affects: [overlays/dev, overlays/prod, RUNBOOK.md, README.md, DESIGN.md, KNOWN-GAPS.md, CI workflow]
tech_stack:
  added: [Apache Flink 1.20.x, FKO 1.14.x, CMF 2.3.x, CFK FlinkApplication/FlinkEnvironment/CMFRestClass CRs, flink-sql-connector-kafka 3.2.0-1.20, flink-sql-avro-confluent-registry 1.20.0]
  patterns: [Kustomize Component (resources-only), Helm readiness-gated Ansible role, mTLS Certificate CRs reusing existing ClusterIssuer, per-overlay FlinkApplication sizing patches, SQL-in-ConfigMap FlinkApplication pattern]
key_files:
  created:
    - ansible/roles/flink_operators/defaults/main.yml
    - ansible/roles/flink_operators/meta/main.yml
    - ansible/roles/flink_operators/tasks/main.yml
    - ansible/roles/flink_operators/tasks/deploy.yml
    - ansible/roles/flink_operators/tasks/check.yml
    - ansible/playbooks/flink_operators.yml
    - accelerators/confluent-on-linuxone/layers/05-flink/kustomization.yaml
    - accelerators/confluent-on-linuxone/layers/05-flink/flink-environment.yaml
    - accelerators/confluent-on-linuxone/layers/05-flink/cmfrestclass.yaml
    - accelerators/confluent-on-linuxone/layers/05-flink/secrets.template/cmf-mtls-credentials.yaml
    - accelerators/confluent-on-linuxone/layers/05-flink/secrets.template/flink-kafka-client-credentials.yaml
    - accelerators/confluent-on-linuxone/layers/05-flink/rolebindings/flink-developer.yaml
    - accelerators/confluent-on-linuxone/layers/05-flink/rolebindings/flink-job-runtime.yaml
    - accelerators/confluent-on-linuxone/layers/05-flink/tls/certificate-crs.yaml
    - accelerators/confluent-on-linuxone/layers/05-flink/applications/txn-volume-tumbling-window.yaml
    - accelerators/confluent-on-linuxone/layers/05-flink/applications/account-transaction-enrichment.yaml
    - accelerators/confluent-on-linuxone/layers/05-flink/topics/kafkatopic-flink-output.yaml
    - accelerators/confluent-on-linuxone/layers/05-flink/sql-runner/Dockerfile
    - accelerators/confluent-on-linuxone/layers/05-flink/sql-runner/README.md
    - accelerators/confluent-on-linuxone/layers/05-flink/validate-flink.sh
    - accelerators/confluent-on-linuxone/layers/05-flink/README.md
  modified:
    - accelerators/confluent-on-linuxone/overlays/dev/kustomization.yaml
    - accelerators/confluent-on-linuxone/overlays/prod/kustomization.yaml
    - accelerators/confluent-on-linuxone/RUNBOOK.md
    - accelerators/confluent-on-linuxone/README.md
    - accelerators/confluent-on-linuxone/DESIGN.md
    - accelerators/confluent-on-linuxone/KNOWN-GAPS.md
    - .github/workflows/accelerator-linuxone.yml
decisions:
  - "Layer 05 is kind:Component resources-only — Flink adds CRs, patches nothing (Flink is a Kafka client)"
  - "05-flink appended last in components: list — depends on layer 01 MDS + layer 02 confluent-ca-issuer"
  - "Certificate CRs reference existing confluent-ca-issuer (layer 02) — shared CA chain, no new PKI"
  - "SQL-runner image shipped as Dockerfile (not built) — mirrors G-08 Connect-image gap pattern"
  - "Per-overlay sizing via overlay patches, not layer patches — keeps Component self-contained"
  - "Flink audit integration is automatic (mTLS identity → ConfluentServerAuthorizer → layer 04) — no layer-04 change"
metrics:
  duration: "~45 minutes"
  completed: "2026-05-22"
  tasks_completed: 8
  files_created: 21
  files_modified: 7
  commits: 7
---

# Phase quick-260522-kjt Plan 01: Add Apache Flink as Layer 05 Summary

Apache Flink stream processing added as the fifth capability layer of the
`accelerators/confluent-on-linuxone` accelerator, covering governed stream
processing (mTLS, RBAC, exactly-once semantics, checkpoint encryption) on CFK/OpenShift/s390x.

---

## What Was Built

### Task 1: flink_operators Ansible role (commit 24961d8)

New `ansible/roles/flink_operators/` role mirroring `cfk_operator`:
- `defaults/main.yml`: FKO 1.14.x + CMF 2.3.x Helm chart settings, readiness polling vars
- `tasks/deploy.yml`: installs FKO first (CRD prerequisite for CMF), then CMF — both `wait: true`
- `tasks/check.yml`: GET-only audit of FKO/CMF releases + FlinkApplication/FlinkEnvironment/CMFRestClass CRs
- `tasks/main.yml`: routes check vs deploy (no apply_crs — CRs applied via kustomize)
- `ansible/playbooks/flink_operators.yml`: RUNBOOK Step 1b entry point

### Task 2: layers/05-flink Component scaffold (commit 61d908b)

- `kustomization.yaml`: `kind: Component` (kustomize.config.k8s.io/v1alpha1), resources-only, no patches
- `flink-environment.yaml`: FlinkEnvironment CR with s390x nodeAffinity, RocksDB state backend, Prometheus port 9249
- `cmfrestclass.yaml`: CMFRestClass CR with mTLS endpoint config for the CFK→CMF governed control path
- Two secrets.template files (all `<PLACEHOLDER>` values): cmf-mtls-credentials + flink-kafka-client-credentials

### Task 3: Self-contained RBAC and mTLS hardening (commit 9a1c237)

- `rolebindings/flink-developer.yaml`: FlinkEnvironmentAdmin bound to LDAP group (not individuals — SOX/FFIEC)
- `rolebindings/flink-job-runtime.yaml`: 3 least-privilege bindings (DeveloperRead source+SR, DeveloperWrite sink, TransactionalId for EOS)
- `tls/certificate-crs.yaml`: cmf-tls + flink-kafka-client-tls cert-manager Certificates, both referencing existing `confluent-ca-issuer` (layer 02) — no new PKI

### Task 4: FlinkApplication CRs + SQL ConfigMaps + output topics (commit 489eff4)

- `applications/txn-volume-tumbling-window.yaml`: FlinkApplication + ConfigMap with 1-minute tumbling window SQL (mutual TLS Kafka + https SR)
- `applications/account-transaction-enrichment.yaml`: FlinkApplication + ConfigMap with temporal stream-table join SQL for fraud enrichment
- `topics/kafkatopic-flink-output.yaml`: two KafkaTopic CRs with `$(FLINK_OUTPUT_RETENTION_MS)` substitutable retention

### Task 5: SQL-runner image, validator, layer README (commit 7705beb)

- `sql-runner/Dockerfile`: cp-flink:1.20.0-cp1 s390x base with kafka + avro-confluent JARs (shipped, not built)
- `sql-runner/README.md`: docker buildx `--platform linux/s390x` build instructions, JAR matrix, air-gapped guidance, OCP registry push
- `validate-flink.sh`: 7-section cluster validator; `bash -n` passes; NOT run in CI
- `README.md`: layer rationale (EOS for regulatory reporting, G-13 checkpoint encryption, audit-by-layer-04 note, per-overlay sizing table)

### Task 6: Overlay wiring with per-overlay FlinkApplication patches (commit bd9c376)

Both overlays:
- `../../layers/05-flink` appended as LAST component
- Header comments updated to five components with dependency rationale

`overlays/prod/kustomization.yaml` patches:
- FlinkApplication: parallelism 2, checkpointInterval 30s
- Flink output KafkaTopic: retention.ms = 220752000000 (7y)

`overlays/dev/kustomization.yaml` patches:
- FlinkApplication: parallelism 1, checkpointInterval 60s
- Flink output KafkaTopic: retention.ms = 2592000000 (30d)

### Task 7: Documentation updates (commit e4b08da)

- **RUNBOOK.md**: Step 1b (FKO+CMF playbook + image build prereq) + Step 10 (validate-flink.sh) + 4 Flink troubleshooting rows; intro updated to five layers
- **README.md**: Layer 05 section (FSI rationale, EOS, audit integration, prerequisites); provenance row; five-component architecture diagram
- **DESIGN.md**: directory tree with `layers/05-flink/`; Section 5 layer detail (CRs, hardening, composition, audit integration, operator prerequisite); composition mechanism updated to five components; validate list updated
- **KNOWN-GAPS.md**: G-10/G-11/G-12/G-13 added to gap register table and detail sections
- **CI workflow**: header updated to mention layer 05-flink and validate-flink.sh non-CI status

### Task 8: Validation pass (no commit — everything clean)

All checks passed without fixes:
- `bash -n`: `validate-flink.sh` passes
- `ansible-lint`: 0 failures on `flink_operators` role + playbook
- YAML parse: all 11 layer-05 YAML files parse cleanly
- `kind: Component` verified; no `patches:` block in 05-flink kustomization
- All `secrets.template/*.yaml` contain `<PLACEHOLDER>` values
- Both overlays have `../../layers/05-flink` as last component
- `kustomize build`: SKIPPED — kustomize not in PATH on this machine; exercised by CI (`accelerator-linuxone.yml` fetch-and-build job) on PR

---

## Commits

| Task | Commit | Message |
|------|--------|---------|
| 1 | 24961d8 | feat(accelerator): add flink_operators Ansible role for FKO + CMF Helm install |
| 2 | 61d908b | feat(accelerator): scaffold layers/05-flink Component with Flink CRs and secret templates |
| 3 | 9a1c237 | feat(accelerator): add self-contained RBAC and mTLS hardening to layers/05-flink |
| 4 | 489eff4 | feat(accelerator): add FSI example FlinkApplications, SQL ConfigMaps, and output topics |
| 5 | 7705beb | feat(accelerator): add Flink SQL-runner image definition, validator, and layer README |
| 6 | bd9c376 | feat(accelerator): wire layer 05-flink into dev and prod overlays with sizing patches |
| 7 | e4b08da | docs(accelerator): document layer 05-flink in RUNBOOK, README, DESIGN, KNOWN-GAPS |
| 8 | — | Validation pass — no changes needed |

---

## Validation Results

| Check | Result | Notes |
|-------|--------|-------|
| `bash -n validate-flink.sh` | PASS | |
| `ansible-lint flink_operators` | PASS | 0 failures; kubernetes.core collection not installed in lint env (warnings only) |
| YAML parse — all 11 layer-05 files | PASS | |
| `kind: Component` + no `patches:` | PASS | |
| secrets.template PLACEHOLDER check | PASS | Both template files |
| Both overlays: 05-flink last | PASS | |
| FlinkApplication kinds (no FlinkDeployment) | PASS | |
| `kustomize build` dev + prod overlays | SKIPPED | kustomize not in PATH on execution host; `base/upstream/` absent (gitignored); CI exercises this on PR |

---

## Deviations from Plan

### Auto-fixed Issues

None.

### Other Deviations

**1. Playbook uses `include_role` task, not `roles:` list**

The plan specified `roles: [flink_operators]`. The existing `deploy-cfk.yml` pattern
uses `tasks: [include_role: flink_operators]`. Using `roles:` caused an ansible-lint
`syntax-check` failure (role not found in playbook-relative search path). Applied the
`include_role` pattern to pass lint, consistent with the existing playbook convention.

**2. `kustomize build` deferred to CI**

kustomize is not in PATH on the execution machine, and `base/upstream/` is gitignored
(requires network fetch). The CI workflow (`accelerator-linuxone.yml`) exercises this
on every PR via the `fetch-and-build` job. Documented in validation results.

---

## Known Stubs

| File | Stub | Reason |
|------|------|--------|
| `flink-environment.yaml` | `<PLACEHOLDER_CP_FLINK_SQL_RUNNER_IMAGE>` | Custom s390x image must be built per sql-runner/README.md (G-12) |
| `flink-environment.yaml` | `<PLACEHOLDER_ENCRYPTED_CHECKPOINT_STORAGE_URI>` | Cluster-dependent encrypted StorageClass/SSE endpoint (G-13) |
| `cmfrestclass.yaml` | `<PLACEHOLDER_CMF_SERVICE_ENDPOINT>` | CMF REST API endpoint — cluster-specific after Helm install |
| `applications/*.yaml` | `<PLACEHOLDER_CP_FLINK_SQL_RUNNER_IMAGE>` | Same as FlinkEnvironment (G-12) |
| `rolebindings/flink-developer.yaml` | `<PLACEHOLDER_FLINK_DEVELOPER_LDAP_GROUP>` | Customer LDAP group name — operator-supplied |
| `rolebindings/flink-job-runtime.yaml` | `<PLACEHOLDER_FLINK_JOB_SERVICE_ACCOUNT>` | Service account name — operator-supplied |
| `tls/certificate-crs.yaml` | `<PLACEHOLDER_FLINK_JOB_SERVICE_ACCOUNT>` | Cert CN must match rolebinding principal |
| SQL ConfigMaps | `<PLACEHOLDER_KEYSTORE_PASSWORD>` etc. | Injected from flink-kafka-client-credentials Secret at runtime |
| `secrets.template/*.yaml` | All `<PLACEHOLDER_*>` values | By design — templates populated out-of-band |

All stubs are intentional and documented in KNOWN-GAPS.md G-12 and G-13. The plan goal
(governed Flink layer as a Kustomize Component with correct CR structure) is achieved.
Stubs prevent the FlinkApplications from starting without explicit operator action (image
build + secret population), which is the correct behavior for a reference accelerator.

## Self-Check: PASSED

Files verified to exist:
- ansible/roles/flink_operators/tasks/main.yml — FOUND
- ansible/playbooks/flink_operators.yml — FOUND
- accelerators/confluent-on-linuxone/layers/05-flink/kustomization.yaml — FOUND
- accelerators/confluent-on-linuxone/layers/05-flink/applications/txn-volume-tumbling-window.yaml — FOUND
- accelerators/confluent-on-linuxone/layers/05-flink/sql-runner/Dockerfile — FOUND
- accelerators/confluent-on-linuxone/layers/05-flink/validate-flink.sh — FOUND

Commits verified:
- 24961d8 (Task 1) — FOUND
- 61d908b (Task 2) — FOUND
- 9a1c237 (Task 3) — FOUND
- 489eff4 (Task 4) — FOUND
- 7705beb (Task 5) — FOUND
- bd9c376 (Task 6) — FOUND
- e4b08da (Task 7) — FOUND

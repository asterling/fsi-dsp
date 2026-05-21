# Roadmap: FSI Kafka Platform

## Milestones

- ✅ **v1.0 Foundation** - Terraform modules, schemas, reference implementations (shipped)
- ✅ **v2.0 Automation** - Ansible layer, DR backends, observability, CFK/CP governance (shipped 2026-04-10)
- 🚧 **v3.0 LinuxONE** - s390x first-class deployment + FSI-hardened accelerator (in progress)

## Phases

<details>
<summary>✅ v1.0 Foundation — SHIPPED</summary>

### Phase 1-9: Foundation
**Goal**: Golden-path Terraform topic module, Avro schema governance, Java/Python/.NET
reference implementations, observability baseline, DR shell CLI.
**Plans**: Complete

</details>

<details>
<summary>✅ v2.0 Automation — SHIPPED 2026-04-10</summary>

### Phase 10-15: Ansible Automation & Governance
**Goal**: Ansible automation layer (10 roles), DR backends (CL/MM2/MRC), observability
templates for 6 providers, CFK operator + topic governance, MDS RBAC.
**Plans**: Complete — 42/42 requirements, milestone audit passed.

</details>

### 🚧 v3.0 LinuxONE (In Progress)

**Milestone Goal:** LinuxONE / s390x as a first-class deployment model, plus an
FSI-hardened Confluent-on-LinuxONE accelerator forked from IBM's public reference.

#### Phase 16: LinuxONE / s390x Integration
**Goal**: s390x deployment scenarios (cp-rhel-linuxone, cfk-openshift-linuxone),
ADR-009, cp_mtls role, FIPS / CEX guidance.
**Depends on**: Phase 15
**Success Criteria** (what must be TRUE):
  1. CP and CFK can be deployed on LinuxONE s390x
  2. mTLS provisioning works on s390x with software keystores
  3. s390x-specific guidance is documented (ADR-009, linuxone-*.md)
**Plans**: Complete

#### Phase 17: FSI-Hardened Confluent-on-LinuxONE Accelerator
**Goal**: A new `accelerators/confluent-on-linuxone/` directory forking Mondics's
reference runbook with four FSI hardening layers (RBAC, mTLS, Schema Registry
governance, audit logging) composed as Kustomize Components.
**Depends on**: Phase 16
**Success Criteria** (what must be TRUE):
  1. A developer can flox activate, follow the runbook, and deploy hardened CP on LinuxONE
  2. Each of the 4 hardening layers has a passing validation procedure
  3. README distinguishes IBM upstream from GoodLabs additions and attributes Mondics
  4. KNOWN-GAPS.md and MIGRATION.md are complete
**Plans**: Tracked as quick task (see STATE.md Quick Tasks Completed)

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1-9. Foundation | v1.0 | Complete | Complete | shipped |
| 10-15. Automation | v2.0 | Complete | Complete | 2026-04-10 |
| 16. LinuxONE Integration | v3.0 | Complete | Complete | 2026-04-27 |
| 17. FSI Accelerator | v3.0 | 0/1 | In progress | - |

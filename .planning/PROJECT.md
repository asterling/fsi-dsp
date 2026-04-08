# FSI Kafka Platform

## What This Is

A universal, automation-first platform for standing up governed Kafka, Flink, and Schema Registry infrastructure across any deployment model — Confluent Cloud (AWS, Azure, GCP), Confluent Private Cloud, Confluent for Kubernetes on OpenShift, and Confluent Platform on RHEL. It packages FSI-specific C4E assets (Terraform modules, Ansible roles, reference implementations, observability templates, DR automation, schema governance) into scenario-based starter kits that any financial institution can adopt in hours, not months. Teams choose their automation tool: Terraform for Confluent Cloud, Ansible for Confluent Platform and CFK deployments.

## Current Milestone: v2.0 Ansible Based Automation

**Goal:** Add Ansible-native automation for Confluent Platform deployments — topic governance, schema management, RBAC, observability, and DR — in an `ansible/` directory alongside existing Terraform content, leaning heavily on Confluent's certified cp-ansible collection.

**Target features:**
- CP governance roles (topic lifecycle, schema registration, RBAC via MDS) as reusable Ansible roles
- End-to-end deployment pipeline: deploy CP cluster → configure topics → register schemas → set RBAC → deploy observability
- DR automation playbooks for CP (MM2 + MRC backends) with state validation and dry-run
- CFK on OpenShift deployment via kubernetes.core.helm with governance parity
- CI/CD for Ansible content (ansible-lint, molecule tests, GitHub Actions)
- Observability deployment roles (JMX exporters, Prometheus configs, dashboard imports)

## Core Value

Any FSI team can stand up a fully governed, observable, DR-ready Kafka/Flink/SR cluster in their deployment model of choice with a single automation run — and onboard their first topic in under a day.

## Requirements

### Validated

<!-- Shipped and confirmed valuable. -->

**v1.0 — Terraform + Shell Foundation (Phases 1-9):**
- ✓ Topic creation Terraform module with naming validation, SLA-tier defaults, RBAC, DR mirror — v1.0
- ✓ Schema registration with Avro, compatibility enforcement, namespace validation — v1.0
- ✓ CC multi-cloud scenarios (AWS, Azure, GCP) with native backends — v1.0 Phase 2
- ✓ CFK on OpenShift with Helm/operator manifests, MM2 DR — v1.0 Phase 8
- ✓ CP on RHEL with cp-ansible deployment, standalone Flink — v1.0 Phase 9
- ✓ Confluent Private Cloud scenario with Terraform — v1.0 Phase 9
- ✓ Pluggable DR framework (Cluster Linking, MM2, MRC backends) with dry-run and rollback — v1.0 Phase 4
- ✓ Observability templates for 6 providers with SLA-tier alerting — v1.0 Phase 5
- ✓ Flink on CC (compute pool module, SQL templates, SR integration) — v1.0 Phase 6
- ✓ Flink on CFK (Kubernetes Operator) and CP-RHEL (standalone) — v1.0 Phases 8-9
- ✓ Access control: SA provisioning, OAuth, Vault credential rotation, CSFLE — v1.0 Phase 3
- ✓ Compliance: 7-year retention, audit trails, FIPS 140-2 — v1.0 Phases 3, 9
- ✓ Onboarding: intake form, C4E CI automation, Python reference client, DLQ patterns — v1.0 Phase 7
- ✓ Reference implementations: Java, .NET, Python producers/consumers — v1.0
- ✓ 8 ADRs, schema guide, DR runbook, compliance guide — v1.0
- ✓ CI/CD: plan-on-PR, apply-on-merge, schema validation, override detection — v1.0
- ✓ Local dev Docker Compose (Kafka + SR + Connect + Flink) — v1.0

### Active

<!-- Current scope: v2.0 Ansible Based Automation -->

**Ansible Governance Roles:**
- [ ] Topic lifecycle management (create, configure, validate) with SLA-tier logic via Ansible roles
- [ ] Schema validation and registration via SR REST API as Ansible role
- [ ] RBAC provisioning via MDS REST API as Ansible role
- [ ] Service account management for CP deployments via Ansible

**Ansible Deployment Pipeline:**
- [ ] End-to-end CP deployment playbook: cp-ansible cluster deploy → topic governance → schema registration → RBAC → observability
- [ ] CFK on OpenShift deployment via kubernetes.core.helm with Ansible governance roles
- [ ] Observability deployment roles (JMX exporter config, Prometheus scrape rules, per-provider dashboard import)
- [ ] Connect configuration and connector deployment via Ansible

**Ansible DR Automation:**
- [ ] Failover/failback playbooks for CP (MM2 backend) with state validation
- [ ] MRC failover/failback playbooks (observer promotion) via Ansible
- [ ] Dry-run mode and rollback capability in Ansible DR playbooks
- [ ] DR drill automation playbook (failover → validate → failback → report)

**Ansible CI/CD:**
- [ ] ansible-lint and molecule test framework for all roles
- [ ] GitHub Actions workflows for Ansible content (lint, test, deploy)
- [ ] Integration tests for Ansible roles (topic creation, schema registration, RBAC verification)

### Out of Scope

<!-- Explicit boundaries. -->

- Flink business logic (fraud scoring, compliance windowing) — runtime only, teams build their own jobs
- Mobile or web UI — CLI and IaC only
- Confluent Cloud account/org provisioning — assumes org and environment exist
- Client-specific customizations — generic FSI patterns only, teams extend
- Real-time chat/collaboration features — use existing Teams/Slack
- Data mesh or catalog integration — future milestone
- Ansible for Confluent Cloud — no native Ansible provider; CC stays Terraform-only
- Apache Kafka (non-Confluent) support — roles target CP with MDS/Confluent CLI only

## Context

This platform generalizes a proven FSI C4E engagement into reusable starter assets. v1.0 delivered complete Terraform-based automation for all 4 deployment models with 9 phases of governance, DR, observability, and onboarding. The gap now: FSI shops that are Red Hat/Ansible-first have no native automation path. The existing `scenarios/cp-rhel/` uses cp-ansible for basic cluster deployment but lacks governance automation (topic lifecycle, schema management, RBAC). v2.0 adds an `ansible/` directory with roles and playbooks that mirror the Terraform module's governance logic for CP and CFK deployments.

The C4E philosophy (from the engagement): **Automation > Documentation. Golden Path > Gatekeeping. Community > Committee.** Every asset should make it easier to do the right thing than the wrong thing.

**Deployment models to support:**
1. **Confluent Cloud** — fully managed on AWS, Azure, or GCP
2. **Confluent Private Cloud** — Confluent-managed in customer VPC
3. **Confluent for Kubernetes (CFK)** — operator-based on OpenShift
4. **Confluent Platform on RHEL** — traditional systemd/Ansible deployment

**Key architectural decisions:**
- Scenario directories over CLI scaffolding — teams pick their path
- Per-provider observability templates over abstraction layer
- DR framework with pluggable backends (Cluster Linking, MM2, MRC)
- MRC with 2.5-cluster observer promotion for RPO=0 scenarios

**Existing codebase map:** `.planning/codebase/` (7 documents, mapped 2026-03-21)

## Constraints

- **Deployment parity**: Core governance (topic naming, schema compat, RBAC) must work identically across all deployment models
- **No vendor lock-in on observability**: Templates per provider, no single-provider dependency
- **FSI compliance**: Retention policies must support regulatory requirements (up to 7-year for OFAC/AML)
- **Backward compatibility**: Existing Confluent Cloud Terraform modules must continue to work — extend, don't break
- **OpenShift compatibility**: CFK scenario must target OCP 4.x with operator lifecycle management
- **cp-ansible alignment**: Ansible roles must integrate with Confluent's certified cp-ansible collection (v8.2.0+), not replace it
- **Governance parity**: Ansible roles must enforce identical governance rules (naming, SLA tiers, schema compat, RBAC) as existing Terraform modules

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Scenario directories over CLI | Lower barrier to entry, teams browse and pick | ✓ Good — Phase 2 delivered 3 scenarios |
| Per-provider observability templates | Simpler to maintain, each FSI has one provider | ✓ Good — Phase 5 delivered 6 providers |
| Flink runtime only (no business logic) | Teams own their jobs, we provide the platform | ✓ Good — Phase 6 delivered CC Flink module + 3 SQL templates |
| DR framework with pluggable backends | Same CLI/UX regardless of deployment model | ✓ Good — Phase 4 CL + Phase 8 MM2 |
| MRC 2.5-cluster for RPO=0 | FSI compliance may require zero data loss | ✓ Good — Phase 9 MRC backend |
| Avro over Protobuf (existing ADR-001) | FSI ecosystem alignment, SR compatibility | ✓ Good |
| Consul for service discovery (existing ADR-003) | Atomic failover across Kafka/SR/DB | ✓ Good |
| Cluster Linking over MRC for CC (existing ADR-005) | CC-native, meets ~2h RPO target | ✓ Good |
| Same repo for Ansible (v2.0) | Shared governance artifacts, schemas, ADRs, validation scripts | — Pending |
| CC stays Terraform-only (v2.0) | No native Ansible provider for CC; Terraform is the right tool | — Pending |
| Confluent Platform only for Ansible (v2.0) | Lean on cp-ansible + MDS + Confluent CLI; no vanilla Apache Kafka | — Pending |
| ansible/ directory structure (v2.0) | Parallel to scenarios/; reusable roles + deployment playbooks | ✓ Good — Phase 10 scaffolded ansible/ with inventories, filter_plugins, governance YAML |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd:transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd:complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-04-08 after Phase 10 complete — Ansible foundation scaffolded with pinned dependencies, governance constants mirroring Terraform, filter plugins, multi-environment inventories, and ansible-lint config.*

# FSI Kafka Platform

## What This Is

A universal, automation-first accelerator repo for standing up governed Kafka, Flink,
and Schema Registry infrastructure across any deployment model — Confluent Cloud (AWS,
Azure, GCP), Confluent Private Cloud, Confluent for Kubernetes (CFK) on OpenShift, and
Confluent Platform on RHEL, including LinuxONE / s390x. It packages FSI-specific C4E
assets (Terraform modules, Ansible roles, reference implementations, observability
templates, DR automation, schema governance) into scenario-based starter kits.

## Core Value

Any FSI team can stand up a fully governed, observable, DR-ready Kafka/Flink/SR cluster
in their deployment model of choice with a single automation run.

## Requirements

### Validated

<!-- Shipped and confirmed valuable. -->

- ✓ Golden-path Terraform topic module (topic + schema + RBAC + DR mirror + tags) — v1.0
- ✓ Ansible automation layer — 10 roles, all deployment models — v2.0
- ✓ DR backends (Cluster Linking, MirrorMaker 2, Multi-Region Clusters) + unified CLI — v2.0
- ✓ Observability templates for 6 providers — v2.0
- ✓ CFK / CP governance roles (cfk_operator, cfk_topic, cp_rbac, cp_mtls) — v2.0
- ✓ LinuxONE / s390x first-class deployment scenarios + ADR-009 — v3.0

### Active

<!-- Current scope. Building toward these. -->

- [ ] FSI-hardened Confluent-on-LinuxONE accelerator (fork of IBM/Mondics reference,
      layered RBAC / mTLS / Schema Registry governance / audit logging)

### Out of Scope

<!-- Explicit boundaries. -->

- Non-OpenShift Kubernetes distributions — accelerator targets RHOCP 4.14+ on LinuxONE only
- Parallel (non-CFK) management of Confluent components — CFK operator is the single control path
- Redistribution of unlicensed upstream code — upstream runbook is fetch-by-SHA, never vendored

## Context

- Brownfield repo at v3.0; v1.0 and v2.0 shipped. `.planning/` artifacts were archived
  after the v2.0 milestone; these files were re-bootstrapped to support quick-task tracking.
- IBM's Matt Mondics published a public reference runbook for Confluent Platform on
  LinuxONE via CFK on OpenShift with Cluster Linking (repo `mmondics/Confluent-LinuxONE-Mirror`,
  article 2026-05-20). It is a generic demo: no RBAC, no audit logging, self-signed TLS.
- The accelerator work forks that base and adds FSI hardening as Kustomize Components.

## Constraints

- **Compatibility**: s390x — every image, chart, and tool must run on s390x; gaps flagged in KNOWN-GAPS.md
- **Platform**: RHOCP 4.14+ on LinuxONE; CFK-operator-managed only
- **Tech stack**: Confluent Platform 8.2.0, CFK 3.2.x, KRaft mode, Kustomize, Helm 3.x
- **Compliance**: FSI — retention up to 7 years (OFAC/AML); no secrets committed (use `<PLACEHOLDER>`)
- **Backward compatibility**: existing Terraform/Ansible/CFK assets must keep working — extend, don't break

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Accelerator base = fetch-by-SHA | Upstream repo has no LICENSE — no redistribution right | — Pending |
| auditor-readonly = audit-topic-scoped | Confluent DeveloperRead always grants consume; isolates payloads | — Pending |
| Reuse existing repo assets | Avoid duplicating cfk_operator / cp_rbac / cp_mtls / observability | — Pending |

---
*Last updated: 2026-05-21 after re-bootstrapping .planning/ for accelerator quick task*

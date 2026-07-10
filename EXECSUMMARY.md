# FSI Data Streaming Platform — Executive Summary

**FSI Data Streaming Platform** is a turnkey infrastructure kit that lets any financial institution stand up a fully governed, observable, DR-ready Kafka/Flink/Schema Registry environment across eight deployment models — with a single automation run.

## What it solves

FSI teams typically spend months wiring up Kafka with the governance, security, DR, and observability layers that regulators require. This platform compresses that to hours by packaging all of it as pre-built, parameterized automation.

## Deployment models

| Model | Tooling | Use case |
|-------|---------|----------|
| Confluent Cloud (AWS/Azure/GCP) | Terraform | Managed cloud, multi-region |
| Confluent for Kubernetes | Helm + Ansible | OpenShift / container-native |
| Confluent Platform on RHEL | Ansible (cp-ansible) | Bare metal / on-prem |
| Confluent Private Cloud | Terraform | Self-managed control plane |

All eight share identical governance rules — topic naming, schema compatibility, RBAC, SLA-tier defaults — enforced by shared modules and filter plugins regardless of deployment model.

## Key capabilities

- **Governance-as-code** — A single topic declaration produces the topic, Avro schema, RBAC bindings, metadata tags, and DR mirror automatically. SLA tiers (critical/standard/best-effort/compliance) drive all config defaults.
- **DR automation** — Three backends (Cluster Linking, MirrorMaker 2, Multi-Region Cluster) behind one CLI and Ansible playbooks. Includes dry-run, state validation, Consul-based atomic failover, and quarterly DR drill automation that produces OCC/FDIC compliance reports.
- **Observability out of the box** — Dashboard templates for all six major providers (Dynatrace, Datadog, Splunk, Grafana, New Relic, Instana) with SLA-tier alert thresholds and auto-discovery.
- **Flink streaming** — Terraform-managed compute pools (CC), Kubernetes Operator (CFK), and standalone Ansible roles (CP) with reference SQL templates for common FSI patterns.
- **Security & compliance** — mTLS, MDS RBAC, CSFLE field-level encryption, FIPS 140-2 validation, credential rotation via Vault/cloud KMS, and configurable retention up to 7 years for OFAC/AML.
- **CI/CD pipeline** — Automated C4E pre-check validates naming, schemas, RBAC, and SLA tiers across all three config formats (Terraform, CFK YAML, CPTopic YAML) before human review.

## By the numbers

- 8 deployment scenarios with governance parity
- 17 Ansible roles + 6-play orchestration pipeline
- 3 DR backends with 103 shell tests + 662 Ansible tests
- 6 observability providers with dashboard templates
- 3 reference client languages (Java, Python, .NET) with DLQ patterns
- 12 ADRs documenting key architectural decisions

## Bottom line

A team picks their deployment model, fills in a tfvars or inventory file, runs one command, and gets a production-grade Kafka environment that already meets FSI regulatory requirements — topic governance, schema evolution controls, RBAC, encryption, DR, observability, and audit trails included.

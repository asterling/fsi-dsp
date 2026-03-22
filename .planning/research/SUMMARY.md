# Research Summary: FSI Multi-Deployment Kafka/Flink C4E Platform

**Domain:** FSI event streaming platform (Kafka, Flink, Schema Registry) with multi-deployment model support
**Researched:** 2026-03-21
**Overall confidence:** MEDIUM

## Executive Summary

The FSI Kafka/Flink C4E platform is extending from a proven Confluent Cloud-only deployment (Azure, single topic module, manual DR) to a multi-deployment platform spanning CC on AWS/Azure/GCP, CFK on OpenShift, and Confluent Platform on RHEL. The feature landscape divides cleanly into table stakes (what FSI teams will not adopt without) and differentiators (what justifies C4E investment over teams rolling their own).

Table stakes are dominated by three themes: (1) governance parity across deployment models -- topic naming, schema compatibility, and RBAC must behave identically whether the target is CC, CFK, or CP; (2) operational maturity -- automated DR failover, observability templates, and consumer lag monitoring are non-negotiable for production FSI workloads; and (3) compliance readiness -- audit trails, retention policies, PII tagging, and FIPS compliance for federal FSI.

The primary differentiator is cross-deployment parity itself. Most C4E platforms are single-deployment. A unified topic specification that renders to Terraform (CC), CRDs (CFK), or Ansible (CP) with identical governance guarantees is rare and valuable. Flink integration is a secondary differentiator -- providing stream processing runtime and templates accelerates teams that would otherwise spend months building Flink infrastructure.

The existing codebase provides a strong foundation. The topic module's design (SLA-tier-driven defaults, schema metadata, RBAC bindings, DR mirror creation) is the right pattern. The gap is breadth (one cloud, one deployment model) and operational maturity (manual DR, no CI validation, no observability templates). The 14 documented concerns in CONCERNS.md are real and must be addressed -- they represent the delta between "demo-ready" and "production-ready."

## Key Findings

**Stack:** Confluent ecosystem (CC, CFK, CP) with Terraform, Helm/CFK operator, and Ansible as IaC per deployment model. Flink for stream processing. Per-provider observability templates (Dynatrace, Datadog, Grafana, Splunk, New Relic, Instana).

**Architecture:** Scenario directory pattern with shared module library. Pluggable DR framework with backend adapters. Unified topic specification that renders to deployment-model-specific IaC.

**Critical pitfall:** Governance drift between deployment models. If CC, CFK, and CP scenarios have independent governance logic, the platform delivers 3 separate platforms, not one. The shared module library is the architectural linchpin.

## Implications for Roadmap

Based on research, suggested phase structure:

1. **Foundation: Multi-Cloud CC + Governance Hardening** -- Add CC-AWS and CC-GCP scenarios, shared module library, schema CI validation, compliance retention tier
   - Addresses: Multi-cloud IaC, schema governance gaps, compliance retention
   - Avoids: Governance drift pitfall (shared module library first)

2. **Operational Maturity: DR Automation + Observability** -- Automated DR failover CLI, mirror lag monitoring, Dynatrace + Grafana dashboard templates, consumer lag alerting
   - Addresses: Manual DR risk (#1 concern), observability gaps, alert configuration
   - Avoids: Deploying multi-cloud without operational readiness

3. **Stream Processing: Flink Integration** -- CC Flink compute pool deployment, Flink SQL reference templates, Flink observability, Flink-SR Avro integration
   - Addresses: Flink as strategic differentiator, stream processing enablement
   - Avoids: Flink before core platform is stable

4. **On-Prem: CFK on OpenShift** -- CFK operator manifests, topic CRD generation from shared spec, CFK-specific DR (MM2), CFK observability (JMX exporter)
   - Addresses: On-prem FSI requirement, Kubernetes-native deployment
   - Avoids: Attempting all deployment models simultaneously

5. **Legacy: CP on RHEL** -- Ansible roles, systemd deployment, MDS RBAC, FIPS 140-2 compliance, MRC RPO=0 (if required)
   - Addresses: Air-gapped/legacy FSI environments
   - Avoids: Lowest-ROI scenario absorbing early phase capacity

**Phase ordering rationale:**
- CC multi-cloud first because existing module is CC-native and extensions are lower risk
- DR automation before new deployment models because it addresses the #1 operational concern
- Flink before CFK because CC Flink is managed (lower operational surface) and proves the integration pattern
- CFK before CP because Kubernetes-native is the industry direction; bare metal is legacy
- Each phase has clear exit criteria (governance parity tests, DR drill success, Flink job template validation)

**Research flags for phases:**
- Phase 1: Unlikely to need deeper research (well-understood Confluent Terraform patterns)
- Phase 2: Needs investigation into Confluent Cloud Metrics API current capabilities and per-provider dashboard template formats
- Phase 3: Needs investigation into CC Flink Terraform resources (evolving rapidly) and Flink Kubernetes Operator maturity
- Phase 4: Needs investigation into CFK operator CRD schema for topic/schema/RBAC management and OLM integration
- Phase 5: Needs investigation into cp-ansible current state, FIPS 140-2 requirements, MRC 2.5-cluster configuration

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | MEDIUM | Confluent ecosystem is well-known from training data; specific version capabilities (Terraform provider 2.x, CFK operator) may have evolved |
| Features | MEDIUM-HIGH | Feature categories are stable across FSI; specific feature availability (e.g., CC Flink GA features, Stream Governance pricing) should be verified |
| Architecture | MEDIUM | Scenario directory + shared module is sound; cross-deployment spec rendering is novel and needs validation |
| Pitfalls | HIGH | Governance drift, manual DR risk, and compliance gaps are well-documented in existing CONCERNS.md and are universal FSI patterns |

## Gaps to Address

- CC Flink Terraform resource availability and GA status should be verified with current Confluent docs
- CFK operator CRD schema for topic management needs investigation (topic CRDs vs. Terraform against CP)
- Observability provider API formats for dashboard templates need per-provider investigation
- cp-ansible current version and FIPS 140-2 compatibility need verification
- Confluent Stream Governance (data contracts) pricing and licensing model affects feasibility
- MRC 2.5-cluster configuration details and observer promotion behavior need Confluent engineering validation

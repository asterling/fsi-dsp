# Technology Stack

**Project:** FSI Multi-Deployment Kafka/Flink Platform
**Researched:** 2026-03-21
**Overall Confidence:** MEDIUM (web verification tools unavailable; versions based on training data through early 2025 plus release cadence extrapolation. All version numbers should be verified against official sources before adoption.)

## Version Verification Caveat

WebSearch, WebFetch, and Bash tools were unavailable during this research session. All version numbers below are based on:
- **Codebase facts** (what is currently pinned in the repo) -- HIGH confidence
- **Training data** (knowledge cutoff ~May 2025) -- MEDIUM confidence
- **Release cadence extrapolation** (projected from known release patterns) -- LOW confidence

**Before starting implementation, verify every version number against its official source.** I flag each recommendation with its confidence level.

---

## Recommended Stack

### Infrastructure as Code -- Core

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| Terraform | >= 1.7.0 | IaC engine for all deployment models | Already in codebase. 1.7+ gives `terraform test` blocks for post-apply validation (addresses CONCERNS.md). Use 1.7+ not 1.9+ to avoid OpenTofu licensing confusion and stay on stable ground. | HIGH (codebase-verified) |
| Confluent Terraform Provider | ~> 2.11 | CC resource management (topics, schemas, RBAC, Flink, cluster linking) | Already using `~> 2.0`. Pin to 2.11+ because Flink compute pool and Flink statement resources were added in the 2.x line (2.4+). The provider follows semver; `~> 2.11` ensures Flink support while avoiding breaking 3.x changes. Verify exact latest at registry.terraform.io. | MEDIUM (version extrapolated from 2.x release cadence) |
| Terraform Kubernetes Provider | ~> 2.35 | CFK and Flink operator deployment on OpenShift | Required for CFK scenario. Manages namespaces, secrets, ConfigMaps that CFK operator consumes. Pin `~> 2.35` to get recent OCP compatibility fixes. | MEDIUM |
| Terraform Helm Provider | ~> 2.17 | Helm chart deployment for CFK operator and Flink operator | CFK and Flink operators are distributed as Helm charts. This is the standard Terraform mechanism to deploy them. | MEDIUM |
| Terraform AWS Provider | ~> 5.80 | AWS networking (PrivateLink, VPC endpoints) for CC on AWS scenario | Only used in the AWS scenario directory. Manages VPC endpoints for Confluent Cloud PrivateLink. | MEDIUM |
| Terraform Azure Provider (azurerm) | ~> 4.14 | Azure networking (Private Endpoint) for CC on Azure scenario | Already implicit in the codebase (backend uses azurerm). Pin to 4.x for current Azure API compatibility. | MEDIUM |
| Terraform GCP Provider | ~> 6.14 | GCP networking (Private Service Connect) for CC on GCP scenario | Only used in the GCP scenario directory. | MEDIUM |

### Infrastructure as Code -- Configuration Management

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| Ansible | >= 2.17 (ansible-core) | Confluent Platform on RHEL deployment | CP on RHEL requires systemd service management, config file templating, rolling upgrades. Ansible is the industry standard for this and Confluent publishes an official Ansible collection. Terraform is wrong for config management on bare metal. | HIGH (pattern confidence) |
| Confluent Ansible Collection (cp-ansible) | >= 7.7.x | Automated CP installation on RHEL | `confluent.platform` Ansible Galaxy collection. Handles broker, SR, Connect, REST Proxy, ksqlDB, Control Center installation with TLS, RBAC, mTLS. This is Confluent's officially supported deployment method for CP on RHEL/bare-metal. | MEDIUM (version extrapolated) |

### Confluent Platform and Kafka

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| Confluent Platform | 7.7.x | Base platform version for CP-on-RHEL and CFK scenarios | 7.6.0 is in the current codebase. 7.7.x is the next LTS-style release (CP releases track ~2x/year). Use 7.7 for MRC observer promotion support and Flink SQL improvements. Verify at docs.confluent.io/platform/current. | LOW (extrapolated) |
| Confluent Cloud | Current (managed) | Fully managed Kafka for CC scenarios (AWS/Azure/GCP) | Already in use. CC is always-current; no version pinning needed. Flink on CC is GA. | HIGH |
| Apache Kafka (bundled with CP) | 3.7.x or 3.8.x | Broker engine | Bundled with CP. Do not independently version Kafka when using CP or CC. | HIGH (pattern) |
| Confluent Schema Registry | Matches CP version | Schema management | Bundled. Always matches CP version. | HIGH |
| Apache Kafka Clients | Match CP version | Producer/consumer SDK | Must match CP version for full compatibility. Currently 3.7.0 in pom.xml; upgrade when CP upgrades. | HIGH |

### Confluent for Kubernetes (CFK) on OpenShift

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| CFK Operator | >= 2.9.x | Operator-based Kafka deployment on OpenShift | CFK is the only supported method for running Confluent on Kubernetes. 2.8.x was current as of early 2025; 2.9.x likely current. CFK uses CRDs (`KafkaCluster`, `SchemaRegistry`, `Connect`, `KsqlDB`). Verify at docs.confluent.io/operator/current. | LOW (version extrapolated) |
| Red Hat OpenShift | 4.14+ | Kubernetes platform | CFK supports OCP 4.12+. Target 4.14+ for Extended Update Support (EUS) lifecycle. OCP 4.16 is likely current but 4.14 gives longer support runway for FSI change management cadence. | MEDIUM |
| OLM (Operator Lifecycle Manager) | Bundled with OCP | CFK operator installation and lifecycle | OLM manages CFK operator upgrades on OpenShift. CFK is available via OperatorHub. Use OLM over raw Helm for OpenShift to get audit trail and approval workflows that FSI compliance requires. | HIGH (pattern) |

### Flink Runtime

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| Confluent Cloud Flink | Managed (no version pin) | Stream processing for CC scenarios | GA on Confluent Cloud. Flink SQL workspaces, compute pools managed via Terraform provider (`confluent_flink_compute_pool`, `confluent_flink_statement`). This is the path of least resistance for CC deployments. | HIGH |
| Apache Flink | 1.20.x | Stream processing for CFK and CP scenarios | For self-managed Flink. 1.19 was current in late 2024; 1.20 expected by mid-2025. Use Confluent's Flink distribution if available (bundles Confluent connectors and Avro serde). | LOW (version extrapolated) |
| Flink Kubernetes Operator | 1.10.x | Flink on OpenShift for CFK scenario | Apache project. Manages Flink `FlinkDeployment` CRDs on Kubernetes. 1.8.0 was released mid-2024; ~1.10.x likely current. Verify at flink.apache.org/downloads. Alternative: Confluent bundles Flink operator in CFK 2.9+ -- verify this before deploying a separate operator. | LOW (version extrapolated) |
| Flink SQL | Matches Flink version | Declarative stream processing | Use Flink SQL (not DataStream API) for reference job templates. SQL is the right abstraction for FSI teams who are not Java/Scala developers. Flink SQL supports Avro format natively with Schema Registry integration. | HIGH (pattern) |

### Observability -- Per-Provider Templates

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| Confluent Cloud Metrics API | v2 | Metrics export from CC clusters | Primary data source for all CC observability. Exposes cluster, topic, partition, consumer group, and cluster link metrics. All provider dashboards consume from this API (or its OpenMetrics/Prometheus endpoint). | HIGH |
| Prometheus + Grafana | Prometheus 2.54+, Grafana 11.x | Open-source observability for CP/CFK scenarios | JMX Exporter on CP brokers -> Prometheus -> Grafana. Standard pattern for self-managed Kafka. Also serves as the reference dashboard that other provider templates are adapted from. | MEDIUM |
| JMX Exporter | 1.0.1+ | Expose Kafka/Connect/Flink JMX metrics as Prometheus format | Required for CP-on-RHEL and CFK scenarios. Runs as a Java agent on broker/connect/SR JVMs. Confluent publishes a reference JMX exporter config. | MEDIUM |
| Dynatrace OneAgent | Current | APM and infrastructure monitoring | FSI's existing provider (referenced in codebase). Dynatrace ingests JMX via OneAgent, CC metrics via Dynatrace API integration. Dashboard templates use Dynatrace DQL. | HIGH (codebase-verified) |
| Datadog Agent | 7.x | Alternative APM provider | Datadog has a native Confluent Cloud integration and Kafka check for self-managed. Dashboard templates use Datadog JSON dashboard format. | MEDIUM |
| Splunk | HEC (HTTP Event Collector) | Log and metrics aggregation | Common in FSI. Kafka metrics via Splunk Connect for Kafka or JMX-to-HEC bridge. Dashboard templates use Splunk SPL. | MEDIUM |
| New Relic | Current | Alternative APM provider | New Relic has Confluent Cloud and Kafka on-host integrations. Dashboard templates use NRQL. | MEDIUM |
| IBM Instana | Current | APM provider common in IBM-heavy FSI shops | Instana auto-discovers Kafka via agent sensors. Less common but listed in PROJECT.md requirements. | LOW |

### DR Framework

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| Confluent Cluster Linking | CC-native | Async DR for Confluent Cloud scenarios | Already in codebase. Bidirectional link, mirror topics, scripted failover. Extend with automated orchestration CLI. | HIGH (codebase-verified) |
| MirrorMaker 2 (MM2) | Matches CP version | Async DR for CP-on-RHEL and CFK scenarios | MM2 is the standard cross-cluster replication for self-managed Kafka. Runs as a Connect connector. Supports topic, consumer group, and ACL mirroring. | HIGH (pattern) |
| MRC (Multi-Region Clusters) | CP 7.7+ | RPO=0 DR for CP scenarios with observer promotion | The 2.5-cluster pattern (2 sync replicas + observer) provides automatic failover with zero data loss. Only available on Confluent Platform, not CC. Requires careful network design (low-latency links between sync replicas). | MEDIUM |
| HashiCorp Consul | 1.19+ | Service discovery for DR endpoint failover | Already in codebase (ADR-003). KV-based region flip for atomic endpoint resolution. | HIGH (codebase-verified) |

### Secrets and Authentication

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| HashiCorp Vault | 1.17+ | Credential management, rotation, dynamic secrets | Already referenced in codebase. Use Vault's Kafka secrets engine for dynamic credential generation. Supports zero-downtime rotation via dual-credential windows. | MEDIUM |
| OAUTHBEARER authentication | Kafka 3.x+ | Token-based auth replacing static API keys | Use for Azure (Entra ID), AWS (IAM), GCP (Workload Identity). Eliminates credential rotation burden. Already noted in cloud-providers.md for Azure. | HIGH (pattern) |

### Reference Implementation Libraries

| Library | Version | Purpose | When to Use | Confidence |
|---------|---------|---------|-------------|------------|
| `org.apache.kafka:kafka-clients` | Match CP (currently 3.7.0) | Java Kafka producer/consumer | All Java reference implementations | HIGH |
| `io.confluent:kafka-avro-serializer` | Match CP (currently 7.6.0) | Avro serde with Schema Registry | All Avro-producing Java apps | HIGH |
| `org.apache.avro:avro` | 1.11.3 (current in codebase) | Avro schema support | All reference apps. Upgrade to 1.12.x when CP bundles it. | HIGH |
| `Confluent.Kafka` (.NET) | 2.6.x | .NET Kafka client | .NET reference implementations | MEDIUM |
| `Confluent.SchemaRegistry` (.NET) | 2.6.x | .NET Schema Registry client | .NET reference implementations | MEDIUM |
| `io.confluent:kafka-connect-jdbc` | 10.7.x (current in codebase) | JDBC source/sink connector | Connect-based database integration | HIGH |
| SLF4J | 2.0.12 (current in codebase) | Java logging facade | All Java reference apps | HIGH |
| `org.apache.flink:flink-connector-kafka` | Match Flink version | Flink Kafka connector | Flink SQL jobs consuming/producing Kafka | MEDIUM |
| `org.apache.flink:flink-avro-confluent-registry` | Match Flink version | Flink Avro serde with Schema Registry | Flink SQL jobs using Avro format with SR | MEDIUM |

### CI/CD and Tooling

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| GitHub Actions | N/A (managed) | CI/CD pipeline | Already in codebase. Extend existing plan/apply workflows with scenario-specific matrices. | HIGH |
| Confluent CLI | 4.x | Operational commands (topic list, mirror promote, cluster link status) | Used in DR scripts. Pin major version 4.x. The CLI is essential for DR orchestration script and post-apply validation. | MEDIUM |
| `tflint` | >= 0.53 | Terraform linting | Add to CI for HCL quality. Catches deprecated resources, naming violations. | MEDIUM |
| `terraform-docs` | >= 0.19 | Auto-generate module documentation | Generates input/output docs from variables.tf/outputs.tf. Reduces doc drift. | MEDIUM |
| `checkov` or `tfsec` | Current | Terraform security scanning | FSI compliance requires security scanning of IaC. Checkov preferred (broader coverage, Confluent resource support). | MEDIUM |
| Python | 3.11+ | Schema validation scripts, DR CLI tooling | Already used for schema validation in CI. Extend for the pluggable DR framework CLI. Python over Bash for anything beyond trivial scripting -- structured error handling, JSON parsing, testability. | HIGH (pattern) |
| Click (Python) | 8.x | CLI framework for DR orchestration tool | Build the "single command failover" CLI with Click. It handles subcommands, --dry-run flags, confirmation prompts, colored output. Better than argparse for multi-command CLIs. | MEDIUM |

---

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| IaC Engine | Terraform | OpenTofu | Licensing uncertainty resolved (BSL is fine for internal FSI use). OpenTofu ecosystem is smaller. Confluent officially supports their TF provider on HashiCorp Terraform. |
| IaC Engine | Terraform + Ansible | Pulumi | Existing team competency is HCL. Pulumi requires code-first approach that doesn't match the "scenario directory" model. |
| Config Management (RHEL) | Ansible | Chef/Puppet | Confluent publishes `cp-ansible` officially. No Chef or Puppet equivalent. Ansible is agentless (less footprint in FSI data centers). |
| K8s Kafka Operator | CFK Operator | Strimzi | CFK is Confluent's official operator with commercial support. Strimzi is community-driven Apache Kafka only (no Schema Registry, Connect, Flink, RBAC). FSI needs vendor support contracts. |
| Stream Processing | Flink SQL | ksqlDB | Flink is Confluent's strategic direction (ksqlDB end-of-life announced). Confluent Cloud Flink is GA. ksqlDB will not receive new features. This is not optional -- ksqlDB must be avoided for new work. |
| Stream Processing | Flink SQL | Flink DataStream API | SQL is the right abstraction for FSI teams. DataStream API is for custom operators that SQL cannot express. Reference templates should be SQL-first with DataStream escape hatch documented. |
| Schema Format | Avro | Protobuf | ADR-001 decision. Avro has better Flink SQL integration, SR compatibility enforcement, and FSI ecosystem alignment. |
| DR Replication (CC) | Cluster Linking | MirrorMaker 2 on CC | Cluster Linking is CC-native, zero operational burden, sub-second lag. MM2 on CC requires self-managed Connect cluster. |
| DR Replication (CP) | MirrorMaker 2 | Cluster Linking | Cluster Linking on self-managed CP requires Enterprise license and is less mature than MM2. MM2 is the proven pattern for CP. |
| Observability Abstraction | Per-provider templates | OpenTelemetry Collector | PROJECT.md explicitly chose per-provider templates over abstraction. Each FSI has one provider; maintaining one template per provider is simpler than maintaining an OTel pipeline that feeds all. Reconsider if a single FSI needs 3+ providers simultaneously. |
| Service Discovery | Consul | Kubernetes-native (CoreDNS) | Consul works across all deployment models (CC, CP, CFK, bare metal). K8s-native service discovery only works for CFK. Consul is already chosen (ADR-003) and provides atomic multi-endpoint failover. |
| DR CLI | Python + Click | Go CLI | Python is already in the codebase for validation scripts. The DR CLI doesn't need Go-level performance. Click provides excellent UX with minimal code. |
| DR CLI | Python + Click | Bash scripts (current) | Current bash scripts have no error handling, state tracking, or rollback (CONCERNS.md). Python provides structured error handling, JSON state files, testability. |

---

## Stack by Deployment Scenario

Each scenario directory uses a subset of the full stack:

### Scenario: Confluent Cloud on AWS

```
Terraform providers: confluent (~> 2.11), aws (~> 5.80)
Modules: topic (shared), networking-aws, flink-cc
Observability: CC Metrics API -> provider template
DR: Cluster Linking (built into topic module)
Auth: OAUTHBEARER via AWS IAM (preferred) or API keys
State backend: S3
```

### Scenario: Confluent Cloud on Azure

```
Terraform providers: confluent (~> 2.11), azurerm (~> 4.14)
Modules: topic (shared), networking-azure, flink-cc
Observability: CC Metrics API -> provider template
DR: Cluster Linking (built into topic module)
Auth: OAUTHBEARER via Entra ID (preferred) or API keys
State backend: Azure Blob Storage
```

### Scenario: Confluent Cloud on GCP

```
Terraform providers: confluent (~> 2.11), google (~> 6.14)
Modules: topic (shared), networking-gcp, flink-cc
Observability: CC Metrics API -> provider template
DR: Cluster Linking (built into topic module)
Auth: OAUTHBEARER via Workload Identity Federation or API keys
State backend: GCS
```

### Scenario: CFK on OpenShift

```
Terraform providers: kubernetes (~> 2.35), helm (~> 2.17)
CFK Operator: ~> 2.9.x (via OLM or Helm)
Flink Operator: Apache Flink K8s Operator ~> 1.10.x
CRDs: KafkaCluster, SchemaRegistry, Connect, KsqlDB, FlinkDeployment
Observability: JMX Exporter -> Prometheus -> Grafana + provider template
DR: MirrorMaker 2 (as Connect connector in CFK)
Auth: mTLS + RBAC (CFK manages certificates)
```

### Scenario: CP on RHEL

```
Ansible: confluent.platform collection >= 7.7.x
Terraform: Optional (for provisioning VMs on cloud, not for CP config)
Flink: Standalone Flink cluster (systemd managed via Ansible)
Observability: JMX Exporter -> Prometheus -> Grafana + provider template
DR: MirrorMaker 2 or MRC (2.5-cluster pattern for RPO=0)
Auth: Kerberos/LDAP + RBAC (CP Enterprise)
```

### Scenario: Confluent Private Cloud

```
Terraform providers: confluent (~> 2.11) -- Private Cloud uses same TF provider
Modules: Same as CC scenarios but with private networking pre-provisioned
Observability: CC Metrics API (Private Cloud exposes same API)
DR: Cluster Linking (same as CC)
Auth: Same as CC (OAUTHBEARER or API keys)
Note: Private Cloud is CC-in-your-VPC. Treat identically to CC for IaC purposes.
```

---

## Shared Module Library

These Terraform modules are consumed by ALL scenarios:

| Module | Purpose | Scenario Compatibility |
|--------|---------|----------------------|
| `modules/topic` | Topic + Schema + RBAC + metadata (existing) | CC (all clouds), Private Cloud |
| `modules/topic-cp` | Topic + Schema + RBAC for self-managed CP | CFK, CP-on-RHEL |
| `modules/schema` | Schema-only registration (for cross-cluster schemas) | All |
| `modules/flink-pool` | Flink compute pool provisioning | CC (all clouds) |
| `modules/flink-statement` | Flink SQL statement deployment | CC (all clouds) |
| `modules/observability` | Metrics export and alert rule configuration | All (provider-specific submodules) |
| `modules/dr-cluster-link` | Cluster Linking setup and monitoring | CC (all clouds), Private Cloud |
| `modules/dr-mm2` | MirrorMaker 2 connector configuration | CFK, CP-on-RHEL |
| `modules/networking-aws` | AWS PrivateLink for CC | CC on AWS |
| `modules/networking-azure` | Azure Private Endpoint for CC | CC on Azure |
| `modules/networking-gcp` | GCP Private Service Connect for CC | CC on GCP |

---

## Installation

### Terraform Providers (root module)

```hcl
terraform {
  required_version = ">= 1.7.0"
  required_providers {
    confluent = {
      source  = "confluentinc/confluent"
      version = "~> 2.11"
    }
    # Include per-scenario:
    # aws      = { source = "hashicorp/aws";        version = "~> 5.80" }
    # azurerm  = { source = "hashicorp/azurerm";     version = "~> 4.14" }
    # google   = { source = "hashicorp/google";      version = "~> 6.14" }
    # kubernetes = { source = "hashicorp/kubernetes"; version = "~> 2.35" }
    # helm     = { source = "hashicorp/helm";        version = "~> 2.17" }
  }
}
```

### Ansible (CP on RHEL)

```bash
# Install Confluent Ansible collection
ansible-galaxy collection install confluent.platform:>=7.7.0

# Verify
ansible-galaxy collection list | grep confluent
```

### Java Reference Libraries (pom.xml)

```xml
<properties>
    <java.version>17</java.version>
    <confluent.version>7.7.0</confluent.version>
    <kafka.version>3.7.0</kafka.version>
    <avro.version>1.11.3</avro.version>
    <flink.version>1.20.0</flink.version>
    <slf4j.version>2.0.12</slf4j.version>
</properties>
```

### Python DR CLI

```bash
pip install click>=8.0 requests>=2.32 pyyaml>=6.0 rich>=13.0
```

### Docker Compose (local dev -- upgrade from 7.6.0)

```yaml
# Update all images to match target CP version
image: confluentinc/cp-kafka:7.7.0
image: confluentinc/cp-schema-registry:7.7.0
image: confluentinc/cp-kafka-connect:7.7.0
```

---

## Version Upgrade Path from Current Codebase

The codebase currently pins CP 7.6.0 and Confluent provider `~> 2.0`. Here is the upgrade sequence:

| Component | Current | Target | Breaking Changes | Priority |
|-----------|---------|--------|------------------|----------|
| Confluent TF Provider | ~> 2.0 | ~> 2.11 | None (semver minor) | Phase 1 -- needed for Flink resources |
| Confluent Platform images | 7.6.0 | 7.7.x | Check release notes. CP follows semver within major. | Phase 1 -- needed for Flink + MRC |
| Kafka Clients (Java) | 3.7.0 | Match new CP | Binary compatible within 3.x | Phase 1 -- follow CP upgrade |
| Avro | 1.11.3 | 1.11.3 (keep) | No change needed. Upgrade to 1.12.x only with CP. | N/A |
| Terraform | >= 1.5 | >= 1.7.0 | None. Already compatible. | Phase 1 |
| Docker Compose images | 7.6.0 | 7.7.x | Match CP version | Phase 1 |

---

## What NOT to Use

| Technology | Why Not |
|------------|---------|
| ksqlDB | End-of-life. Confluent is migrating to Flink. Do not create new ksqlDB deployments. Existing ksqlDB should be migrated to Flink SQL. |
| Strimzi Operator | No commercial support, no Schema Registry/Connect/Flink lifecycle management. CFK is the right choice for Confluent on K8s. |
| Kafka Streams (for new platform jobs) | Flink SQL is the strategic direction. Kafka Streams is fine for existing apps but new reference templates should use Flink SQL. |
| Terraform for CP configuration | Terraform is wrong for systemd service management on bare metal. Use Ansible. Terraform can provision the VMs but Ansible configures CP. |
| Custom Helm charts for Kafka | CFK operator is the supported deployment method. Custom charts become unmaintainable and miss CFK's rolling upgrade, certificate, and RBAC automation. |
| AWS MSK | This is a Confluent Platform project. MSK is a different product with different APIs, no Schema Registry, no Cluster Linking, no RBAC model. |
| OpenTelemetry Collector (as primary) | Per PROJECT.md decision: per-provider templates, not abstraction layer. OTel adds complexity without value when each FSI has a single provider. |
| Terraform Cloud/Enterprise | Not required. GitHub Actions with remote state backends (S3/Blob/GCS) provides equivalent CI/CD. TFC/TFE adds cost without material benefit for this use case. |

---

## Sources

- **Codebase analysis:** `environments/prod/main.tf`, `modules/topic/main.tf`, `reference/local-dev/docker-compose.yml`, `reference/java-producer/pom.xml` -- HIGH confidence
- **ADR decisions:** `docs/adr/001-005` -- HIGH confidence (project decisions, not research)
- **Confluent documentation patterns:** Training data through May 2025 -- MEDIUM confidence
- **Terraform provider versions:** Extrapolated from known 2.x release cadence -- LOW confidence, verify at https://registry.terraform.io/providers/confluentinc/confluent
- **CFK operator versions:** Extrapolated from known release cadence -- LOW confidence, verify at https://docs.confluent.io/operator/current
- **Flink operator versions:** Extrapolated from known release cadence -- LOW confidence, verify at https://flink.apache.org/downloads
- **Confluent Platform versions:** Extrapolated from ~2 releases/year cadence -- LOW confidence, verify at https://docs.confluent.io/platform/current
- **cp-ansible collection:** Training data awareness of `confluent.platform` collection -- MEDIUM confidence, verify at https://galaxy.ansible.com/ui/repo/published/confluent/platform

---

## Verification Checklist (Pre-Implementation)

Before adopting this stack, verify these specific items:

- [ ] Confluent Terraform Provider: actual latest 2.x version at registry.terraform.io
- [ ] Confluent Platform: actual latest version at docs.confluent.io (is it 7.7.x or 7.8.x?)
- [ ] CFK Operator: actual latest version and supported OCP versions
- [ ] Flink Kubernetes Operator: actual latest version
- [ ] Whether CFK 2.9+ bundles Flink operator (may eliminate need for separate Apache Flink operator)
- [ ] cp-ansible collection: actual latest version and supported CP versions
- [ ] Confluent Cloud Flink: current GA status and supported SQL features (window functions, joins, Avro serde)
- [ ] MRC observer promotion: confirm available in target CP version
- [ ] Confluent provider Flink resources: confirm `confluent_flink_compute_pool` and `confluent_flink_statement` exist in target provider version

---

*Stack research: 2026-03-21*

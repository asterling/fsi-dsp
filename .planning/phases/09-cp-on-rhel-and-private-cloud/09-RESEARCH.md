# Phase 9: CP on RHEL and Private Cloud - Research

**Researched:** 2026-03-27
**Domain:** Confluent Platform on RHEL (Ansible), Private Cloud (Terraform), MRC RPO=0, standalone Flink, FIPS 140-2
**Confidence:** MEDIUM

## Summary

Phase 9 is the final v1 milestone phase, adding two new deployment models (CP on RHEL via Ansible, Private Cloud via Terraform) plus three cross-cutting capabilities (MRC for RPO=0, standalone Flink, FIPS compliance). This is the most complex phase in the roadmap -- it spans five distinct technical domains that must integrate with every governance, DR, and observability pattern established in Phases 1-8.

The CP on RHEL scenario uses Confluent's official `cp-ansible` playbooks (Ansible roles for `kafka_broker`, `schema_registry`, `kafka_connect`, plus MDS for RBAC) with systemd service management. The Private Cloud scenario reuses the existing `confluentinc/confluent` Terraform provider -- the provider supports managing self-managed CP clusters when pointed at the cluster's Kafka REST endpoint, allowing the shared governance modules from Phase 1 to work with minimal adaptation. MRC with automatic observer promotion (2.5-cluster pattern) provides RPO=0 for critical/compliance-tier topics on CP and requires a new `mrc` backend in `fsi-dr.sh`. Standalone Flink uses Apache Flink's standalone deployment mode (JobManager + TaskManagers as processes) with systemd unit files -- Confluent Platform for Apache Flink requires Kubernetes, so the RHEL scenario uses open-source Apache Flink 1.20 with the `flink-sql-avro-confluent` connector JAR for SR integration. FIPS 140-2 compliance is achievable via cp-ansible's `fips_enabled: true` variable for CP on RHEL and CFK's `--set fipsmode=true` Helm flag for OpenShift.

**Primary recommendation:** Structure as 4 plans: (1) CP on RHEL Ansible scenario + C4E validation, (2) Private Cloud Terraform scenario, (3) MRC backend for fsi-dr.sh + DR runbook, (4) standalone Flink + FIPS compliance. Each plan integrates with existing governance, DR, and observability patterns.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
No locked decisions -- all implementation choices are at Claude's discretion. This is a pure infrastructure phase.

### Claude's Discretion
Key areas for Claude to decide:
- Ansible role structure and variable organization for CP deployment
- Private Cloud Terraform module structure (extending shared governance modules)
- MRC observer promotion automation approach (Confluent CLI-based or API-based)
- FIPS compliance validation method (JVM flag checks, TLS library validation, OpenShift FIPS mode detection)
- Standalone Flink systemd service file structure and Ansible role organization
- How MRC backend integrates with existing fsi-dr.sh dispatch pattern (new `mrc_*` functions)

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| IAC-04 | Operator can deploy CP on RHEL with Ansible roles (Kafka, SR, Connect, MDS RBAC) | cp-ansible roles documented; `kafka_broker`, `schema_registry`, `kafka_connect` roles with `rbac_enabled: true` for MDS; systemd is native service management |
| IAC-05 | Operator can deploy Confluent Private Cloud scenario with Terraform modules | Confluent Terraform provider supports self-managed clusters via `kafka_rest_endpoint`; shared governance modules reusable with provider endpoint override |
| DR-06 | MRC with automatic observer promotion (2.5-cluster pattern) provides RPO=0 | MRC replica placement v2 with `observerPromotionPolicy: under-min-isr`; 2.5-DC pattern (2 full DCs + 1 light DC for KRaft quorum); new `mrc` backend in fsi-dr.sh |
| FLINK-03 | CP standalone Flink deployed via Ansible roles with systemd service management | Apache Flink standalone mode (JobManager + TaskManagers as OS processes); `flink-sql-avro-confluent` connector for SR integration; systemd unit files for JM/TM |
| COMP-03 | FIPS 140-2 compliance automated for CP on RHEL and CFK on FIPS-enabled OpenShift | cp-ansible: `fips_enabled: true` + `fips_mode: fips-140-2`; CFK: `--set fipsmode=true` Helm flag; BCFKS keystore type; RHEL OS-level FIPS mode required |
</phase_requirements>

## Standard Stack

### Core

| Library/Tool | Version | Purpose | Why Standard |
|--------------|---------|---------|--------------|
| cp-ansible (Confluent Ansible) | 7.6.x / 8.x | Ansible roles for CP deployment | Official Confluent automation; manages systemd services natively |
| Ansible | 9.x (ansible-core 2.16) | Automation framework | Required for RHEL 8 compat; latest supported by cp-ansible for CP 7.x |
| confluentinc/confluent TF provider | ~> 2.0 | Terraform provider for CP topic/schema/RBAC | Already in use; supports self-managed via kafka_rest_endpoint |
| Apache Flink | 1.20 | Standalone stream processing | Latest LTS; matches CFK Flink version for parity |
| Bouncy Castle FIPS | Bundled with CP | FIPS-compliant crypto provider | Required for FIPS 140-2 keystore (BCFKS) and TLS cipher enforcement |

### Supporting

| Library/Tool | Version | Purpose | When to Use |
|--------------|---------|---------|-------------|
| flink-sql-avro-confluent | 3.2.0-1.20 | Avro-Confluent format connector for Flink | Standalone Flink SR integration (same version as CFK Flink) |
| JMX Exporter | 0.17+ | Prometheus metrics from JMX | CP broker/Flink metrics export to observability providers |
| Confluent CLI | v3.x | CP cluster management | MRC observer promotion, topic management, mirror operations |
| systemd | OS-native | Service management | CP components + Flink JM/TM on RHEL |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| cp-ansible | Manual RPM install + custom roles | cp-ansible handles idempotent config, systemd unit generation, and rolling upgrades -- custom roles would rebuild all of this |
| Apache Flink standalone | Confluent Platform for Apache Flink | CP Flink requires Kubernetes; standalone mode is the only non-K8s option |
| BCFKS keystore | PKCS12 keystore | PKCS12 is NOT FIPS-compliant per Confluent docs; must use BCFKS |
| Confluent TF provider for Private Cloud | Pure Ansible for Private Cloud | TF provider enables shared governance module reuse; Ansible alone would require parallel validation logic |

## Architecture Patterns

### Recommended Project Structure

```
scenarios/
  cp-rhel/
    README.md                      # Quickstart and architecture overview
    inventory/
      hosts.yml.example            # Ansible inventory template (3 brokers, 2 SR, 2 Connect)
      group_vars/
        all.yml                    # Common vars: CP version, FIPS, TLS, MDS
        kafka_broker.yml           # Broker-specific: rack, MRC placement, JMX
        schema_registry.yml        # SR config: compatibility, listeners
        kafka_connect.yml          # Connect workers: plugins, REST
        flink.yml                  # Flink JM/TM config (custom role)
    playbooks/
      deploy-cp.yml                # Main playbook importing cp-ansible roles
      deploy-flink.yml             # Standalone Flink deployment
      validate-fips.yml            # FIPS compliance validation playbook
    roles/
      flink_standalone/            # Custom role for Flink (not in cp-ansible)
        tasks/main.yml
        templates/
          flink-jobmanager.service.j2
          flink-taskmanager.service.j2
          flink-conf.yaml.j2
        defaults/main.yml
    topics/                        # Topic YAML definitions (for c4e-precheck)
      corebanking-account-txn.yml
      fraud-alert-signal.yml
      compliance-screening-result.yml
  private-cloud/
    README.md                      # Quickstart for Private Cloud TF scenario
    main.tf                        # Provider config with kafka_rest_endpoint
    variables.tf                   # CP cluster endpoints, credentials
    example-topics.tf              # Reference topic modules (shared governance)
    terraform.tfvars.example       # Example variable values
```

### Pattern 1: cp-ansible Inventory-Driven Deployment

**What:** All CP configuration lives in Ansible inventory variables (hosts.yml + group_vars). The playbook imports cp-ansible roles and configures Kafka brokers, Schema Registry, Connect, and MDS RBAC via variable declarations.

**When to use:** Deploying CP on bare-metal RHEL or VMs with systemd service management.

**Example:**
```yaml
# inventory/hosts.yml.example
# Source: cp-ansible docs + Confluent Ansible authorization docs
all:
  vars:
    confluent_server_enabled: true
    confluent_package_version: "7.6.0"
    rbac_enabled: true
    mds_super_user: mds
    mds_super_user_password: "{{ vault_mds_password }}"
    kafka_broker_ldap_user: kafka_broker
    kafka_broker_ldap_password: "{{ vault_kafka_broker_password }}"
    schema_registry_ldap_user: schema_registry
    schema_registry_ldap_password: "{{ vault_sr_password }}"
    kafka_connect_ldap_user: connect_worker
    kafka_connect_ldap_password: "{{ vault_connect_password }}"
    ssl_enabled: true
    ssl_mutual_auth_enabled: true
    # FIPS -- controlled by variable, applied when fips_enabled=true
    fips_enabled: false
    fips_mode: "fips-140-2"

  children:
    kafka_broker:
      hosts:
        kafka-east-1: {broker_id: 1, kafka_broker_custom_properties: {broker.rack: us-east-1a}}
        kafka-east-2: {broker_id: 2, kafka_broker_custom_properties: {broker.rack: us-east-1b}}
        kafka-east-3: {broker_id: 3, kafka_broker_custom_properties: {broker.rack: us-east-1c}}
    schema_registry:
      hosts:
        sr-east-1: {}
        sr-east-2: {}
    kafka_connect:
      hosts:
        connect-east-1: {}
        connect-east-2: {}
```

### Pattern 2: MRC 2.5-Cluster Replica Placement

**What:** Multi-Region Cluster with 2 full data centers + 1 light DC for KRaft quorum. Topics use replica placement v2 JSON with sync replicas in DC1+DC2 and async observers in DR DC. `observerPromotionPolicy: under-min-isr` enables automatic promotion when ISR drops below `min.insync.replicas`.

**When to use:** Compliance-tier or critical-tier topics on CP requiring RPO=0.

**Example:**
```json
{
  "version": 2,
  "replicas": [
    {"count": 2, "constraints": {"rack": "us-east"}},
    {"count": 2, "constraints": {"rack": "us-west"}}
  ],
  "observers": [
    {"count": 1, "constraints": {"rack": "us-central"}}
  ],
  "observerPromotionPolicy": "under-min-isr"
}
```
```bash
# Source: Confluent MRC docs
kafka-topics --create \
  --bootstrap-server kafka-east-1:9092 \
  --topic compliance.screening.v1.result \
  --partitions 12 \
  --replica-placement /path/to/mrc-placement-critical.json \
  --config min.insync.replicas=3
```

**Key config for RPO=0:** With 2 replicas in east + 2 in west + 1 observer in central, setting `min.insync.replicas=3` ensures synchronous replication across both DCs. Producers MUST use `acks=all`.

### Pattern 3: Private Cloud Terraform with Shared Governance

**What:** Terraform scenario directory that points the Confluent provider at a self-managed CP cluster's REST endpoint. Reuses the shared `modules/topic` module for governance parity.

**When to use:** Deploying governed topics on self-managed CP infrastructure via Terraform (same GitOps workflow as CC).

**Example:**
```hcl
# scenarios/private-cloud/main.tf
terraform {
  required_providers {
    confluent = {
      source  = "confluentinc/confluent"
      version = "~> 2.0"
    }
  }
}

provider "confluent" {
  kafka_rest_endpoint = var.cp_kafka_rest_endpoint
  kafka_api_key       = var.cp_kafka_api_key
  kafka_api_secret    = var.cp_kafka_api_secret

  schema_registry_rest_endpoint = var.cp_sr_rest_endpoint
  schema_registry_api_key       = var.cp_sr_api_key
  schema_registry_api_secret    = var.cp_sr_api_secret
}

module "corebanking_account_txn" {
  source          = "../../modules/topic"
  domain          = "corebanking"
  application     = "core"
  schema_version  = "v1"
  entity          = "account-transaction"
  owner           = "corebanking-team@fsi.org"
  sla_tier        = "critical"
  schema_file     = "../../schemas/examples/account-transaction.avsc"
  # ... same governance inputs as CC scenarios
}
```

### Pattern 4: Standalone Flink with systemd

**What:** Apache Flink deployed as OS processes (JobManager + TaskManagers) managed by systemd unit files. An Ansible role handles installation, configuration, service creation, and SR integration via `flink-sql-avro-confluent` connector JAR.

**When to use:** Stream processing on RHEL bare-metal where Kubernetes is not available.

**Example:**
```ini
# flink-jobmanager.service.j2 (systemd unit template)
[Unit]
Description=Apache Flink JobManager
After=network.target

[Service]
Type=forking
User=flink
Group=flink
ExecStart={{ flink_home }}/bin/jobmanager.sh start
ExecStop={{ flink_home }}/bin/jobmanager.sh stop
Environment="JAVA_HOME={{ java_home }}"
Environment="FLINK_HOME={{ flink_home }}"
Restart=on-failure
RestartSec=30
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
```

### Pattern 5: FIPS Compliance Validation

**What:** Automated validation that FIPS requirements are met: OS-level FIPS mode enabled, BCFKS keystores in use, Bouncy Castle FIPS providers configured, and only FIPS-approved cipher suites active.

**When to use:** CP on RHEL with FIPS requirement, CFK on FIPS-enabled OpenShift.

**Example (validation playbook task):**
```yaml
# validate-fips.yml
- name: Verify OS FIPS mode enabled
  command: cat /proc/sys/crypto/fips_enabled
  register: fips_check
  failed_when: fips_check.stdout != "1"

- name: Verify BCFKS keystore in use
  shell: >
    grep -c "ssl.keystore.type=BCFKS"
    /etc/kafka/server.properties
  register: keystore_check
  failed_when: keystore_check.stdout == "0"

- name: Verify Bouncy Castle FIPS provider configured
  shell: >
    grep -c "BcFipsProviderCreator"
    /etc/kafka/server.properties
  register: provider_check
  failed_when: provider_check.stdout == "0"
```

### Anti-Patterns to Avoid

- **Hand-rolling cp-ansible roles:** Do NOT create custom Ansible roles for Kafka, SR, or Connect deployment. cp-ansible already handles package install, config templating, systemd unit creation, TLS, RBAC/MDS, and rolling upgrades. Custom roles would duplicate this and miss edge cases.
- **Using PKCS12 keystores for FIPS:** Only BCFKS keystores are FIPS-compliant. PKCS12 will pass basic TLS checks but fail FIPS certification.
- **Running Confluent Platform for Apache Flink on bare metal:** Confluent's managed Flink (CP Flink) requires Kubernetes. Use open-source Apache Flink standalone mode for RHEL deployments.
- **Skipping acks=all for MRC RPO=0 topics:** MRC synchronous replication only guarantees RPO=0 when producers use `acks=all`. Without it, acknowledged messages may not be replicated to the remote DC.
- **Using the `confluent_kafka_mirror_topic` resource for MRC:** MRC is NOT the same as Cluster Linking mirror topics. MRC uses native Kafka replica placement -- there is no mirror topic to "promote." Observer promotion happens automatically or via `kafka-leader-election.sh`.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| CP deployment automation | Custom Ansible roles for Kafka/SR/Connect | cp-ansible official roles | Handles systemd units, config templating, rolling upgrades, security, idempotency |
| FIPS crypto enforcement | Custom TLS config + JVM flags | cp-ansible `fips_enabled: true` | Automatically configures BC FIPS providers, BCFKS keystores, approved ciphers |
| MRC replica placement | Custom broker config for multi-DC replication | Confluent replica placement v2 JSON | Topic-level replica placement with observer promotion built into Confluent Server |
| Flink standalone service management | Raw shell scripts for start/stop | systemd unit files (forking type) | Proper lifecycle management, automatic restart, journal logging |
| Private Cloud topic governance | Separate validation logic for CP topics | Shared `modules/topic` + Confluent TF provider | Provider works with self-managed clusters via REST endpoint; same module = same governance |
| Ansible topic YAML validation | Custom Python parser | Extend c4e-precheck.py | Already handles TF and CFK YAML; extend for Ansible inventory topic definitions |

**Key insight:** The biggest risk in this phase is diverging from established patterns. CP on RHEL must produce the same governance outcomes (naming, SLA tiers, RBAC) as CC and CFK scenarios. The shared Terraform module and C4E precheck already enforce this -- extend them, don't replace them.

## Common Pitfalls

### Pitfall 1: cp-ansible Version Mismatch with CP Version
**What goes wrong:** cp-ansible roles are versioned to match CP versions. Using cp-ansible 7.6 roles with CP 8.x (or vice versa) causes config template errors and missing properties.
**Why it happens:** cp-ansible tags follow CP version tags. The relationship is not always obvious.
**How to avoid:** Pin cp-ansible version to match the target CP version in the inventory. Document the version pair in the scenario README.
**Warning signs:** Ansible template errors referencing unknown properties, or missing systemd unit files after playbook run.

### Pitfall 2: MRC min.insync.replicas Misconfiguration
**What goes wrong:** Setting `min.insync.replicas` too low allows a single-DC failure to produce acknowledged but unreplicated messages, breaking RPO=0 guarantee.
**Why it happens:** With 2+2+1 replicas (east+west+observer), `min.insync.replicas=2` allows all ISR members to be in one DC. Only `min.insync.replicas=3` (or higher) forces cross-DC sync.
**How to avoid:** Document the formula: `min.insync.replicas > max replicas in any single DC`. For 2+2+1: min.isr must be >= 3. Enforce via topic module validation for MRC scenarios.
**Warning signs:** Producers succeed with only one DC's brokers in the ISR.

### Pitfall 3: FIPS Mode Without OS-Level Enablement
**What goes wrong:** Enabling FIPS in CP/CFK config without enabling FIPS at the OS level causes crypto library mismatches. The JVM loads non-FIPS providers from the system, defeating the FIPS enforcement.
**Why it happens:** FIPS is a two-layer requirement: OS (RHEL `fips-mode-setup --enable`) AND application (CP `enable.fips=true`). Missing either layer breaks compliance.
**How to avoid:** Validation playbook checks `/proc/sys/crypto/fips_enabled == 1` before proceeding. For OpenShift, verify FIPS was enabled at cluster install time (cannot be enabled post-install).
**Warning signs:** `/proc/sys/crypto/fips_enabled` returns 0 on CP hosts; OpenShift nodes show FIPS disabled in `oc get nodes -o yaml`.

### Pitfall 4: Standalone Flink Avro-Confluent JAR Missing
**What goes wrong:** Flink SQL jobs fail with `Could not find format 'avro-confluent'` or `Class not found` errors when connecting to Schema Registry.
**Why it happens:** Apache Flink base distribution does not include the avro-confluent format connector. It must be downloaded and placed in `$FLINK_HOME/lib/` before starting the cluster.
**How to avoid:** Ansible role includes a task to download/copy the `flink-sql-avro-confluent-*.jar` and `flink-avro-*.jar` to the lib directory. Same approach as CFK Flink Docker image from Phase 8.
**Warning signs:** Flink UI shows job submission failures; `flink run` exits with ClassNotFoundException.

### Pitfall 5: Observer Promotion Confused with Mirror Promotion
**What goes wrong:** Treating MRC observer promotion like Cluster Linking mirror promotion -- trying to run `confluent kafka mirror failover` on MRC topics, which does nothing (there are no mirror topics in MRC).
**Why it happens:** Both achieve DR failover but via completely different mechanisms. CL uses mirror topics that need promotion. MRC uses replica placement where observers auto-promote into ISR.
**How to avoid:** The `mrc` backend in fsi-dr.sh must use different commands: check observer status via `kafka-replica-status.sh` or admin API, trigger leader election via `kafka-leader-election.sh` if automatic promotion hasn't occurred.
**Warning signs:** Running mirror commands on MRC topics returns empty results; observers show as "already in ISR" during a DC failure (meaning auto-promotion worked).

### Pitfall 6: Private Cloud Provider Authentication
**What goes wrong:** The Confluent Terraform provider cannot authenticate to a self-managed CP cluster because MDS/RBAC token exchange differs from CC's API key authentication.
**Why it happens:** CC uses API key/secret directly. CP with MDS uses LDAP-backed tokens obtained via the MDS REST endpoint. The TF provider needs to be configured with the correct authentication flow.
**How to avoid:** Configure the provider with `kafka_rest_endpoint` pointing to the CP REST Proxy or Kafka's REST endpoint with appropriate credentials. Document the authentication chain in the scenario README.
**Warning signs:** Terraform plan fails with 401 Unauthorized against CP REST endpoint.

### Pitfall 7: Ansible Topic YAML Format Divergence
**What goes wrong:** C4E precheck fails on CP-RHEL topic definitions because they use a different YAML format than CFK KafkaTopic CRDs.
**Why it happens:** CP on RHEL topics are defined via Ansible variables or standalone YAML (not Kubernetes CRDs with `kind: KafkaTopic`). The parser needs a third format.
**How to avoid:** Define a simple YAML topic definition format for CP-RHEL (inspired by the existing CFK format) and extend `c4e-precheck.py` to parse it. Keep the same governance fields: domain, application, version, entity, sla_tier, data_classification.
**Warning signs:** c4e-precheck.py reports "No topic modules found" when run against the CP-RHEL scenario directory.

## Code Examples

### MRC Backend Functions for fsi-dr.sh

```bash
# Source: Pattern derived from existing cl_* and mm2_* backends in fsi-dr.sh

# MRC environment variables
# FSI_MRC_BOOTSTRAP -- Bootstrap servers for the MRC cluster
# FSI_MRC_EAST_RACK -- Rack ID for East DC (e.g., "us-east")
# FSI_MRC_WEST_RACK -- Rack ID for West DC (e.g., "us-west")
# FSI_MRC_OBSERVER_RACK -- Rack ID for observer DC (e.g., "us-central")

# mrc_preflight -- MRC-specific pre-flight checks
# Verifies both DCs have ISR replicas for critical topics
mrc_preflight() {
  local pass=0 warn=0 fail=0
  echo "=== Pre-flight Checks (MRC Backend) ==="
  echo ""

  # Check 1: East DC brokers reachable
  # Check 2: West DC brokers reachable
  # Check 3: Observer DC brokers reachable
  # Check 4: Critical topics have ISR members in both DCs
  # Check 5: Consul reachable
  # ... (follows mm2_preflight pattern)
}

# mrc_failover_mirrors -- Trigger leader election to observer/west replicas
# MRC does NOT use mirror topics. It uses replica placement + leader election.
mrc_failover_mirrors() {
  if [ "${DRY_RUN}" = true ]; then
    echo "  [DRY-RUN] MRC failover: would trigger preferred leader election"
    echo "  Observer replicas in ${FSI_MRC_WEST_RACK} will be promoted to ISR"
    echo "  (automatic if observerPromotionPolicy=under-min-isr)"
    return 0
  fi
  # Use kafka-leader-election.sh for unclean leader election if auto-promotion
  # hasn't occurred, or verify observers are already promoted
  kafka-leader-election.sh --bootstrap-server "${FSI_MRC_BOOTSTRAP}" \
    --election-type PREFERRED --all-topic-partitions
}

# mrc_get_mirror_lag -- Report observer replica lag (not mirror lag)
# Returns per-partition observer lag via kafka-replica-status
mrc_get_mirror_lag() {
  # Uses confluent CLI or kafka admin API to get replica status
  # Format output as JSON array matching CL/MM2 format for fsi-dr status
}

# mrc_get_mirror_status -- Report observer promotion status
mrc_get_mirror_status() {
  # Check which observers are promoted into ISR
  # Report per-topic observer state (OBSERVER, IN_ISR, LAGGING)
}
```

### FIPS Validation Script (CP on RHEL)

```bash
#!/usr/bin/env bash
# scripts/validate-fips.sh -- Verify FIPS compliance for CP on RHEL
set -euo pipefail

echo "=== FIPS 140-2 Compliance Validation ==="
echo ""

# Check 1: OS-level FIPS mode
fips_val=$(cat /proc/sys/crypto/fips_enabled)
if [ "${fips_val}" = "1" ]; then
  echo "  PASS: OS FIPS mode enabled"
else
  echo "  FAIL: OS FIPS mode disabled (/proc/sys/crypto/fips_enabled=${fips_val})"
  echo "  Action: Run 'fips-mode-setup --enable' and reboot"
fi

# Check 2: Java version (17 or 21 required)
java_ver=$(java -version 2>&1 | head -1)
echo "  INFO: Java version: ${java_ver}"

# Check 3: BCFKS keystore in use
for conf in /etc/kafka/server.properties /etc/schema-registry/schema-registry.properties; do
  if [ -f "${conf}" ]; then
    if grep -q "ssl.keystore.type=BCFKS" "${conf}"; then
      echo "  PASS: BCFKS keystore in ${conf}"
    else
      echo "  FAIL: BCFKS keystore NOT configured in ${conf}"
    fi
  fi
done

# Check 4: Bouncy Castle FIPS provider
for conf in /etc/kafka/server.properties; do
  if grep -q "BcFipsProviderCreator" "${conf}"; then
    echo "  PASS: BC FIPS provider configured"
  else
    echo "  FAIL: BC FIPS provider NOT configured"
  fi
done
```

### CP Topic Definition YAML (for C4E validation)

```yaml
# scenarios/cp-rhel/topics/corebanking-account-txn.yml
# CP-RHEL topic definition -- validated by c4e-precheck.py
kind: CPTopic
metadata:
  name: corebanking.core.v1.account-transaction
  labels:
    fsi.sla-tier: critical
    fsi.owner: corebanking-team@fsi.org
    fsi.data-classification: confidential
    fsi.domain: corebanking
    fsi.application: core
    fsi.version: v1
    fsi.entity: account-transaction
spec:
  partitionCount: 12
  replicationFactor: 5
  configs:
    retention.ms: "604800000"
    min.insync.replicas: "3"
  replicaPlacement: mrc-placement-critical.json
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| ZooKeeper for CP cluster coordination | KRaft mode (no ZooKeeper) | CP 7.4+ (GA), 8.0+ (default) | MRC 2.5-cluster uses KRaft controllers; ZK not required |
| FIPS 140-2 only | FIPS 140-2 and FIPS 140-3 | CP 8.2 | 140-3 is new default; 140-2 remains valid for existing deployments |
| Manual observer promotion | Automatic observer promotion (policy-based) | CP 6.1 | Reduces human intervention; `under-min-isr` policy is default |
| cp-ansible with Ansible 2.x | cp-ansible with Ansible 9.x+ | CP 7.6+ | RHEL 8 requires Ansible 9.x (core 2.16); RHEL 9+ supports 10.x+ |
| Confluent Platform for Flink (K8s only) | Still K8s only | Current | No bare-metal CP Flink; use open-source Apache Flink standalone |

**Deprecated/outdated:**
- **ZooKeeper mode for MRC:** KRaft is the current standard; 2.5-cluster uses KRaft controllers
- **PKCS12 keystores for FIPS:** Only BCFKS is FIPS-compliant per Confluent docs
- **AvroProducer/AvroConsumer (deprecated Flink API):** Use modern AvroSerializer/AvroDeserializer with format connectors

## Open Questions

1. **Confluent Terraform Provider + Self-Managed CP Authentication**
   - What we know: Provider supports `kafka_rest_endpoint` for managing self-managed clusters; CC uses API key auth
   - What's unclear: Whether MDS token-based auth works transparently with the TF provider, or if REST Proxy is needed as a middleware layer
   - Recommendation: Test provider against a CP REST endpoint in Plan 2. Document both direct REST and REST Proxy auth paths. If direct auth fails, use REST Proxy as intermediary.

2. **MRC Failover Automation Details**
   - What we know: Observer auto-promotion handles ISR membership automatically; `kafka-leader-election.sh` can force election
   - What's unclear: Whether the `confluent` CLI has MRC-specific commands, or if the Kafka admin API is the only programmatic interface for observer status
   - Recommendation: Implement mrc_* backend using `kafka-leader-election.sh` and `kafka-replica-status.sh` commands. The CLI approach matches existing DR backend pattern (confluent CLI for CL, curl for MM2, kafka tools for MRC).

3. **cp-ansible and Standalone Flink Integration**
   - What we know: cp-ansible does not include a Flink role. CP Flink requires Kubernetes.
   - What's unclear: Whether there's an official way to integrate Flink metrics with the cp-ansible-deployed JMX exporter config
   - Recommendation: Create a custom Ansible role (`flink_standalone`) that follows cp-ansible conventions (variable naming, handler patterns, systemd template style). Configure JMX exporter separately for Flink processes.

4. **Private Cloud Scenario Scope**
   - What we know: The requirement says "deploy Confluent Private Cloud scenario with Terraform modules"
   - What's unclear: Whether "Private Cloud" means (a) self-managed CP in private infra managed via TF, or (b) a specific Confluent BYOC product
   - Recommendation: Implement as (a): a TF scenario directory that manages topics/schemas/RBAC on a pre-existing self-managed CP cluster via REST endpoint. This matches the project's GitOps governance model and reuses shared modules.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Bash (test-fsi-dr-*.sh pattern) + Python (c4e-precheck.py) |
| Config file | None -- tests are self-contained scripts |
| Quick run command | `bash tests/dr/test-fsi-dr-mrc.sh` |
| Full suite command | `bash tests/dr/test-fsi-dr-helpers.sh && bash tests/dr/test-fsi-dr-mm2.sh && bash tests/dr/test-fsi-dr-mrc.sh && python3 ci/scripts/c4e-precheck.py --scenario-dir scenarios/cp-rhel/ && python3 ci/scripts/c4e-precheck.py --scenario-dir scenarios/private-cloud/` |

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| IAC-04 | CP-RHEL Ansible inventory is valid + topics pass C4E precheck | unit | `python3 ci/scripts/c4e-precheck.py --scenario-dir scenarios/cp-rhel/` | Partially (c4e-precheck exists, CP parser needed) |
| IAC-05 | Private Cloud TF scenario validates + topics pass C4E precheck | unit | `cd scenarios/private-cloud && terraform validate && python3 ../../ci/scripts/c4e-precheck.py --scenario-dir .` | Partially (TF validate works, scenario dir needed) |
| DR-06 | MRC backend functions pass unit tests (preflight, failover, lag, status) | unit | `bash tests/dr/test-fsi-dr-mrc.sh` | Wave 0 |
| FLINK-03 | Flink Ansible role templates render correctly; systemd units valid | unit | `ansible-playbook --syntax-check scenarios/cp-rhel/playbooks/deploy-flink.yml` | Wave 0 |
| COMP-03 | FIPS validation script checks OS mode, keystore, provider | unit | `bash scripts/validate-fips.sh` (on FIPS-enabled host; CI validates script syntax) | Wave 0 |

### Sampling Rate
- **Per task commit:** Quick run command for the changed domain (DR tests for MRC backend, c4e-precheck for scenario dirs)
- **Per wave merge:** Full suite
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `tests/dr/test-fsi-dr-mrc.sh` -- MRC backend unit tests (follows test-fsi-dr-mm2.sh pattern)
- [ ] CP topic YAML parser extension in `ci/scripts/c4e-precheck.py`
- [ ] `scripts/validate-fips.sh` -- FIPS compliance validator (syntax-checkable in CI)
- [ ] Flink standalone Ansible role (`scenarios/cp-rhel/roles/flink_standalone/`)

## Sources

### Primary (HIGH confidence)
- [Confluent Ansible docs](https://docs.confluent.io/ansible/current/overview.html) -- cp-ansible overview, roles, component names
- [Confluent Ansible requirements](https://docs.confluent.io/ansible/current/ansible-requirements.html) -- OS versions, Ansible versions, Java requirements
- [Confluent MRC configuration](https://docs.confluent.io/platform/current/multi-dc-deployments/multi-region.html) -- Replica placement v2, observer promotion, 2.5-DC pattern, min.insync.replicas for RPO=0
- [Confluent FIPS compliance](https://docs.confluent.io/platform/current/security/compliance/overview.html) -- BCFKS keystores, BC FIPS providers, component config, RHEL requirements
- [Confluent Ansible encryption/FIPS](https://docs.confluent.io/ansible/current/ansible-encrypt.html) -- `fips_enabled`, `fips_mode` variables
- [Confluent Ansible authorization](https://docs.confluent.io/ansible/current/ansible-authorize.html) -- MDS RBAC configuration, LDAP variables
- [CFK FIPS compliance](https://docs.confluent.io/operator/current/co-security-compliance.html) -- `--set fipsmode=true`, BCFKS, component CR config
- [Apache Flink standalone deployment](https://nightlies.apache.org/flink/flink-docs-master/docs/deployment/resource-providers/standalone/overview/) -- JM/TM as processes, session/application modes

### Secondary (MEDIUM confidence)
- [Confluent blog: Automatic Observer Promotion](https://www.confluent.io/blog/automatic-observer-promotion-for-safe-multi-datacenter-failover-in-confluent-6-1/) -- Observer promotion policy details
- [Confluent MRC architectures](https://docs.confluent.io/platform/current/multi-dc-deployments/multi-region-architectures.html) -- 2.5-DC pattern details
- [Confluent CP Flink overview](https://docs.confluent.io/platform/current/flink/overview.html) -- Confirmed K8s-only for CP Flink

### Tertiary (LOW confidence)
- Confluent TF provider + self-managed clusters -- provider docs confirm `kafka_rest_endpoint` param exists but specific CP/MDS auth flow needs validation
- cp-ansible MRC integration -- confirmed cp-ansible supports multi-DC but specific MRC replica placement automation via inventory vars not verified

## Metadata

**Confidence breakdown:**
- Standard stack: MEDIUM -- cp-ansible and MRC docs are well-documented; Flink standalone on RHEL uses open-source Apache Flink (not CP Flink), which is verified; Private Cloud TF auth needs validation
- Architecture: MEDIUM -- patterns are clear for each domain; integration points between cp-ansible, shared TF modules, and MRC need careful wiring during implementation
- Pitfalls: HIGH -- common failure modes well-documented in Confluent docs and derived from established Phase 4/8 patterns

**Research date:** 2026-03-27
**Valid until:** 2026-04-27 (30 days -- stable domain; cp-ansible and MRC are mature features)

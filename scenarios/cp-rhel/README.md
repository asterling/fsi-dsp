# CP on RHEL -- Confluent Platform on Bare-Metal RHEL

Self-contained Ansible inventory, group vars, and deployment playbook for standing up a fully governed Kafka environment on RHEL using the `cp-ansible` collection with MDS RBAC, TLS, and systemd management.

## Prerequisites

- RHEL 8.x or 9.x (all target hosts)
- Ansible 9.x (core 2.16+) on the control node
- Java 17 JDK on all target hosts
- `cp-ansible` 7.6.x collection (`confluent.platform`)
- Network connectivity between control node and all target hosts (SSH)
- DNS or `/etc/hosts` entries for all cluster nodes
- (Optional) HashiCorp Vault for secret management
- (Optional) LDAP/AD backend for MDS RBAC identity

## Quick Start

### 1. Install the cp-ansible collection

```bash
ansible-galaxy collection install confluent.platform
```

### 2. Copy and customize inventory

```bash
cp inventory/hosts.yml.example inventory/hosts.yml
```

Edit `inventory/hosts.yml` with your actual hostnames, IP addresses, and broker rack assignments.

### 3. Set secrets in vault or vars

Store sensitive values (MDS passwords, LDAP credentials, TLS keystores) in Ansible Vault or update the `vault_*` references in `inventory/group_vars/all.yml`:

```bash
ansible-vault create inventory/group_vars/vault.yml
```

### 4. Run the deployment playbook

```bash
ansible-playbook -i inventory/hosts.yml playbooks/deploy-cp.yml
```

To use Ansible Vault for secrets:

```bash
ansible-playbook -i inventory/hosts.yml playbooks/deploy-cp.yml --ask-vault-pass
```

## Architecture

This scenario deploys the following topology in a single data center (East):

| Component | Nodes | Purpose |
|-----------|-------|---------|
| Kafka Brokers | 3 | Multi-rack Kafka brokers with Confluent Server |
| Schema Registry | 2 | HA Schema Registry with TLS |
| Kafka Connect | 2 | Distributed Connect workers with JDBC plugin path |
| MDS | (co-located on brokers) | Metadata Service for Confluent RBAC |

### Multi-Rack Awareness

Brokers are spread across three availability zones (`us-east-1a`, `us-east-1b`, `us-east-1c`) via `broker.rack` configuration. This ensures partition replicas are distributed across racks for fault tolerance.

### Systemd Management

All CP components are managed via systemd units installed by `cp-ansible`:

```bash
# Check service status
systemctl status confluent-kafka
systemctl status confluent-schema-registry
systemctl status confluent-kafka-connect

# Restart a service
systemctl restart confluent-kafka
```

## Topic Governance

Topic definitions use the `CPTopic` YAML format in the `topics/` directory. These files carry the same FSI governance labels as CFK `KafkaTopic` CRDs and CC Terraform topic modules:

- `fsi.sla-tier` -- SLA tier (critical, standard, best-effort, compliance)
- `fsi.domain` -- Business domain
- `fsi.owner` -- Team email responsible for the topic
- `fsi.data-classification` -- Data classification per FSI policy
- `fsi.application` -- Application name within the domain
- `fsi.version` -- Schema version identifier
- `fsi.entity` -- Data entity name

CPTopic YAML files are validated by `c4e-precheck.py` in the CI pipeline to enforce naming conventions and governance labels before deployment.

## Security

### TLS

Mutual TLS is enabled by default (`ssl_mutual_auth_enabled: true`). The `cp-ansible` collection manages certificate generation and distribution when configured with a CA. Update `inventory/group_vars/all.yml` with your CA certificate paths or use auto-generated certs for development.

### MDS RBAC

Confluent RBAC via Metadata Service (MDS) is enabled (`rbac_enabled: true`). MDS requires an LDAP/AD backend for identity resolution. Service account credentials for each component (broker, SR, Connect) are configured in `inventory/group_vars/all.yml` using Ansible Vault references.

### FIPS 140-2

FIPS mode is toggled via `fips_enabled` in `inventory/group_vars/all.yml` (default: `false`). When enabled, CP components use FIPS-approved cryptographic algorithms. FIPS validation is covered in a separate plan (see `validate-fips.yml`).

> **Note:** Standalone Flink deployment and FIPS validation playbook are covered in separate plans within this phase.

## Files

| Directory | File | Purpose |
|-----------|------|---------|
| inventory/ | hosts.yml.example | Ansible inventory with 3 brokers, 2 SR, 2 Connect |
| inventory/group_vars/ | all.yml | Common vars: CP version, TLS, MDS, FIPS, JMX |
| inventory/group_vars/ | kafka_broker.yml | Broker-specific config (rack, replication, retention) |
| inventory/group_vars/ | schema_registry.yml | Schema Registry config (compatibility level) |
| inventory/group_vars/ | kafka_connect.yml | Connect config (replication factors, plugin path) |
| playbooks/ | deploy-cp.yml | Main deployment playbook using cp-ansible roles |
| topics/ | corebanking-account-txn.yml | CPTopic: critical tier, core banking transactions |
| topics/ | fraud-alert-signal.yml | CPTopic: critical tier, fraud detection alerts |
| topics/ | compliance-screening-result.yml | CPTopic: compliance tier, regulatory screening |

## Cloud-Specific Notes

- **Network:** Ensure firewall rules allow Kafka (9092-9093), Schema Registry (8081), Connect (8083), MDS (8090), and JMX exporter (7778) ports between all cluster nodes.
- **Storage:** Kafka log directories should be on dedicated high-throughput storage (SSD/NVMe recommended). Configure `log.dirs` in broker group vars for multi-disk setups.
- **DR:** CP on RHEL supports both Cluster Linking and Multi-Region Clusters (MRC). MRC with observer promotion provides RPO=0 for compliance-tier topics. See ADR-008 for DR tier classification.
- **Observability:** JMX exporter is enabled (`jmxexporter_enabled: true`). Point your Prometheus scrape targets at port 7778 on each CP node. See the main platform `observability/` directory for provider-specific dashboards.

# Private Cloud -- Confluent Platform via Terraform

Self-contained Terraform deployment for governed Kafka topics on a pre-existing self-managed Confluent Platform cluster, using the Confluent Terraform provider's `kafka_rest_endpoint` mode.

## Prerequisites

- Terraform >= 1.7.0
- Running Confluent Platform cluster with Kafka REST Proxy (MDS or REST Proxy endpoint)
- Schema Registry REST endpoint accessible from the Terraform runner
- Credentials (API key/secret or LDAP-based) for Kafka REST and Schema Registry REST APIs

## Quick Start

### 1. Copy configuration templates

```bash
cd scenarios/private-cloud/
cp terraform.tfvars.example terraform.tfvars
```

### 2. Set endpoints and credentials

Edit `terraform.tfvars` with your CP cluster REST endpoints and API credentials:

```hcl
cp_kafka_rest_endpoint = "https://kafka-east-1.example.com:8090"
cp_kafka_api_key       = "<your-kafka-rest-api-key>"
cp_kafka_api_secret    = "<your-kafka-rest-api-secret>"
cp_sr_rest_endpoint    = "https://sr-east-1.example.com:8081"
cp_sr_api_key          = "<your-sr-api-key>"
cp_sr_api_secret       = "<your-sr-api-secret>"
cp_kafka_cluster_id    = "kafka-east-cluster"
```

### 3. Initialize Terraform

```bash
terraform init
```

### 4. Plan and apply

```bash
terraform plan
terraform apply
```

## What Gets Created

Each reference topic (corebanking, fraud, compliance) produces:
- Kafka topic with SLA-tier-derived partitions and retention
- Avro schema registered in Schema Registry with metadata tags
- RBAC bindings for producer and consumer service accounts
- DR mirror topic via Cluster Linking (if enabled)

## Files

| File | Purpose |
|------|---------|
| main.tf | Provider config with kafka_rest_endpoint for CP cluster |
| variables.tf | CP cluster endpoint and credential variables |
| example-topics.tf | 3 reference topic declarations using shared governance module |
| terraform.tfvars.example | Example values template |

## Deployment-Specific Notes

- **Authentication:** CP clusters use MDS (Metadata Service) or LDAP-backed REST credentials. The Confluent Terraform provider authenticates via `kafka_api_key`/`kafka_api_secret` against the REST endpoint.
- **RBAC:** Managed via MDS role bindings (same Terraform provider resources as Confluent Cloud).
- **Secrets:** HashiCorp Vault recommended for credential storage. See `.env.example` section for Vault integration patterns.
- **DR:** Cluster Linking or MirrorMaker 2, depending on topology. Configure `enable_dr_mirror` per topic.
- **Governance parity:** This scenario uses the same shared `modules/topic` module as CC and CFK scenarios -- identical topic naming, schema compatibility, RBAC, and SLA-tier enforcement.

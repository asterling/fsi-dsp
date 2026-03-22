# CC-GCP Scenario -- Confluent Cloud on GCP

Self-contained Terraform deployment for a fully governed Kafka environment on Confluent Cloud (GCP regions).

## Prerequisites

- Terraform >= 1.5
- Confluent Cloud organization with environment and dedicated Kafka cluster
- GCP project with Cloud Storage bucket for state backend
- Schema Registry cluster (Confluent Cloud)
- DR cluster with Cluster Linking configured

## Quick Start

### 1. Clone and configure

```bash
cd scenarios/cc-gcp/
cp clusters.auto.tfvars.example clusters.auto.tfvars
cp terraform.tfvars.example terraform.tfvars
```

Edit `clusters.auto.tfvars` with your Confluent Cloud cluster IDs and endpoints.
Edit `terraform.tfvars` with your API keys and secrets.

### 2. Configure backend

Create a GCS bucket or use an existing one. GCS provides built-in state locking -- no additional infrastructure needed. Update the `backend "gcs"` block in `main.tf` with your values:

```bash
# Create GCS bucket for state
gsutil mb -l us-east1 gs://fsi-terraform-state

# Enable versioning
gsutil versioning set on gs://fsi-terraform-state
```

### 3. Initialize and deploy

```bash
terraform init
terraform plan
terraform apply
```

### 4. Verify deployment

```bash
# List created topics
terraform output -json | jq 'keys'

# Check individual topic
terraform output -json corebanking_account_txn
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
| main.tf | Provider config and GCS backend |
| variables.tf | Cluster configuration variables |
| example-topics.tf | 3 reference topic declarations |
| clusters.auto.tfvars.example | Cluster endpoint template |
| terraform.tfvars.example | Secret values template |

## Cloud-Specific Notes

- **Private networking:** Private Service Connect (PSC) uses a single IP with manual DNS configuration.
- **Authentication:** Google Cloud Identity or Workload Identity Federation.
- **Secrets:** Google Secret Manager.
- **DR regions:** us-east1 (production) and us-west1 (DR).
- **Note:** GCP uses region names without hyphens before the digit (e.g., `us-east1` not `us-east-1`).

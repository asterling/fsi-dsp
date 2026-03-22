# CC-AWS Scenario -- Confluent Cloud on AWS

Self-contained Terraform deployment for a fully governed Kafka environment on Confluent Cloud (AWS regions).

## Prerequisites

- Terraform >= 1.5
- Confluent Cloud organization with environment and dedicated Kafka cluster
- AWS account with S3 bucket and DynamoDB table for state locking
- Schema Registry cluster (Confluent Cloud)
- DR cluster with Cluster Linking configured

## Quick Start

### 1. Clone and configure

```bash
cd scenarios/cc-aws/
cp clusters.auto.tfvars.example clusters.auto.tfvars
cp terraform.tfvars.example terraform.tfvars
```

Edit `clusters.auto.tfvars` with your Confluent Cloud cluster IDs and endpoints.
Edit `terraform.tfvars` with your API keys and secrets.

### 2. Configure backend

Create an S3 bucket with versioning enabled and a DynamoDB table with `LockID` as partition key. Update the `backend "s3"` block in `main.tf` with your values:

```bash
# Create S3 bucket for state
aws s3api create-bucket \
  --bucket fsi-terraform-state \
  --region us-east-1

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket fsi-terraform-state \
  --versioning-configuration Status=Enabled

# Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name fsi-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST
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
| main.tf | Provider config and S3 + DynamoDB backend |
| variables.tf | Cluster configuration variables |
| example-topics.tf | 3 reference topic declarations |
| clusters.auto.tfvars.example | Cluster endpoint template |
| terraform.tfvars.example | Secret values template |

## Cloud-Specific Notes

- **Private networking:** AWS PrivateLink with VPC Endpoint. AZ ID mapping is required between your VPC and Confluent Cloud.
- **Authentication:** IAM auth or external IdP via OAUTHBEARER.
- **Secrets:** AWS Secrets Manager. Kafka Connect has a native config provider for Secrets Manager.
- **DR regions:** us-east-1 (production) and us-west-2 (DR).

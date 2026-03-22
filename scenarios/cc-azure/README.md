# CC-Azure Scenario -- Confluent Cloud on Azure

Self-contained Terraform deployment for a fully governed Kafka environment on Confluent Cloud (Azure regions).

## Prerequisites

- Terraform >= 1.5
- Confluent Cloud organization with environment and dedicated Kafka cluster
- Azure subscription with Resource Group for Terraform state
- Azure Storage Account with blob container for state backend
- Schema Registry cluster (Confluent Cloud)
- DR cluster with Cluster Linking configured

## Quick Start

### 1. Clone and configure

```bash
cd scenarios/cc-azure/
cp clusters.auto.tfvars.example clusters.auto.tfvars
cp terraform.tfvars.example terraform.tfvars
```

Edit `clusters.auto.tfvars` with your Confluent Cloud cluster IDs and endpoints.
Edit `terraform.tfvars` with your API keys and secrets.

### 2. Configure backend

Create an Azure Storage Account and container, or use an existing one. Update the `backend "azurerm"` block in `main.tf` with your values:

```bash
# Create resource group (if needed)
az group create --name rg-terraform-state --location eastus2

# Create storage account
az storage account create \
  --name stterraformstate \
  --resource-group rg-terraform-state \
  --sku Standard_LRS \
  --encryption-services blob

# Create blob container
az storage container create \
  --name tfstate \
  --account-name stterraformstate
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
| main.tf | Provider config and Azure Blob Storage backend |
| variables.tf | Cluster configuration variables |
| example-topics.tf | 3 reference topic declarations |
| clusters.auto.tfvars.example | Cluster endpoint template |
| terraform.tfvars.example | Secret values template |

## Cloud-Specific Notes

- **Private networking:** Azure Private Link with Private Endpoint in VNet. Configure `AZURE_VNET_ID` and `AZURE_SUBNET_ID` in `.env.example`.
- **Authentication:** Azure AD / Entra ID OAuth tokens (OAUTHBEARER) work against both production and DR clusters -- no credential swap during failover.
- **Secrets:** Azure Key Vault or HashiCorp Vault.
- **DR regions:** East US 2 (production) and West US 2 (DR).

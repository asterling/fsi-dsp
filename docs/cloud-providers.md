# Cloud Provider Guide

## Overview
The topic/schema/RBAC Terraform module is cloud-agnostic. Differences are in networking, auth, secrets, and backend.

## Azure (Default for FSI)

| Concern | Azure Approach | .env Variable |
|---------|---------------|---------------|
| Private networking | Azure Private Link → Private Endpoint in VNet | `AZURE_VNET_ID`, `AZURE_SUBNET_ID` |
| Private DNS | Private DNS Zone: `privatelink.confluent.cloud` | `AZURE_PRIVATE_DNS_ZONE` |
| Authentication | Azure AD / Entra ID → OAUTHBEARER (eliminates API keys) | `AZURE_TENANT_ID`, `AZURE_CLIENT_ID` |
| Secrets | Azure Key Vault or HashiCorp Vault | `SECRETS_PROVIDER` |
| Terraform state | Azure Blob Storage (`azurerm` backend) | `TF_BACKEND_STORAGE_ACCOUNT` |
| DR regions | East US 2 ↔ West US 2 | `CC_PROD_REGION`, `CC_DR_REGION` |

**OAuth advantage for DR:** Azure AD tokens work against both clusters. No credential swap during failover.

## AWS

| Concern | AWS Approach | Notes |
|---------|-------------|-------|
| Private networking | AWS PrivateLink → VPC Endpoint | AZ ID mapping required |
| Authentication | IAM auth or external IdP via OAUTHBEARER | |
| Secrets | AWS Secrets Manager | Connect has native config provider |
| Terraform state | S3 backend | |
| DR regions | us-east-1 ↔ us-west-2 | |

## GCP

| Concern | GCP Approach | Notes |
|---------|-------------|-------|
| Private networking | Private Service Connect (PSC) | Single IP, manual DNS |
| Authentication | Google Cloud Identity / Workload Identity Federation | |
| Secrets | Google Secret Manager | |
| Terraform state | GCS backend | |
| DR regions | us-east1 ↔ us-west1 | |

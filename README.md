# FSI Kafka Platform

Opinionated, C4E-managed Terraform for Confluent Cloud in regulated financial services.

## What This Is

A ready-to-deploy repository that creates fully governed Kafka topics with one module call: topic + Avro schema + RBAC + metadata tags + DR mirror. Designed for banks, credit unions, and insurance companies running Confluent Cloud.

## Quick Start

1. Copy `.env.example` → `.env` and fill in your CC environment details
2. Copy `environments/prod/terraform.tfvars.example` → `terraform.tfvars`
3. Update `environments/prod/main.tf` locals with your cluster IDs and endpoints
4. Add your topic declarations (copy from `example-topics.tf`)
5. Add your Avro schemas to `schemas/`
6. Submit a PR → CI validates → merge triggers `terraform apply`

## Structure

```
.env.example                 ← Start here: all environment-specific variables
modules/topic/               ← The single Terraform module (do not modify per-engagement)
environments/prod/           ← Topic declarations and environment config
schemas/examples/            ← Example Avro schemas for common FSI entities
docs/
  cloud-providers.md         ← Azure vs AWS vs GCP differences
  schema-guide.md            ← Naming, compatibility, evolution rules
  onboarding.md              ← Self-service flow for new teams
  adr/                       ← Architecture decision records
scripts/                     ← DR failover/failback, Connect pause/resume
reference/
  java-producer/             ← Reference producer (idempotent, Avro, Dynatrace JMX)
  java-consumer/             ← Reference consumer (manual commit, graceful shutdown)
  dotnet-producer/           ← .NET reference (for non-JVM teams)
  dotnet-consumer/
  connect-configs/           ← JDBC source/sink, distributed properties (East/West)
  local-dev/                 ← Docker Compose for local Kafka + SR + Connect
  integration-test/          ← Roundtrip produce-consume verification
.github/                     ← CI/CD pipelines, PR template, issue template
```

## Cloud Support

Tested on Confluent Cloud running on Azure, AWS, and GCP. See `docs/cloud-providers.md` for:
- Private networking (Azure Private Link / AWS PrivateLink / GCP PSC)
- Authentication (Azure AD OAuth / AWS IAM / GCP Workload Identity)
- Secrets management (Vault / Azure Key Vault / AWS Secrets Manager)
- Terraform backend (Azure Blob / S3 / GCS)

## Engagement Customization

1. Set `ORG_PREFIX` in `.env` if topics need an org prefix
2. Choose cloud provider settings (default: Azure)
3. Adjust SLA tier → compatibility/partition/retention mappings in `modules/topic/main.tf`
4. Add client-specific schemas to `schemas/`
5. Write topic declarations in `environments/prod/`

## License

Proprietary — GoodLabs Studio

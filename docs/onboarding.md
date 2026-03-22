# Self-Service Onboarding Guide

## Prerequisites
- Your team has a Confluent Cloud service account (request via C4E intake)
- You have access to the `fsi-kafka-platform` Git repo
- You have your Avro schema (.avsc file) ready

## Steps

### 1. Fill out the intake form
Copy `.github/ISSUE_TEMPLATE/new-topic-request.md` and fill in:
- Domain, application, version, entity
- Owner email, SLA tier, data classification
- PII fields (if any)
- Producer and consumer service account IDs

### 2. Add your schema
Place your `.avsc` file in `/schemas/{domain}-{entity}.avsc`.
Follow the naming conventions in `docs/schema-guide.md`.

### 3. Add your module call
Create or update a `.tf` file in `/environments/prod-east/`:
```hcl
module "your_topic" {
  source      = "../../modules/topic"
  domain      = "your-domain"
  application = "your-app"
  version     = "v1"
  entity      = "your-entity"
  owner       = "your-team@fsi.org"
  sla_tier    = "standard"
  schema_file = "../../schemas/your-domain-your-entity.avsc"
  pii_fields  = []
  producer_service_accounts = ["sa-your-producer"]
  consumer_service_accounts = ["sa-your-consumer"]
  # ... infrastructure refs (copy from existing module call)
}
```

### 4. Submit a PR
The PR template will auto-populate the review checklist.
C4E review target: same business day.

### 5. Merge and verify
After approval, merge triggers `terraform apply`.
Verify: topic exists, schema registered, mirror topic created, RBAC applied.

## Need help?
Post in the `#kafka-cop` Teams channel.

# Schema Governance Guide

## Topic Naming Convention
Format: `{domain}.{application}.{version}.{entity}`

- **domain**: Business domain (lowercase, e.g., `cncb`, `rtfd`, `ofac`, `eventgrid`)
- **application**: App within domain (e.g., `core`, `alerts`, `screening`, `api`)
- **version**: Schema version (e.g., `v1`, `v2`)
- **entity**: The data entity (e.g., `account-transaction`, `fraud-signal`)

## Schema Format
All production topics use **Apache Avro**. See ADR-001 for rationale.

## Compatibility Modes

| SLA Tier    | Mode              | What it means |
|-------------|-------------------|---------------|
| critical    | FULL_TRANSITIVE   | Can only add optional fields with defaults. Cannot remove or rename. |
| standard    | BACKWARD_TRANSITIVE | New schema can read old data. Can add optional fields. |
| best-effort | BACKWARD          | Same as above but only checks against latest version. |

## Schema Evolution Runbook

### Adding a field (safe for all modes)
1. Add the field with a default value: `{"name": "new_field", "type": ["null", "string"], "default": null}`
2. Register the new schema version (Terraform apply)
3. Deploy consumers first (they can handle both old and new), then producers

### Deprecating a field (critical topics)
You **cannot** remove fields from FULL_TRANSITIVE topics. Instead:
1. Stop producing values (set to null/default)
2. Add a `@deprecated` doc annotation
3. Consumers should stop reading the field

### Breaking change (new topic)
If you must make an incompatible change:
1. Create a new topic with an incremented version: `cncb.core.v2.account-transaction`
2. Run both versions in parallel during migration
3. Decommission the old topic after all consumers migrate

## PII Tagging
Fields containing personally identifiable information must be tagged in the schema metadata:
- Add field names to the `pii_fields` variable in the Terraform module call
- The module sets `pii: true` and `pii-fields: field1,field2` in schema metadata
- For encryption, add CEL-based encryption rules in the data contract (requires Advanced Stream Governance)

## Avro Best Practices
- Use `["null", "type"]` union with `"default": null` for optional fields
- Use logical types: `timestamp-millis` for timestamps, `decimal` for money, `date` for dates
- Use enums for closed sets (transaction types, risk categories, channels)
- Use `string` for identifiers (UUIDs, account numbers) — never `long`
- Set `"doc"` on every field — this feeds into Alation catalog descriptions

## Breaking Change Runbook

When you must make an incompatible schema change (field removal, type change,
renaming) on a topic with FULL_TRANSITIVE or BACKWARD_TRANSITIVE compatibility,
follow this 5-step process. **Do not request a compatibility_override** unless
you have exhausted this process and documented the exception in an ADR.

### Step 1: Create Versioned Topic

Create a new topic with the next version using the same Terraform module:

```hcl
module "corebanking_account_txn_v2" {
  source      = "../../modules/topic"
  domain      = "corebanking"
  application = "transactions"
  version     = "v2"                    # Incremented from v1
  entity      = "account-transaction"
  owner       = "core-banking-team@company.com"
  sla_tier    = "critical"
  schema_file = "../../schemas/corebanking/account-transaction-v2.avsc"
  # ... remaining config identical to v1 ...
}
```

Both v1 and v2 topics coexist. v1 continues to operate normally.

### Step 2: Dual-Write Period

Deploy producers that write to BOTH v1 and v2 topics simultaneously.

- **Minimum duration:** 2 business days (allow consumer teams to plan and migrate)
- **Recommended:** 1 sprint (2 weeks) for critical-tier topics
- **Monitoring:** Verify v2 topic is receiving messages at expected throughput via consumer lag metrics

### Step 3: Consumer Migration

Each consumer team:

1. Updates their consumer to read from the v2 topic
2. Deploys to a staging environment and validates deserialization
3. Deploys to production
4. Confirms migration complete to the C4E team via the intake form or PR comment

**Track progress:** Maintain a migration checklist in the PR that adds the v2 topic:

- [ ] Consumer team A migrated (confirmed YYYY-MM-DD)
- [ ] Consumer team B migrated (confirmed YYYY-MM-DD)

### Step 4: Deprecate Old Topic

After ALL consumers confirm migration:

1. Stop producing to v1 topic (remove v1 from producer config)
2. Add `deprecated = true` tag to the v1 Terraform module metadata
3. Set a decommission date: retention period + 30 days buffer
4. Announce deprecation via team communication channel

### Step 5: Decommission

After the decommission date:

1. Verify v1 consumer lag is 0 (no active consumers): `confluent kafka topic consume --from-beginning` should show no new offsets
2. Remove v1 topic module from Terraform configuration
3. Run `terraform apply` to delete the topic and associated RBAC/schema resources
4. Soft-delete the v1 schema subject (optional -- preserves version history for audit):
   `confluent schema-registry subject delete --subject "{topic}-value" --permanent=false`

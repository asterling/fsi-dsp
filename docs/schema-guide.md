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

## New Topic / Schema Change

### Checklist (all required for merge)
- [ ] Avro schema (.avsc) added to /schemas/
- [ ] Terraform module call added to /environments/prod-east/
- [ ] Topic name follows convention: {domain}.{application}.{version}.{entity}
- [ ] owner is a valid team email
- [ ] sla_tier is set (critical / standard / best-effort)
- [ ] PII fields identified in pii_fields list
- [ ] Producer and consumer service accounts listed
- [ ] Schema has doc annotations on all fields
- [ ] terraform plan runs clean

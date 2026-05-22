# Layer 04: Audit Logging

## FSI Rationale

Without audit logging, there is no forensic record of who accessed what, when, and
with what result. In FSI regulated environments:

- **OFAC/AML**: transaction access audit trails must be retained for 7 years and
  reconstructable for regulatory examination (FinCEN, OCC, Federal Reserve requirements)
- **SOX § 302/404**: IT general controls require evidence that access to financial
  systems is logged and reviewed; no logging = reportable control deficiency
- **FFIEC IT Handbook**: event logging is a mandatory security control; audit logs
  must be protected from tampering and available for incident response

**Failure mode without this layer:** no forensic record of access — an insider threat,
credential compromise, or unauthorized configuration change leaves no audit trail.
This is an automatic finding in any SOC 2 Type II, PCI DSS, or bank exam.

## What this layer does

### Captured event categories

| Category | Examples |
|----------|---------|
| Authentication | mTLS handshake success/failure, SASL auth attempts, MDS token validation |
| Authorization | Produce/consume allows and denials, admin operation allows and denials |
| Schema changes | Schema registration, compatibility config changes, hard deletes |
| Topic configuration | Retention changes, partition changes, compaction policy changes |
| ACL/rolebinding changes | ConfluentRolebinding CRUD operations |

### Components

1. **Kafka CR patch** (`patches/kafka-audit.yaml`): sets `confluent.security.event.router.config`
   on a **distinct CR field** (`spec.configOverrides.server`) from layers 01 and 02 to
   avoid JSON-merge patch collisions.

2. **`kafkatopic-audit.yaml`**: pre-creates `confluent-audit-log-events` with:
   - `retention.ms`: overlay-configurable — 7 years (220752000000 ms) in prod,
     30 days (2592000000 ms) in dev
   - `cleanup.policy: delete` (no compaction — compaction suppresses duplicate events)
   - `min.insync.replicas: 2` (durability)

3. **`connect-cr.yaml`**: re-enables Connect (upstream has it commented out) and
   deploys two Sink Connectors:
   - **Splunk Sink** via HEC — routes to `observability/splunk/` dashboards
   - **HTTP Sink → Dynatrace** — routes to `observability/dynatrace/` dashboards
     (no first-party Dynatrace connector; HTTP Sink is the approved workaround —
     see `KNOWN-GAPS.md`)

4. **`siem/`**: cross-references to existing SIEM assets — no duplication (D-03).

## Dependency on layer 01 (RBAC)

The `confluent.security.event.router.config` requires `ConfluentServerAuthorizer`
to be active. Layer 01's `spec.authorization.type: rbac` enables it. Component
ordering in the overlay kustomization (`01-rbac` before `04-audit`) enforces this.

Do not apply layer 04 without layer 01 — the audit router will silently no-op.

## Audit topic protection

The `confluent-audit-log-events` topic is protected by:
- **RBAC** (layer 01): only `auditor-readonly` has `DeveloperRead` on this topic;
  `platform-admin` has `SystemAdmin` which includes write — but this is the only role
  with that level of cluster access
- **min.insync.replicas: 2**: topic write requires 2 of 3 replicas — single-broker
  failure does not cause data loss

## Validation

```bash
bash layers/04-audit/validate-audit.sh
```

Cluster-dependent. Asserts: KafkaTopic CR exists, Connect RUNNING, Splunk Sink RUNNING,
messages present in `confluent-audit-log-events`.

## Cross-references

- `layers/01-rbac/` — RBAC controls that gate access to the audit topic (D-02)
- `observability/splunk/` — Splunk dashboards for audit event visualization
- `observability/dynatrace/` — Dynatrace dashboards
- `KNOWN-GAPS.md` — no native Dynatrace connector; s390x Connect image requirement
- `DESIGN.md` — component ordering rationale (01 before 04)

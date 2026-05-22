# SIEM Integration Reference

This directory points to the existing SIEM assets in this repository.
Per locked decision D-03 (reuse existing assets), dashboards and alert definitions
are NOT duplicated here.

## Splunk

**Dashboard location:** `observability/splunk/`

The Splunk dashboards in `observability/splunk/` include panels for Confluent audit
events. After the Splunk Sink connector (`splunk-audit-sink`) begins delivering events,
import the dashboards from that directory into your Splunk instance.

Key panels:
- Authentication failures over time (detect brute-force/credential stuffing)
- Authorization denials by principal (detect privilege escalation attempts)
- Schema Registry events (detect unauthorized schema deletions)
- Topic configuration changes (detect retention/compaction tampering)
- Rolebinding changes (detect unauthorized RBAC modifications)

## Dynatrace

**Dashboard location:** `observability/dynatrace/`

The Dynatrace dashboards in `observability/dynatrace/` provide similar visibility.
The HTTP Sink connector (`dynatrace-audit-sink`) posts to Dynatrace's generic log
ingest v2 API (`/api/v2/logs/ingest`).

**Important:** There is no first-party Confluent Dynatrace connector. The HTTP Sink
connector is the approved workaround. See `KNOWN-GAPS.md` for the full gap register
entry on this limitation.

After events begin flowing, configure a Dynatrace Log Management attribute extractor
for the `confluent.audit` log source to enable attribute-based dashboarding.

## Alert thresholds

Both SIEM destinations should alert on:

- > 10 authentication failures in 60 seconds from a single principal
- Any `AuthorizationResult: DENIED` for topic `confluent-audit-log-events`
  (audit log tampering attempt)
- Any hard-delete Schema Registry event by a non-`schema-admin` principal
- Any `ConfluentRolebinding` CRUD event outside of a maintenance window

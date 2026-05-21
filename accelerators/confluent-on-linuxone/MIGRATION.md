# x86 → LinuxONE Migration via Cluster Linking

This document wraps Mondics's Cluster Linking pattern (`base/upstream/clusterlink.yaml`)
with FSI-grade procedures for migrating an existing x86 Confluent cluster to IBM
LinuxONE. It covers pre-migration audit posture verification, in-flight data validation,
rollback, and post-migration evidence collection for regulatory review.

Cross-reference: `docs/adr/005-cluster-linking-over-mrc.md` (why Cluster Linking
over MirrorMaker 2 / Multi-Region Clusters for Confluent-to-Confluent migration).

---

## Section 1: Pre-Migration Audit Checklist

Run this checklist on the **source (x86) cluster** before establishing the Cluster Link.
A control gap on the source will propagate to the destination — validate both ends.

### 1.1 RBAC posture

```bash
# List all role bindings — look for overly broad SystemAdmin grants
confluent iam rbac role-binding list --kafka-cluster-id <SOURCE_CLUSTER_ID>

# Verify no wildcard DeveloperRead bindings exist (would expose all topics to auditor)
confluent iam rbac role-binding list \
  --kafka-cluster-id <SOURCE_CLUSTER_ID> \
  --role DeveloperRead | grep -v "PREFIXED\|LITERAL"
```

Expected: no wildcard role bindings; `auditor-readonly` scoped to `_confluent-audit-log-events` only.

### 1.2 TLS posture on source cluster

```bash
# Verify source cluster uses TLS 1.2+ (not 1.0/1.1)
openssl s_client -connect <SOURCE_BOOTSTRAP>:9092 2>&1 | grep -E "Protocol|Cipher"
```

Expected: `Protocol: TLSv1.3` or `TLSv1.2`. If TLS 1.0/1.1 is present, remediate
before migration — traffic in transit during the link would use the weaker protocol.

### 1.3 Schema governance on source

```bash
# Check source SR global compatibility
curl -sf -u <SR_USER>:<SR_PASS> \
  https://<SOURCE_SR_URL>/config | jq -r '.compatibility'
```

Expected: `FULL_TRANSITIVE` or at minimum `BACKWARD`. If `NONE`, schemas may exist
that are incompatible with destination consumers — enumerate and remediate before linking.

### 1.4 Audit log coverage on source

```bash
# Verify _confluent-audit-log-events exists and has recent events
confluent kafka topic consume _confluent-audit-log-events \
  --bootstrap <SOURCE_BOOTSTRAP> \
  --from-beginning \
  --timeout-ms 5000 | wc -l
```

Expected: > 0 messages (source must have audit logging before migration or the
pre-migration audit trail will be incomplete).

### 1.5 Regulatory data scope

Document the following before migration:

- [ ] Topic list with retention policies (identify topics with >1y retention)
- [ ] Schema subjects in scope (export: `GET /subjects`)
- [ ] Active consumer groups and committed offsets (will not migrate via Cluster Linking)
- [ ] Active transactional producers (must be quiesced before cutover)

---

## Section 2: Cluster Link Establishment and In-Flight Data Validation

### 2.1 Apply the Cluster Link manifest

After running `base/fetch-upstream.sh`, the Cluster Linking CR is in
`base/upstream/clusterlink.yaml`. Update the source cluster endpoints before applying:

```bash
# Update source cluster endpoint in clusterlink.yaml
# Then apply — kustomize build already includes this resource via base/kustomization.yaml
kustomize build overlays/prod | oc apply -f - -n confluent
```

### 2.2 Monitor mirror lag

Mirror lag is the primary health indicator. Target: lag < 1 minute sustained; cut over
when lag → 0 ms.

```bash
# Check mirror lag per topic
confluent kafka mirror describe \
  --link <LINK_NAME> \
  --cluster <DESTINATION_CLUSTER_ID>
```

Expected output includes `MirrorLag: 0` for all topics in scope.

### 2.3 Record-count parity

Before cutover, verify producer → consumer round-trip count matches between clusters:

```bash
# Source: get end offset for each topic
confluent kafka topic describe <TOPIC_NAME> \
  --bootstrap <SOURCE_BOOTSTRAP> | grep "End Offset"

# Destination: get end offset for the mirrored topic
confluent kafka topic describe <TOPIC_NAME> \
  --bootstrap <DESTINATION_BOOTSTRAP> | grep "End Offset"
```

Expected: end offsets are equal (or within a few messages if producers are still active).

### 2.4 Schema parity

Export and compare schema subjects between source and destination:

```bash
# Source schemas
curl -sf -u <SR_USER>:<SR_PASS> \
  https://<SOURCE_SR_URL>/subjects > /tmp/source-subjects.json

# Destination schemas
curl -sf -u <SR_USER>:<SR_PASS> \
  https://<DEST_SR_URL>/subjects > /tmp/dest-subjects.json

diff /tmp/source-subjects.json /tmp/dest-subjects.json
```

Expected: no diff. Schema Registry DOES NOT replicate via Cluster Linking — schemas
must be migrated separately using the SR migration tool or the Cluster Linking
schema sync feature (CP 8.2+ with Schema Registry Cluster Linking).

### 2.5 Cutover: quiesce producers, promote mirrors

```bash
# 1. Stop all producers writing to source cluster (coordinate with app teams)

# 2. Wait for mirror lag → 0
confluent kafka mirror describe --link <LINK_NAME> --cluster <DESTINATION_CLUSTER_ID>

# 3. Promote all mirror topics to writable on destination
confluent kafka mirror promote \
  --link <LINK_NAME> \
  --topics <COMMA_SEPARATED_TOPIC_LIST> \
  --cluster <DESTINATION_CLUSTER_ID>

# 4. Point consumer groups to destination bootstrap endpoint (update Consul KV or app config)
# Via Consul KV (canonical pattern per ADR-003):
consul kv put fsi/kafka/active-region linuxone
consul kv put fsi/kafka/bootstrap <DESTINATION_BOOTSTRAP>

# 5. Restart consumers against destination cluster
# 6. Verify consumer group lag = 0 on destination
confluent kafka consumer group describe <GROUP_NAME> \
  --bootstrap <DESTINATION_BOOTSTRAP>
```

---

## Section 3: Rollback Procedure

If issues are detected after cutover, rollback within the RTO window (documented
in your DR plan; typically 15-30 minutes before transactional state diverges).

### 3.1 Stop producers on destination

Coordinate with application teams to stop all producers writing to LinuxONE cluster.

### 3.2 Re-point consumers to source

```bash
# Restore source cluster in Consul KV (if using service discovery)
consul kv put fsi/kafka/active-region x86
consul kv put fsi/kafka/bootstrap <SOURCE_BOOTSTRAP>

# Or update application config and restart consumer instances
```

### 3.3 Demote mirrored topics on destination

```bash
# Pause the Cluster Link to stop replication
confluent kafka mirror pause \
  --link <LINK_NAME> \
  --cluster <DESTINATION_CLUSTER_ID>

# If the promotion was completed, reverse-replicate:
# Create a new Cluster Link from destination (LinuxONE) back to source (x86)
# and let it catch up on any events produced to LinuxONE during the window.
```

### 3.4 Validate source cluster is receiving traffic

```bash
# Confirm new messages are landing on source topics
confluent kafka topic tail <TOPIC_NAME> --bootstrap <SOURCE_BOOTSTRAP>
```

### 3.5 Document rollback event

Log the rollback with:
- Timestamp of cutover
- Timestamp of rollback decision
- Event volume produced to destination during the window
- Root cause (preliminary — full RCA within 5 business days per FSI incident policy)

---

## Section 4: Post-Migration Evidence Collection

Regulatory evidence is required to demonstrate the migration met data integrity and
security controls. Collect and archive the following.

### 4.1 Mirror lag log

Export the complete mirror lag timeline from the Confluent Cloud/CP UI or CLI:

```bash
confluent kafka mirror describe \
  --link <LINK_NAME> \
  --cluster <DESTINATION_CLUSTER_ID> \
  --output json > /tmp/migration-evidence/mirror-lag-at-cutover.json
```

Target: lag = 0 ms at time of cutover. If lag was non-zero, document the data window
and confirm all records arrived post-promotion (end-offset comparison).

### 4.2 Record-count comparison

Archive the end-offset comparison from Section 2.3:

```bash
confluent kafka topic list --bootstrap <SOURCE_BOOTSTRAP> --output json \
  > /tmp/migration-evidence/source-topics.json

confluent kafka topic list --bootstrap <DESTINATION_BOOTSTRAP> --output json \
  > /tmp/migration-evidence/dest-topics.json
```

### 4.3 Audit log continuity verification

Confirm `_confluent-audit-log-events` on the destination cluster received events
throughout the migration window:

```bash
# Consume audit events in the migration time range and export
confluent kafka topic consume _confluent-audit-log-events \
  --bootstrap <DESTINATION_BOOTSTRAP> \
  --from-beginning \
  --print-key \
  --timeout-ms 30000 \
  > /tmp/migration-evidence/audit-events-migration-window.jsonl
```

### 4.4 RBAC posture comparison

Document that RBAC controls on the destination match the source (no role creep
during migration):

```bash
confluent iam rbac role-binding list \
  --kafka-cluster-id <DESTINATION_CLUSTER_ID> \
  --output json \
  > /tmp/migration-evidence/dest-rbac-bindings.json
```

### 4.5 Schema parity confirmation

Document that all subjects migrated successfully:

```bash
diff /tmp/source-subjects.json /tmp/dest-subjects.json \
  > /tmp/migration-evidence/schema-parity-diff.txt || true

# Expected: empty diff file
```

### 4.6 Archive evidence package

```bash
tar czf migration-evidence-$(date +%Y%m%d).tar.gz /tmp/migration-evidence/
# Store in your regulatory evidence management system (GRC tool, SharePoint, etc.)
# Retain for minimum 7 years (OFAC/AML requirement) or per your FI's retention schedule
```

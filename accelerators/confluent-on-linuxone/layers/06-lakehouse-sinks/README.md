# Layer 06: Lakehouse Sinks

## FSI Rationale

FSI risk, compliance, and ML teams consume Kafka topics from a downstream
lakehouse — Databricks (Delta / Unity Catalog) or Snowflake — for analytics,
model training, and regulatory reporting. Without a sanctioned, governed
path each business unit invents its own: ad-hoc Connect clusters in random
namespaces, hardcoded credentials in connector JSON, no DLQ, no observability.

**Failure mode without this layer:** the audit trail of "how data got from
Kafka to the lakehouse" is fragmented across business units; PII handling is
inconsistent; schema drift between Kafka and the lakehouse creates silent
data quality regressions; credential exposure incidents become an
existential risk in regulated environments.

## What this layer does

Implements the DB-C (Databricks Delta Lake Sink) and SF-A (Snowflake Snowpipe
Streaming) self-managed paths from
[ADR-011](../../../../docs/adr/011-lakehouse-integration-patterns.md) on CFK
on OCP on LinuxONE (s390x).

### Components

1. **`kafkatopic-lakehouse-dlq.yaml`**: pre-creates per-sink DLQ topics
   (`lakehouse.dlq.databricks-*`, `lakehouse.dlq.snowflake-*`) with
   `min.insync.replicas=2` and 7-day retention. Overlay can extend.

2. **`connect-cr.yaml`**: deploys a dedicated `connect-lakehouse` Connect
   cluster (separate from the layer-04 audit Connect for operational
   isolation) plus two `Connector` CRs:
   - **Databricks Delta Lake Sink** — pure-Java JAR, runs unchanged on s390x
   - **Snowflake Snowpipe Streaming Sink** — same; `SNOWPIPE_STREAMING`
     ingestion method (sub-second latency)

3. **`rolebindings.yaml`**: MDS `ConfluentRolebinding` CRs for the
   `lakehouse-sink-connector` principal — source topic read, DLQ write,
   consumer group read, SR subject read. Requires layer 01-rbac.

4. **`service-accounts.yaml`**: Kubernetes SA for pod identity (not Kafka
   auth; Kafka uses mTLS via layer 02-tls).

5. **`secrets.template.yaml`**: pointer/template documenting the
   `lakehouse-creds` Secret contract. The actual Secret is reconciled by
   Vault-Agent or External Secrets Operator — not committed (per the
   bug_018 fix pattern).

### Architecture-neutral JAR, s390x-required Connect base image

Both the Databricks Delta Lake Sink and Snowflake Sink JARs are pure Java.
They run on s390x without recompilation. **What must be s390x is the
Connect base image** — the JVM is what executes the JAR. Build:

```bash
docker buildx build --platform linux/s390x \
  --tag <registry>/fsi-cp-connect-lakehouse:7.6.0 \
  -f scenarios/cfk-openshift/connectors/Dockerfile.lakehouse .
```

Then substitute `<PLACEHOLDER_S390X_CONNECT_LAKEHOUSE_IMAGE>` in
`connect-cr.yaml` with the resulting image reference.

## Dependencies on prior layers

| Layer | Required for | What breaks without it |
|---|---|---|
| 01-rbac | MDS authorizer + ConfluentRolebinding CRD | Sink connector cannot read source topic — auth deny |
| 02-tls | cert-manager + confluent-ca-issuer; `connect-lakehouse-tls` Secret | Connect-to-broker mTLS fails; no SR connectivity |
| 03-schema-governance | Schema Registry + governed subjects | AvroConverter cannot resolve schema by ID |

Layer 06 does **not** depend on 04-audit or 05-flink. It is appended after
05 in the overlay; ordering preserves layer independence.

Add to `overlays/prod/kustomization.yaml`:

```yaml
components:
  - ../../layers/01-rbac
  - ../../layers/02-tls
  - ../../layers/03-schema-governance
  - ../../layers/04-audit
  - ../../layers/05-flink
  - ../../layers/06-lakehouse-sinks   # <-- new
```

## Why a dedicated connect-lakehouse cluster

Splitting from the layer-04 `connect` cluster:

- **Failure isolation** — a Databricks outage causing connector restart loops
  must not back up the audit pipeline (compliance SLAs)
- **Image isolation** — lakehouse JARs ≈ 200MB; baking them into the audit
  image bloats unrelated pulls
- **Tuning** — lakehouse sinks tune for throughput (large `buffer.size.bytes`,
  multi-task parallelism); audit sinks tune for low-overhead event shipping

## Validation

```bash
# 1. Manifests assemble cleanly
kustomize build accelerators/confluent-on-linuxone/overlays/prod | \
  yq 'select(.kind == "Connector" and (.metadata.labels."fsi.io/sink-type" // "" | contains("lakehouse")))' | \
  head -100

# 2. Apply
oc apply -k accelerators/confluent-on-linuxone/overlays/prod

# 3. Connect-lakehouse cluster reaches READY
oc get connect -n confluent connect-lakehouse

# 4. Both connectors reach RUNNING
oc get connector -n confluent \
  -l fsi.io/part-of=fsi-kafka-platform,fsi.io/sink-type | \
  grep -E "(databricks|snowflake)"

# 5. DLQ topics exist
oc get kafkatopic -n confluent -l fsi.io/dlq-for
```

## Observability

The connect-lakehouse cluster inherits the platform JMX exporter config; the
lakehouse-specific Grafana dashboards
(`observability/grafana/dashboard-lakehouse-sink-{databricks,snowflake}.json`)
auto-discover connectors by name pattern (`lakehouse-*`).

## Cross-references

- [ADR-011](../../../../docs/adr/011-lakehouse-integration-patterns.md) — decision
- [databricks-integration-guide.md](../../../../docs/databricks-integration-guide.md) — DB-A and DB-C
- [snowflake-integration-guide.md](../../../../docs/snowflake-integration-guide.md) — SF-A and SF-B
- [tableflow-guide.md](../../../../docs/tableflow-guide.md) — CC-only availability
- `layers/01-rbac/` — MDS authorizer
- `layers/02-tls/` — cert-manager and TLS material
- `layers/04-audit/` — sibling Connect cluster pattern (operational isolation rationale)
- `KNOWN-GAPS.md` — s390x Connect base image requirement

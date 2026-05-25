# CFK Connector CRs — Lakehouse Sinks

Self-managed Databricks Delta and Snowflake Snowpipe sinks for CFK on
OpenShift. These manifests implement the DB-C and SF-A self-managed paths
from [ADR-011](../../../docs/adr/011-lakehouse-integration-patterns.md).

| File | Purpose |
|---|---|
| `databricks-delta-sink.yaml` | DB-C: Databricks Delta Lake Sink Connector CR |
| `snowflake-snowpipe-sink.yaml` | SF-A: Snowflake Snowpipe Streaming Sink Connector CR |

## Prerequisites

### 1. Connector JARs in the Connect image

The base Confluent Connect image does not include these connectors. Build a
custom image:

```dockerfile
FROM confluentinc/cp-server-connect:7.6.0

USER root
RUN confluent-hub install --no-prompt \
      confluentinc/kafka-connect-databricks-delta-lake-sink:latest && \
    confluent-hub install --no-prompt \
      snowflakeinc/snowflake-kafka-connector:latest
USER 1000
```

Reference the resulting image in your `scenarios/cfk-openshift/values/connect.yaml`:

```yaml
connect:
  image:
    application: <your-registry>/fsi-cp-connect-lakehouse:7.6.0
```

For the LinuxONE-specific s390x build, see
`accelerators/confluent-on-linuxone/layers/06-lakehouse-sinks/connect-cr.yaml`.

### 2. Secrets mounted at /mnt/secrets/lakehouse/

The Connect cluster needs the lakehouse credential files mounted. Add to
your Connect CR:

```yaml
connect:
  mountedSecrets:
    - secretRef: lakehouse-databricks-creds
      keyItems:
        - key: token
          path: lakehouse/databricks
        - key: s3_access_key_id
          path: lakehouse/databricks
        - key: s3_secret_access_key
          path: lakehouse/databricks
    - secretRef: lakehouse-snowflake-creds
      keyItems:
        - key: private_key
          path: lakehouse/snowflake
        - key: private_key_passphrase
          path: lakehouse/snowflake
    - secretRef: lakehouse-sr-creds
      keyItems:
        - key: user_info
          path: lakehouse/sr
```

The actual Secret objects are populated by Vault-Agent on-cluster (or by
External Secrets Operator). They are **not committed to the repo** —
cert-manager owns TLS, Vault-Agent owns app credentials.

### 3. Placeholder substitution

Each manifest contains `<PLACEHOLDER_*>` tokens. Substitute via your
GitOps tooling (ArgoCD/Flux Kustomize patches, or `envsubst` before apply)
with values from your environment:

| Placeholder | Source |
|---|---|
| `<PLACEHOLDER_DATABRICKS_WORKSPACE_URL>` | Databricks workspace URL |
| `<PLACEHOLDER_DATABRICKS_STAGING_BUCKET>` | S3 bucket for Delta staging |
| `<PLACEHOLDER_SNOWFLAKE_ACCOUNT_URL>` | Snowflake account URL |

### 4. DLQ topics

The DLQ topics referenced by these connectors are not created automatically.
Provision them via `modules/topic/` (CC) or KafkaTopic CR (CFK) before
applying these manifests.

## Apply

```bash
# Apply to a CFK cluster with the lakehouse image already deployed
oc apply -f databricks-delta-sink.yaml
oc apply -f snowflake-snowpipe-sink.yaml

# Verify both connectors reach RUNNING
oc get connector -n confluent \
  -l app.kubernetes.io/part-of=fsi-kafka-platform
oc describe connector lakehouse-databricks-corebanking-account-txn -n confluent
```

Expected: `STATUS: RUNNING`, all tasks `RUNNING`. If any task is FAILED,
check the Connect worker logs:

```bash
oc logs -n confluent -l app=connect --tail=200 | grep -i lakehouse
```

## Observability

The CFK Connect cluster already exposes JMX metrics via the platform's
`jmx-exporter-config.yaml`. The lakehouse-specific Grafana dashboards at
`observability/grafana/dashboard-lakehouse-sink-{databricks,snowflake}.json`
pick up the new connectors automatically by name pattern (`lakehouse-*`).

# Lakehouse Sink Connector Configs

Reference JSON for the self-managed paths from ADR-011:

| File | Path | Connector class |
|---|---|---|
| `databricks-delta-sink-example.json` | DB-C self-managed | `io.confluent.connect.databricks.DatabricksDeltaLakeSinkConnector` |
| `snowflake-snowpipe-sink-example.json` | SF-A self-managed | `com.snowflake.kafka.connector.SnowflakeSinkConnector` |

These configs target the **self-managed** Connect cluster used by CP on RHEL,
CFK on OpenShift, and the LinuxONE variants. For CC-managed equivalents, use
the `modules/lakehouse_sink/` Terraform module (`environments/prod/lakehouse_sinks.tf`).

## Connector JAR installation

The Databricks Delta Lake Sink and Snowflake Sink JARs are not bundled with
the base CP Connect distribution. Install them into the Connect worker
plugin path before deploying these configs.

### CP on RHEL / RHEL on LinuxONE

```bash
# Databricks Delta Lake Sink
confluent-hub install \
  --no-prompt \
  --component-dir /opt/kafka-connect/plugins \
  --worker-configs /etc/kafka-connect/connect-distributed.properties \
  confluentinc/kafka-connect-databricks-delta-lake-sink:latest

# Snowflake Sink (community / Snowflake-published)
confluent-hub install \
  --no-prompt \
  --component-dir /opt/kafka-connect/plugins \
  --worker-configs /etc/kafka-connect/connect-distributed.properties \
  snowflakeinc/snowflake-kafka-connector:latest

systemctl restart confluent-kafka-connect
```

Both JARs are pure Java and run unchanged on s390x.

### CFK on OpenShift

The connector JARs are baked into a custom Connect image. See:
- `scenarios/cfk-openshift/connectors/README.md` for the stock build
- `accelerators/confluent-on-linuxone/layers/06-lakehouse-sinks/connect-cr.yaml`
  for the s390x build

## Deployment

### Via Ansible (CP / CP on RHEL on L1)

```bash
ansible-playbook -i ansible/inventories/prod \
  ansible/playbooks/deploy-lakehouse-sinks.yml \
  --tags databricks      # or --tags snowflake, or both
```

The playbook reads `ansible/vars/lakehouse-connectors-example.yml` (copy and
edit) and applies via the `cp_databricks_sink` and `cp_snowflake_sink` roles.

### Via Connect REST (manual or CI)

```bash
curl -X PUT \
  -H "Content-Type: application/json" \
  --data @databricks-delta-sink-example.json \
  https://connect.fsi.internal:8083/connectors/lakehouse-databricks-corebanking-account-txn/config
```

### Via Kustomize (CFK on OCP on LinuxONE)

```bash
oc apply -k accelerators/confluent-on-linuxone/overlays/prod
```

## Secret patterns

All credentials use the platform-standard Vault interpolation
`${vault:secret/fsi/<system>#<field>}`. Vault paths used by these configs:

| Path | Used by |
|---|---|
| `secret/fsi/databricks#token` | Databricks PAT |
| `secret/fsi/snowflake#private_key` | Snowflake RSA private key (PEM body) |
| `secret/fsi/snowflake#private_key_passphrase` | Passphrase if the private key is encrypted |
| `secret/fsi/aws-databricks-staging#access_key_id` | S3 staging bucket for Databricks |
| `secret/fsi/aws-databricks-staging#secret_access_key` | S3 staging bucket for Databricks |
| `secret/fsi/sr#api_key` | Schema Registry API key (already in use platform-wide) |
| `secret/fsi/sr#api_secret` | Schema Registry API secret |

On LinuxONE deployments where Vault is unreachable from the closed z/IRD
network, credentials are loaded from a JCEKS keystore — see
`scenarios/cp-rhel-linuxone/group_vars/lakehouse.yml`.

## DLQ topics

Each sink writes errors to a per-sink DLQ topic named
`lakehouse.dlq.<connector-name>`. The DLQ topic must exist before the
connector starts; the platform default is `sla_tier = best-effort` (3
partitions, 7-day retention). Provision via:

```hcl
module "databricks_dlq" {
  source         = "../../modules/topic"
  domain         = "lakehouse"
  application    = "dlq"
  schema_version = "v1"
  entity         = "databricks-corebanking-account-txn"
  owner          = "platform-team@fsi.org"
  sla_tier       = "best-effort"
  schema_file    = "../../schemas/examples/dlq-envelope.avsc"
  # ...infra refs
}
```

For CC-managed sinks the DLQ is provisioned automatically by
`modules/lakehouse_sink/`.

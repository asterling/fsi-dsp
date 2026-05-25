# Tableflow Guide

Tableflow is the Confluent Cloud feature that materializes a Kafka topic to
object storage as an Iceberg or Delta table. It is the foundation of the
"zero-copy" lakehouse integration paths — DB-A (Databricks) and SF-B
(Snowflake).

This guide is the canonical answer to: *"Can I use Tableflow on CFK?
On CP? On LinuxONE?"*

---

## Availability matrix (2026-05)

| Deployment model | Tableflow available? | Recommendation |
|---|---|---|
| Confluent Cloud (AWS) | ✅ | Use DB-A or SF-B for lakehouse integration |
| Confluent Cloud (Azure) | ✅ | Use DB-A or SF-B |
| Confluent Cloud (GCP) | ✅ | Use DB-A or SF-B |
| Confluent Private Cloud | ❌ | Use DB-C / SF-A |
| Confluent for Kubernetes (OCP) | ❌ | Use DB-C / SF-A |
| Confluent Platform on RHEL | ❌ | Use DB-C / SF-A |
| CFK on OCP on LinuxONE | ❌ | Use DB-C / SF-A |
| CP on RHEL on LinuxONE | ❌ | Use DB-C / SF-A |

Tableflow is a **managed service**, not a software package. There is no
Helm chart, RPM, or container image. It will not appear on CP, CFK, or
LinuxONE through any installation path.

---

## When customers ask "is Tableflow Anywhere coming"

Confluent has not announced a portable Tableflow product as of 2026-05.
The closest off-Cloud equivalent today is:

- **Iceberg sink via Kafka Connect** (community Iceberg sink connector) +
  a customer-managed REST catalog (Polaris, Nessie). This is *not*
  Tableflow — it is a build-it-yourself stack with substantially more
  operational surface area. The platform does not ship this pattern by
  default.

If a customer needs an open table format on-prem, the platform
recommendation is:

1. Ship Kafka → on-prem object storage (MinIO, S3-compatible) via the
   S3 Sink Connector with Parquet output.
2. Register an Iceberg table over those Parquet files using an out-of-band
   Iceberg catalog.

This is documented separately. It is not in scope for ADR-011.

---

## Provisioning Tableflow via Terraform

```hcl
module "corebanking_tableflow_databricks" {
  source = "../../modules/tableflow"

  source_topic_name = module.corebanking_account_txn.topic_name
  storage_format    = "DELTA"
  catalog_target    = "unity-catalog"

  databricks_workspace_endpoint  = "https://adb-1234567890.123.azuredatabricks.net"
  databricks_catalog_name        = "fsi_prod"
  databricks_oauth_client_id     = "$${vault:secret/fsi/databricks-uc-oauth#client_id}"
  databricks_oauth_client_secret = "$${vault:secret/fsi/databricks-uc-oauth#client_secret}"

  tableflow_bucket_name             = var.tableflow_bucket_name
  tableflow_provider_integration_id = var.tableflow_provider_integration_id

  environment_id       = var.environment_id
  kafka_cluster_id     = local.infra.kafka_cluster_id
  tableflow_api_key    = var.tableflow_api_key
  tableflow_api_secret = var.tableflow_api_secret
}
```

Variables of note:

- `storage_format`: `ICEBERG` (default) or `DELTA`. Iceberg works with both
  Databricks (via Delta UniForm) and Snowflake. Delta is Databricks-only.
- `catalog_target`: `unity-catalog`, `snowflake-horizon`, or `none` (raw
  table in storage; query via your own catalog).
- Catalog auth is **OAuth client credentials** for both Unity Catalog and
  Snowflake Open Catalog — see the module README. Databricks PAT and
  Snowflake RSA key-pair are used by the sink connectors (DB-C / SF-A),
  not by Tableflow's catalog integration.
- Materialization cadence is controlled by Confluent Cloud (typically
  60–120 seconds); it is not a module input.

## DR considerations

Tableflow on a cluster that is the source side of a Cluster Link continues
to materialize from that cluster. On regional failover (promotion of the
West DR cluster), Tableflow materialization either:

- Continues from the now-primary cluster if Tableflow is enabled on the
  same topic on both East and West, or
- Stops on East and must be enabled on West manually if Tableflow was only
  configured on East.

The platform default — set in `modules/tableflow/main.tf` — is to enable
Tableflow on the production (East) topic only. DR failover therefore
requires a Terraform apply against West to resume materialization. This
is documented in `docs/dr-runbook.md`.

## CSFLE interaction

If the source topic has `data_classification = "confidential"`, the
materialized rows in Iceberg/Delta contain the *encrypted* field values.
Downstream readers (Databricks, Snowflake) need access to the same KEK to
decrypt. The platform supports this for AWS KMS, Azure Key Vault, GCP KMS,
and HCVault — see [csfle-guide.md](csfle-guide.md).

## Cost notes

Tableflow billing line items appear under the CC account:

- Materialization throughput (per GB processed)
- Storage (per GB-month in Tableflow-managed object storage)
- Catalog API calls (per million catalog requests)

There is no per-Connect-worker cost (none are deployed). Compare against
DB-C / SF-A which charge for Connect workers (CC-managed) or self-hosted
worker compute.

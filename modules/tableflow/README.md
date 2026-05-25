# `modules/tableflow`

Enables Confluent Tableflow on a topic and wires the materialized table into
a downstream catalog (Unity Catalog for Databricks, Snowflake Open Catalog
for Snowflake).

> **Tableflow is a Confluent Cloud-only feature.** This module will not work
> against CP, CFK, or LinuxONE deployments. See
> [tableflow-guide.md](../../docs/tableflow-guide.md) for the availability
> matrix and the DB-C / SF-A fallback paths.

> **Catalog auth note.** Both Unity Catalog and Snowflake Open Catalog
> integrations use OAuth `client_id` + `client_secret` per the
> `confluent_catalog_integration` provider schema — **not** Databricks PAT
> or Snowflake RSA key-pair. The latter are used by the sink connectors
> in `modules/lakehouse_sink/`. The two credential sets are different
> by design: catalog auth is service-principal-OAuth (read/write table
> metadata); sink connector auth is workload-identity (write rows).

## Usage

### DB-A: Tableflow → Databricks Unity Catalog

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

  tableflow_bucket_name             = "fsi-kafka-tableflow-prod-east"
  tableflow_provider_integration_id = local.infra.tableflow_provider_integration_id

  environment_id       = local.infra.environment_id
  kafka_cluster_id     = local.infra.kafka_cluster_id
  tableflow_api_key    = var.tableflow_api_key
  tableflow_api_secret = var.tableflow_api_secret
}
```

### SF-B: Tableflow → Snowflake Open Catalog

```hcl
module "fraud_tableflow_snowflake" {
  source = "../../modules/tableflow"

  source_topic_name = module.fraud_alert_signal.topic_name
  storage_format    = "ICEBERG"
  catalog_target    = "snowflake-horizon"

  snowflake_open_catalog_endpoint = "https://abc12345.snowflakecomputing.com/open-catalog"
  snowflake_warehouse             = "FSI_KAFKA_WH"
  snowflake_allowed_scope         = "PRINCIPAL_ROLE:fsi_kafka_ingest"
  snowflake_oauth_client_id       = "$${vault:secret/fsi/snowflake-oc-oauth#client_id}"
  snowflake_oauth_client_secret   = "$${vault:secret/fsi/snowflake-oc-oauth#client_secret}"

  tableflow_bucket_name             = "fsi-kafka-tableflow-prod-east"
  tableflow_provider_integration_id = local.infra.tableflow_provider_integration_id

  environment_id       = local.infra.environment_id
  kafka_cluster_id     = local.infra.kafka_cluster_id
  tableflow_api_key    = var.tableflow_api_key
  tableflow_api_secret = var.tableflow_api_secret
}
```

## storage_format selection

| Format | Databricks | Snowflake | Trino / Spark / Athena |
|---|---|---|---|
| `ICEBERG` (default) | ✅ via Delta UniForm | ✅ native | ✅ native |
| `DELTA` | ✅ native | ❌ | partial |

Default to `ICEBERG` unless you need Delta-native features (Delta Sharing,
Liquid Clustering) and your only target is Databricks.

## catalog_target selection

| `catalog_target` | Effect |
|---|---|
| `unity-catalog` | Creates a `confluent_catalog_integration` with a `unity { ... }` block so the table appears in Databricks |
| `snowflake-horizon` | Creates a `confluent_catalog_integration` with a `snowflake { ... }` block (Snowflake Open Catalog / Horizon) |
| `none` | No catalog integration; consumers query the underlying storage directly via their own catalog |

## Prerequisites not handled by this module

- **BYOB storage**: the S3 bucket and the CC provider integration (IAM role
  / service principal) must be created out-of-band. The provider
  integration ID is passed as `tableflow_provider_integration_id`. Azure
  ADLS Gen2 is also supported by the provider but not wired into this
  module; copy `byob_aws` to `azure_data_lake_storage_gen_2` if needed.
- **OAuth client credentials**: for Unity Catalog, create a Databricks
  service principal and OAuth secret. For Snowflake, configure an
  external OAuth integration and a security integration scope.
- **Tableflow service account + API key**: pass via `tableflow_api_key` /
  `_secret`. The SA needs the `TableflowAdmin` role.

## DR considerations

The platform default is to enable Tableflow on the production (East) topic
only. On regional failover (cluster link promotion), materialization
continues from the now-primary cluster only if Tableflow has been enabled
on West as well. See `docs/dr-runbook.md` for the failover sequence.

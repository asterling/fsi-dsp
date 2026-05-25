# =============================================================================
# Tableflow Declarations -- CC-only zero-copy materialization
# =============================================================================
# Tableflow materializes topics to managed Iceberg/Delta storage and wires
# the result into Unity Catalog (Databricks) or Snowflake Open Catalog. No
# Connect workers are deployed; cadence is minute-scale.
#
# CC-ONLY FEATURE. For CP/CFK/LinuxONE sources, fall back to the sink
# connector approach in lakehouse_sinks.tf.
#
# Catalog auth: both Unity Catalog and Snowflake Open Catalog integrations
# use OAuth client credentials per the confluent_catalog_integration provider
# schema. Databricks PAT and Snowflake RSA key-pair are NOT used for the
# catalog integration itself (those are used by the sink connectors).
# =============================================================================

# ---------------------------------------------------------------------------
# DB-A: Corebanking topic -> Databricks Unity Catalog (Delta UniForm)
# ---------------------------------------------------------------------------
module "corebanking_tableflow_databricks" {
  source = "../../modules/tableflow"

  source_topic_name = module.corebanking_account_txn.topic_name
  storage_format    = "DELTA"
  catalog_target    = "unity-catalog"

  databricks_workspace_endpoint  = var.databricks_workspace_url
  databricks_catalog_name        = "fsi_prod"
  databricks_oauth_client_id     = var.databricks_oauth_client_id
  databricks_oauth_client_secret = var.databricks_oauth_client_secret

  tableflow_bucket_name             = var.tableflow_bucket_name
  tableflow_provider_integration_id = var.tableflow_provider_integration_id

  environment_id       = var.environment_id
  kafka_cluster_id     = local.infra.kafka_cluster_id
  tableflow_api_key    = var.tableflow_api_key
  tableflow_api_secret = var.tableflow_api_secret
}

# ---------------------------------------------------------------------------
# SF-B: Fraud topic -> Snowflake Open Catalog (Iceberg)
# ---------------------------------------------------------------------------
module "fraud_tableflow_snowflake" {
  source = "../../modules/tableflow"

  source_topic_name = module.fraud_alert_signal.topic_name
  storage_format    = "ICEBERG"
  catalog_target    = "snowflake-horizon"

  snowflake_open_catalog_endpoint = var.snowflake_open_catalog_endpoint
  snowflake_warehouse             = "FSI_KAFKA_WH"
  snowflake_allowed_scope         = "PRINCIPAL_ROLE:fsi_kafka_ingest"
  snowflake_oauth_client_id       = var.snowflake_oauth_client_id
  snowflake_oauth_client_secret   = var.snowflake_oauth_client_secret

  tableflow_bucket_name             = var.tableflow_bucket_name
  tableflow_provider_integration_id = var.tableflow_provider_integration_id

  environment_id       = var.environment_id
  kafka_cluster_id     = local.infra.kafka_cluster_id
  tableflow_api_key    = var.tableflow_api_key
  tableflow_api_secret = var.tableflow_api_secret
}

# ---------------------------------------------------------------------------
# Tableflow-specific variables (sensitive auth + storage/catalog references)
# ---------------------------------------------------------------------------
variable "tableflow_api_key" {
  description = "API key for an SA holding the TableflowAdmin role"
  type        = string
  sensitive   = true
}

variable "tableflow_api_secret" {
  description = "API secret for the TableflowAdmin SA"
  type        = string
  sensitive   = true
}

variable "tableflow_bucket_name" {
  description = "S3 bucket backing Tableflow materialized storage"
  type        = string
}

variable "tableflow_provider_integration_id" {
  description = "CC provider integration ID referencing the IAM role / service principal Tableflow uses to write to the bucket"
  type        = string
}

# Unity Catalog OAuth credentials (used by Tableflow catalog integration;
# the Databricks Delta Lake Sink Connector in lakehouse_sinks.tf uses a PAT
# instead — that is a separate credential set).
variable "databricks_oauth_client_id" {
  description = "Databricks service principal OAuth client ID for Unity Catalog integration"
  type        = string
  sensitive   = true
}

variable "databricks_oauth_client_secret" {
  description = "Databricks service principal OAuth client secret"
  type        = string
  sensitive   = true
}

# Snowflake Open Catalog OAuth credentials (used by Tableflow catalog
# integration; the Snowpipe Streaming Sink Connector in lakehouse_sinks.tf
# uses key-pair auth instead — separate credential set).
variable "snowflake_open_catalog_endpoint" {
  description = "Snowflake Open Catalog endpoint URL"
  type        = string
}

variable "snowflake_oauth_client_id" {
  description = "Snowflake OAuth client ID for Open Catalog integration"
  type        = string
  sensitive   = true
}

variable "snowflake_oauth_client_secret" {
  description = "Snowflake OAuth client secret for Open Catalog integration"
  type        = string
  sensitive   = true
}

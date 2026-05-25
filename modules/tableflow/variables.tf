# =============================================================================
# Module Inputs -- Tableflow
# =============================================================================

variable "source_topic_name" {
  description = "Fully qualified source topic name (typically module.X.topic_name)"
  type        = string
}

variable "storage_format" {
  description = "Tableflow storage format. ICEBERG (default) works with both Databricks (via UniForm) and Snowflake; DELTA is Databricks-only."
  type        = string
  default     = "ICEBERG"

  validation {
    condition     = contains(["ICEBERG", "DELTA"], var.storage_format)
    error_message = "storage_format must be ICEBERG or DELTA."
  }
}

variable "catalog_target" {
  description = "Downstream catalog target. unity-catalog routes to Databricks; snowflake-horizon routes to Snowflake Open Catalog; none leaves the table queryable via the underlying storage only."
  type        = string
  default     = "none"

  validation {
    condition     = contains(["unity-catalog", "snowflake-horizon", "none"], var.catalog_target)
    error_message = "catalog_target must be one of: unity-catalog, snowflake-horizon, none."
  }
}

# ---------------------------------------------------------------------------
# Storage (BYOB -- Bring Your Own Bucket; CC default storage is also supported
# but BYOB is the FSI standard for data residency control)
# ---------------------------------------------------------------------------
variable "tableflow_bucket_name" {
  description = "S3 bucket name for Tableflow materialized files. (Azure ADLS Gen2 variant available; see provider docs for the azure_data_lake_storage_gen_2 block.)"
  type        = string
}

variable "tableflow_provider_integration_id" {
  description = "CC provider integration ID for the bucket (created out-of-band; references the IAM role / service principal Tableflow uses)"
  type        = string
}

# ---------------------------------------------------------------------------
# Unity Catalog inputs (required when catalog_target = unity-catalog)
# Auth is OAuth client_id/client_secret per the confluent_catalog_integration
# provider schema -- Databricks PAT is not used here.
# ---------------------------------------------------------------------------
variable "databricks_workspace_endpoint" {
  description = "Databricks workspace URL (e.g., https://adb-1234567890.123.azuredatabricks.net)"
  type        = string
  default     = ""
}

variable "databricks_catalog_name" {
  description = "Unity Catalog catalog name (e.g., fsi_prod)"
  type        = string
  default     = ""
}

variable "databricks_oauth_client_id" {
  description = "Databricks service principal OAuth client ID for Unity Catalog integration"
  type        = string
  default     = ""
  sensitive   = true
}

variable "databricks_oauth_client_secret" {
  description = "Databricks service principal OAuth client secret. Use Vault interpolation in calling module."
  type        = string
  default     = ""
  sensitive   = true
}

# ---------------------------------------------------------------------------
# Snowflake Open Catalog (Horizon) inputs (required when catalog_target =
# snowflake-horizon). Snowflake Open Catalog uses OAuth (client_id/secret)
# plus a warehouse name for catalog operations.
# ---------------------------------------------------------------------------
variable "snowflake_open_catalog_endpoint" {
  description = "Snowflake Open Catalog endpoint URL"
  type        = string
  default     = ""
}

variable "snowflake_warehouse" {
  description = "Snowflake warehouse to use for Open Catalog operations"
  type        = string
  default     = ""
}

variable "snowflake_allowed_scope" {
  description = "Allowed scope for the Snowflake Open Catalog integration (e.g., PRINCIPAL_ROLE:fsi_kafka_ingest)"
  type        = string
  default     = ""
}

variable "snowflake_oauth_client_id" {
  description = "Snowflake OAuth client ID for Open Catalog"
  type        = string
  default     = ""
  sensitive   = true
}

variable "snowflake_oauth_client_secret" {
  description = "Snowflake OAuth client secret. Use Vault interpolation in calling module."
  type        = string
  default     = ""
  sensitive   = true
}

# ---------------------------------------------------------------------------
# Infrastructure references
# ---------------------------------------------------------------------------
variable "environment_id" {
  description = "Confluent Cloud environment ID"
  type        = string
}

variable "kafka_cluster_id" {
  description = "Confluent Cloud Kafka cluster ID hosting the source topic"
  type        = string
}

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

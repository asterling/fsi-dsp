# =============================================================================
# Lakehouse Sink Declarations -- CC-managed Databricks / Snowflake connectors
# =============================================================================
# Scoped exception to ADR-004 (self-managed on-prem Connect): these sinks
# are CC-managed because the source topic is in CC and the target is a SaaS
# lakehouse. No on-prem element in the pipeline.
#
# For self-managed CP/CFK/LinuxONE deployments, see:
#   - reference/connect-configs/databricks-delta-sink-example.json
#   - reference/connect-configs/snowflake-snowpipe-sink-example.json
#   - ansible/playbooks/deploy-lakehouse-sinks.yml
# =============================================================================

# ---------------------------------------------------------------------------
# DB-C: Databricks Delta Lake Sink for core-banking account transactions
# ---------------------------------------------------------------------------
module "corebanking_to_databricks" {
  source = "../../modules/lakehouse_sink"

  sink_type         = "DatabricksDeltaLakeSink"
  source_topic_name = module.corebanking_account_txn.topic_name
  target_table      = "fsi_prod.kafka_corebanking.account_transaction"
  sla_tier          = "critical"

  databricks_workspace_url = var.databricks_workspace_url
  credentials_secret_ref   = "secret/fsi/databricks#token"

  environment_id                = var.environment_id
  kafka_cluster_id              = local.infra.kafka_cluster_id
  kafka_cluster_crn             = local.infra.kafka_cluster_crn
  kafka_rest_endpoint           = local.infra.kafka_rest_endpoint
  kafka_api_key                 = var.kafka_api_key
  kafka_api_secret              = var.kafka_api_secret
  schema_registry_cluster_crn   = local.infra.sr_cluster_crn
  schema_registry_rest_endpoint = local.infra.sr_rest_endpoint
}

# ---------------------------------------------------------------------------
# SF-A: Snowflake Snowpipe Streaming Sink for fraud alert signals
# ---------------------------------------------------------------------------
module "fraud_to_snowflake" {
  source = "../../modules/lakehouse_sink"

  sink_type         = "SnowflakeSink"
  source_topic_name = module.fraud_alert_signal.topic_name
  target_table      = "FSI_PROD.KAFKA_FRAUD.ALERT_SIGNAL"
  sla_tier          = "critical"

  snowflake_account_url  = var.snowflake_account_url
  snowflake_user         = var.snowflake_user
  credentials_secret_ref = "secret/fsi/snowflake#private_key"

  environment_id                = var.environment_id
  kafka_cluster_id              = local.infra.kafka_cluster_id
  kafka_cluster_crn             = local.infra.kafka_cluster_crn
  kafka_rest_endpoint           = local.infra.kafka_rest_endpoint
  kafka_api_key                 = var.kafka_api_key
  kafka_api_secret              = var.kafka_api_secret
  schema_registry_cluster_crn   = local.infra.sr_cluster_crn
  schema_registry_rest_endpoint = local.infra.sr_rest_endpoint
}

# ---------------------------------------------------------------------------
# Variables specific to lakehouse sinks
# ---------------------------------------------------------------------------
variable "environment_id" {
  description = "Confluent Cloud environment ID"
  type        = string
}

variable "databricks_workspace_url" {
  description = "Databricks workspace URL (e.g., https://adb-1234567890.123.azuredatabricks.net)"
  type        = string
}

variable "snowflake_account_url" {
  description = "Snowflake account URL (e.g., https://abc12345.us-east-1.snowflakecomputing.com)"
  type        = string
}

variable "snowflake_user" {
  description = "Snowflake service user with INSERT on the target schema and key-pair auth configured"
  type        = string
}

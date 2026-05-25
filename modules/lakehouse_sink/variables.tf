# =============================================================================
# Module Inputs -- Lakehouse Sink
# =============================================================================

# ---------------------------------------------------------------------------
# Sink identity (required)
# ---------------------------------------------------------------------------
variable "sink_type" {
  description = "Sink connector class. Must be DatabricksDeltaLakeSink or SnowflakeSink."
  type        = string

  validation {
    condition     = contains(["DatabricksDeltaLakeSink", "SnowflakeSink"], var.sink_type)
    error_message = "sink_type must be one of: DatabricksDeltaLakeSink, SnowflakeSink."
  }
}

variable "source_topic_name" {
  description = "Fully qualified source topic name (typically the output of module.X.topic_name)"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9.-]+$", var.source_topic_name))
    error_message = "Source topic must match the platform naming convention (lowercase, dots, hyphens)."
  }
}

variable "target_table" {
  description = "Target table in catalog.schema.table form (Databricks) or DATABASE.SCHEMA.TABLE form (Snowflake)"
  type        = string

  validation {
    condition     = length(split(".", var.target_table)) == 3
    error_message = "target_table must have exactly two dots: catalog.schema.table or DATABASE.SCHEMA.TABLE."
  }
}

variable "credentials_secret_ref" {
  description = "Vault/secrets reference for the lakehouse credential (e.g., secret/fsi/databricks#token or secret/fsi/snowflake#private_key). Resolved at runtime by CC Secrets Manager."
  type        = string
  sensitive   = true
}

variable "sla_tier" {
  description = "SLA tier determining task count and DLQ defaults"
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["critical", "standard", "best-effort", "compliance"], var.sla_tier)
    error_message = "SLA tier must be one of: critical, standard, best-effort, compliance."
  }
}

# ---------------------------------------------------------------------------
# Databricks-specific inputs (required when sink_type = DatabricksDeltaLakeSink)
# ---------------------------------------------------------------------------
variable "databricks_workspace_url" {
  description = "Databricks workspace URL (e.g., https://adb-1234567890.123.azuredatabricks.net)"
  type        = string
  default     = ""
}

variable "auto_evolve" {
  description = "Whether the Databricks connector should auto-evolve the target table schema. ADR-002 default is false."
  type        = bool
  default     = false
}

variable "flush_interval_ms" {
  description = "Databricks sink flush interval in milliseconds"
  type        = number
  default     = 5000
}

# ---------------------------------------------------------------------------
# Snowflake-specific inputs (required when sink_type = SnowflakeSink)
# ---------------------------------------------------------------------------
variable "snowflake_account_url" {
  description = "Snowflake account URL (e.g., https://abc12345.us-east-1.snowflakecomputing.com)"
  type        = string
  default     = ""
}

variable "snowflake_user" {
  description = "Snowflake service user with INSERT on the target schema and key-pair auth configured"
  type        = string
  default     = ""
}

variable "enable_schematization" {
  description = "Whether to use Snowflake's schematization (Avro fields become typed columns). Default true."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# DLQ configuration
# ---------------------------------------------------------------------------
variable "dlq_retention_ms" {
  description = "DLQ topic retention in milliseconds. Default 7 days for forensic review."
  type        = number
  default     = 604800000 # 7 days
}

# ---------------------------------------------------------------------------
# Connector tuning
# ---------------------------------------------------------------------------
variable "tasks_max_override" {
  description = "Override the SLA-tier-derived tasks.max. Leave null to use default (critical=6, standard=3, best-effort=1, compliance=6)."
  type        = number
  default     = null
}

variable "connector_overrides" {
  description = "Map of additional connector config keys to merge into the final config. Use sparingly; document the why in the calling module."
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# Infrastructure references (set in environment-level vars, same shape as modules/topic)
# ---------------------------------------------------------------------------
variable "environment_id" {
  description = "Confluent Cloud environment ID"
  type        = string
}

variable "kafka_cluster_id" {
  description = "Confluent Cloud Kafka cluster ID hosting the source topic"
  type        = string
}

variable "kafka_cluster_crn" {
  description = "Confluent Resource Name for the Kafka cluster (for RBAC)"
  type        = string
}

variable "kafka_rest_endpoint" {
  description = "Kafka REST endpoint"
  type        = string
}

variable "kafka_api_key" {
  description = "API key for Kafka cluster operations (DLQ provisioning)"
  type        = string
  sensitive   = true
}

variable "kafka_api_secret" {
  description = "API secret for Kafka cluster operations"
  type        = string
  sensitive   = true
}

variable "schema_registry_cluster_crn" {
  description = "Confluent Resource Name for Schema Registry (for RBAC)"
  type        = string
}

variable "schema_registry_rest_endpoint" {
  description = "Schema Registry REST endpoint (consumed by AvroConverter)"
  type        = string
}

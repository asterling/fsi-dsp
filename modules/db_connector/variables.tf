# =============================================================================
# Module Inputs -- Database Connector
# =============================================================================

# ---------------------------------------------------------------------------
# Connector identity (required)
# ---------------------------------------------------------------------------
variable "db_type" {
  description = "Database type. One of: mongodb, redis, cockroachdb, postgres."
  type        = string

  validation {
    condition     = contains(["mongodb", "redis", "cockroachdb", "postgres"], var.db_type)
    error_message = "db_type must be one of: mongodb, redis, cockroachdb, postgres."
  }
}

variable "direction" {
  description = "Connector direction. source = Kafka <- DB (CDC). sink = Kafka -> DB."
  type        = string

  validation {
    condition     = contains(["source", "sink"], var.direction)
    error_message = "direction must be source or sink."
  }
}

variable "source_topic_name" {
  description = "Source Kafka topic (required for sinks; empty for sources)"
  type        = string
  default     = ""
}

variable "target_topic_pattern" {
  description = "Target Kafka topic name or prefix (required for sources). Sources may emit to multiple topics; pattern is granted DeveloperWrite as PREFIXED."
  type        = string
  default     = ""
}

variable "credentials_secret_ref" {
  description = "Vault/secrets reference for the database credential. Resolved at runtime by CC Secrets Manager. Format: secret/fsi/<db>#<field>."
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
# Target database endpoint (used by sinks)
# ---------------------------------------------------------------------------
variable "target_db_url" {
  description = "Target DB URL for sinks. mongodb+srv://... for Mongo; rediss://host:port for Redis; jdbc:postgresql://host:port/db for CRDB/Postgres."
  type        = string
  default     = ""
}

variable "source_db_url" {
  description = "Source DB URL for sources. mongodb+srv://... for Mongo; jdbc:postgresql://host:port/db for Postgres."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# MongoDB-specific (db_type = mongodb)
# ---------------------------------------------------------------------------
variable "mongodb_database" {
  description = "MongoDB database name"
  type        = string
  default     = ""
}

variable "mongodb_collection" {
  description = "MongoDB collection name (single-collection scope; for multi-collection use connector_overrides)"
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Redis-specific (db_type = redis, direction = sink)
# ---------------------------------------------------------------------------
variable "redis_client_mode" {
  description = "Redis client mode. Standalone (default) or Cluster."
  type        = string
  default     = "Standalone"

  validation {
    condition     = contains(["Standalone", "Cluster"], var.redis_client_mode)
    error_message = "redis_client_mode must be Standalone or Cluster."
  }
}

variable "redis_key_prefix" {
  description = "Prefix applied to all Redis keys written by this connector"
  type        = string
  default     = ""
}

variable "redis_ttl_seconds" {
  description = "TTL in seconds for Redis values (0 = no expiration). Defaults align with SLA tier: critical=0, standard=86400 (24h), best-effort=3600 (1h)."
  type        = number
  default     = 0
}

# ---------------------------------------------------------------------------
# JDBC-specific (db_type = cockroachdb or postgres, direction = sink)
# ---------------------------------------------------------------------------
variable "jdbc_database" {
  description = "JDBC database name (the dbname part of the connection URL)"
  type        = string
  default     = ""
}

variable "jdbc_table_name" {
  description = "Target JDBC table name. Supports $${topic} substitution per Confluent JDBC sink convention."
  type        = string
  default     = ""
}

variable "jdbc_pk_fields" {
  description = "Comma-separated primary key field names for upsert mode"
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Postgres CDC source (db_type = postgres, direction = source)
# ---------------------------------------------------------------------------
variable "postgres_database" {
  description = "Postgres database name to capture"
  type        = string
  default     = ""
}

variable "postgres_publication" {
  description = "Pre-created Postgres logical-decoding publication. Platform pattern: DBA owns publication creation per security policy; we do not use publication.autocreate.mode=all_tables."
  type        = string
  default     = ""
}

variable "postgres_slot_name" {
  description = "Postgres logical replication slot name. The platform convention is fsi_kafka_<env>."
  type        = string
  default     = ""
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
  description = "Override the SLA-tier-derived tasks.max. Sinks default to {critical: 6, standard: 3, best-effort: 1}. Sources default to {critical: 4, standard: 2, best-effort: 1}."
  type        = number
  default     = null
}

variable "connector_overrides" {
  description = "Map of additional connector config keys to merge into the final config. Use sparingly; document the why in the calling module."
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# Infrastructure references (same shape as modules/lakehouse_sink and modules/topic)
# ---------------------------------------------------------------------------
variable "environment_id" {
  description = "Confluent Cloud environment ID"
  type        = string
}

variable "kafka_cluster_id" {
  description = "Confluent Cloud Kafka cluster ID"
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
  description = "Schema Registry REST endpoint"
  type        = string
}

# =============================================================================
# Module Inputs — What teams fill in
# =============================================================================

# ---------------------------------------------------------------------------
# Topic identity (required — assembles the topic name)
# ---------------------------------------------------------------------------
variable "domain" {
  description = "Business domain (e.g., cncb, rtfd, ofac, eventgrid)"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}$", var.domain))
    error_message = "Domain must be lowercase alphanumeric with hyphens, 2-31 chars, starting with a letter."
  }
}

variable "application" {
  description = "Application name within the domain (e.g., core, alerts, screening)"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}$", var.application))
    error_message = "Application must be lowercase alphanumeric with hyphens, 2-31 chars."
  }
}

variable "schema_version" {
  description = "Schema version identifier (e.g., v1, v2)"
  type        = string

  validation {
    condition     = can(regex("^v[0-9]+$", var.schema_version))
    error_message = "Version must follow the pattern v1, v2, etc."
  }
}

variable "entity" {
  description = "The data entity this topic carries (e.g., account-transaction, fraud-signal)"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,60}$", var.entity))
    error_message = "Entity must be lowercase alphanumeric with hyphens, 2-61 chars."
  }
}

# ---------------------------------------------------------------------------
# Governance metadata (required — enforced by C4E)
# ---------------------------------------------------------------------------
variable "owner" {
  description = "Team email responsible for this topic (e.g., cncb-team@fsi.org)"
  type        = string

  validation {
    condition     = can(regex("^[^@]+@[^@]+\\.[^@]+$", var.owner))
    error_message = "Owner must be a valid email address."
  }
}

variable "sla_tier" {
  description = "SLA tier determining compatibility mode, partitions, retention, and DR priority"
  type        = string

  validation {
    condition     = contains(["critical", "standard", "best-effort", "compliance"], var.sla_tier)
    error_message = "SLA tier must be one of: critical, standard, best-effort, compliance."
  }
}

variable "data_classification" {
  description = "Data classification per FSI policy"
  type        = string
  default     = "internal"

  validation {
    condition     = contains(["confidential", "internal", "public"], var.data_classification)
    error_message = "Data classification must be one of: confidential, internal, public."
  }
}

# ---------------------------------------------------------------------------
# Schema (required)
# ---------------------------------------------------------------------------
variable "schema_file" {
  description = "Path to the Avro schema file (.avsc) relative to the calling module"
  type        = string
}

variable "pii_fields" {
  description = "List of field names containing PII (for tagging and encryption rules)"
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------------------
# Access control (required — at least one producer)
# ---------------------------------------------------------------------------
variable "create_service_accounts" {
  description = "Whether to create new service accounts or use existing IDs from producer/consumer_service_accounts"
  type        = bool
  default     = false
}

variable "producer_sa_names" {
  description = "Display names for producer SAs to create (used when create_service_accounts = true)"
  type        = list(string)
  default     = []
}

variable "consumer_sa_names" {
  description = "Display names for consumer SAs to create (used when create_service_accounts = true)"
  type        = list(string)
  default     = []
}

variable "producer_service_accounts" {
  description = "List of Confluent Cloud service account IDs that produce to this topic (used when create_service_accounts = false)"
  type        = list(string)
  default     = []
}

variable "consumer_service_accounts" {
  description = "List of Confluent Cloud service account IDs that consume from this topic"
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------------------
# Overrides (optional — defaults derived from sla_tier)
# ---------------------------------------------------------------------------
variable "compatibility_override" {
  description = "Override the auto-derived compatibility mode. Leave null to use C4E defaults."
  type        = string
  default     = null

  validation {
    condition = var.compatibility_override == null || contains([
      "BACKWARD", "BACKWARD_TRANSITIVE", "FORWARD", "FORWARD_TRANSITIVE",
      "FULL", "FULL_TRANSITIVE", "NONE"
    ], coalesce(var.compatibility_override, "BACKWARD"))
    error_message = "Invalid compatibility mode."
  }
}

variable "partitions_override" {
  description = "Override the auto-derived partition count. Leave null to use C4E defaults."
  type        = number
  default     = null
}

variable "retention_ms_override" {
  description = "Override the auto-derived retention in milliseconds. Leave null to use C4E defaults."
  type        = number
  default     = null
}

variable "cleanup_policy" {
  description = "Topic cleanup policy"
  type        = string
  default     = "delete"

  validation {
    condition     = contains(["delete", "compact", "compact,delete"], var.cleanup_policy)
    error_message = "Cleanup policy must be one of: delete, compact, compact,delete."
  }
}

# ---------------------------------------------------------------------------
# DR configuration
# ---------------------------------------------------------------------------
variable "enable_dr_mirror" {
  description = "Whether to create a mirror topic in the DR cluster"
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Infrastructure references (set in environment-level vars, not per-topic)
# ---------------------------------------------------------------------------
variable "kafka_cluster_id" {
  description = "Confluent Cloud Kafka cluster ID (East/production)"
  type        = string
}

variable "kafka_rest_endpoint" {
  description = "Kafka REST endpoint for the production cluster"
  type        = string
}

variable "kafka_api_key" {
  description = "API key for Kafka cluster operations"
  type        = string
  sensitive   = true
}

variable "kafka_api_secret" {
  description = "API secret for Kafka cluster operations"
  type        = string
  sensitive   = true
}

variable "kafka_cluster_crn" {
  description = "Confluent Resource Name for the Kafka cluster (for RBAC)"
  type        = string
}

variable "schema_registry_cluster_id" {
  description = "Confluent Cloud Schema Registry cluster ID"
  type        = string
}

variable "schema_registry_rest_endpoint" {
  description = "Schema Registry REST endpoint"
  type        = string
}

variable "schema_registry_api_key" {
  description = "API key for Schema Registry operations"
  type        = string
  sensitive   = true
}

variable "schema_registry_api_secret" {
  description = "API secret for Schema Registry operations"
  type        = string
  sensitive   = true
}

variable "schema_registry_cluster_crn" {
  description = "Confluent Resource Name for Schema Registry (for RBAC)"
  type        = string
}

variable "cluster_link_name" {
  description = "Name of the bidirectional cluster link for DR mirroring"
  type        = string
  default     = "cluster_link_bidir_east_west"
}

variable "dr_kafka_cluster_id" {
  description = "Confluent Cloud Kafka cluster ID (West/DR)"
  type        = string
  default     = ""
}

variable "dr_kafka_rest_endpoint" {
  description = "Kafka REST endpoint for the DR cluster"
  type        = string
  default     = ""
}

variable "dr_kafka_api_key" {
  description = "API key for DR Kafka cluster operations"
  type        = string
  sensitive   = true
  default     = ""
}

variable "dr_kafka_api_secret" {
  description = "API secret for DR Kafka cluster operations"
  type        = string
  sensitive   = true
  default     = ""
}

# ---------------------------------------------------------------------------
# Compliance retention (per D-11)
# ---------------------------------------------------------------------------
variable "retention_years" {
  description = "Retention period in years for compliance tier. -1 = infinite (default). Set 7, 10, etc. for specific retention. Only applies when sla_tier = compliance."
  type        = number
  default     = -1

  validation {
    condition     = var.retention_years == -1 || var.retention_years >= 7
    error_message = "Compliance retention must be -1 (infinite) or >= 7 years per FSI regulatory requirements."
  }
}

# ---------------------------------------------------------------------------
# CSFLE encryption (per D-08) — confidential topics only
# Requires Stream Governance Advanced package on Confluent Cloud.
# ---------------------------------------------------------------------------
variable "kek_name" {
  description = "Key Encryption Key name for CSFLE (required when data_classification = confidential)"
  type        = string
  default     = ""
}

variable "csfle_kms_type" {
  description = "KMS provider type for CSFLE: aws-kms, azure-kms, gcp-kms, or hcvault"
  type        = string
  default     = ""

  validation {
    condition     = var.csfle_kms_type == "" || contains(["aws-kms", "azure-kms", "gcp-kms", "hcvault"], var.csfle_kms_type)
    error_message = "CSFLE KMS type must be one of: aws-kms, azure-kms, gcp-kms, hcvault."
  }
}

variable "csfle_kms_key_id" {
  description = "KMS key identifier for CSFLE (ARN for AWS, Key Vault URI for Azure, resource name for GCP, path for Vault)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "csfle_shared_kek" {
  description = "Whether DEK Registry can call KMS directly. Required true for Connect/ksqlDB to process encrypted data."
  type        = bool
  default     = true
}

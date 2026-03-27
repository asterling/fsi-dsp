# =============================================================================
# Module Inputs -- Flink Compute Pool & SQL Statements
# =============================================================================

# ---------------------------------------------------------------------------
# Compute pool configuration
# ---------------------------------------------------------------------------
variable "compute_pool_name" {
  description = "Display name for the Flink compute pool (e.g., fsi-prod-pool)"
  type        = string
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{2,62}$", var.compute_pool_name))
    error_message = "Compute pool name must be 3-63 chars, alphanumeric with hyphens, starting with a letter."
  }
}

variable "cloud_provider" {
  description = "Cloud provider for the compute pool: AWS, AZURE, or GCP"
  type        = string
  validation {
    condition     = contains(["AWS", "AZURE", "GCP"], var.cloud_provider)
    error_message = "Cloud provider must be one of: AWS, AZURE, GCP."
  }
}

variable "region" {
  description = "Cloud region for the compute pool (e.g., us-east-1, eastus2, us-central1)"
  type        = string
}

variable "max_cfu" {
  description = "Maximum Confluent Flink Units. Cannot be decreased after creation. Start conservative: 5-10 dev, 10-20 staging, 20-50 prod."
  type        = number
  default     = 5
  validation {
    condition     = contains([5, 10, 20, 30, 40, 50], var.max_cfu)
    error_message = "max_cfu must be one of: 5, 10, 20, 30, 40, 50. Cannot be decreased after creation."
  }
}

variable "environment_id" {
  description = "Confluent Cloud environment ID (e.g., env-xxxxx)"
  type        = string
}

variable "environment_display_name" {
  description = "Confluent Cloud environment display name (used as sql.current-catalog)"
  type        = string
}

# ---------------------------------------------------------------------------
# Flink SQL statement configuration
# ---------------------------------------------------------------------------
variable "flink_statements" {
  description = "Map of Flink SQL statements to submit. Key = statement name, value = { sql = \"...\", properties = {} }"
  type = map(object({
    sql        = string
    properties = optional(map(string), {})
  }))
  default = {}
}

variable "organization_id" {
  description = "Confluent Cloud organization ID"
  type        = string
}

variable "kafka_cluster_display_name" {
  description = "Kafka cluster display name (used as sql.current-database)"
  type        = string
}

variable "flink_service_account_id" {
  description = "Service account ID used as principal for Flink statements"
  type        = string
  default     = ""
}

variable "flink_rest_endpoint" {
  description = "Flink REST endpoint for the compute pool region"
  type        = string
  default     = ""
}

variable "flink_api_key" {
  description = "API key for Flink REST API (Cloud API key or Flink-scoped key)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "flink_api_secret" {
  description = "API secret for Flink REST API"
  type        = string
  sensitive   = true
  default     = ""
}

# ---------------------------------------------------------------------------
# Lifecycle control
# ---------------------------------------------------------------------------
variable "prevent_destroy" {
  description = "Prevent accidental destruction of compute pool and statements"
  type        = bool
  default     = true
}

# =============================================================================
# Flink Configuration Variables
# =============================================================================
# Values loaded from terraform.tfvars or environment variables.

variable "flink_enabled" {
  description = "Whether to provision Flink compute pool in this scenario"
  type        = bool
  default     = false
}

variable "flink_compute_pool_name" {
  description = "Display name for the Flink compute pool"
  type        = string
  default     = "fsi-prod-pool"
}

variable "flink_max_cfu" {
  description = "Maximum CFUs for the Flink compute pool (cannot be decreased)"
  type        = number
  default     = 5
}

variable "flink_region" {
  description = "Region for the Flink compute pool (must match or be compatible with Kafka cluster region)"
  type        = string
  default     = ""
}

variable "cc_environment_id" {
  description = "Confluent Cloud environment ID (e.g., env-xxxxx)"
  type        = string
  default     = ""
}

variable "cc_environment_display_name" {
  description = "Confluent Cloud environment display name (Flink sql.current-catalog)"
  type        = string
  default     = ""
}

variable "cc_org_id" {
  description = "Confluent Cloud organization ID"
  type        = string
  default     = ""
}

variable "kafka_cluster_display_name" {
  description = "Kafka cluster display name (Flink sql.current-database)"
  type        = string
  default     = ""
}

variable "flink_service_account_id" {
  description = "Service account ID for Flink statement principal"
  type        = string
  default     = ""
}

variable "flink_rest_endpoint" {
  description = "Flink REST endpoint"
  type        = string
  default     = ""
}

variable "flink_api_key" {
  description = "API key for Flink REST API"
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

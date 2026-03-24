# =============================================================================
# OAuth Variables -- GCP Cloud Identity
# =============================================================================

variable "gcp_organization_id" {
  description = "GCP organization ID for Cloud Identity integration"
  type        = string
  default     = ""
}

variable "confluent_cloud_app_id" {
  description = "Confluent Cloud application ID registered in GCP Cloud Identity"
  type        = string
  default     = ""
}

variable "gcp_producer_group_email" {
  description = "Google Group email for Kafka producer identity pool filter"
  type        = string
  default     = ""
}

variable "gcp_consumer_group_email" {
  description = "Google Group email for Kafka consumer identity pool filter"
  type        = string
  default     = ""
}

# =============================================================================
# OAuth Variables -- Azure AD
# =============================================================================

variable "azure_tenant_id" {
  description = "Azure AD tenant ID for OAUTHBEARER identity provider"
  type        = string
  default     = ""
}

variable "confluent_cloud_app_id" {
  description = "Confluent Cloud application ID registered in Azure AD"
  type        = string
  default     = ""
}

variable "azure_producer_group_id" {
  description = "Azure AD group ID for Kafka producer identity pool filter"
  type        = string
  default     = ""
}

variable "azure_consumer_group_id" {
  description = "Azure AD group ID for Kafka consumer identity pool filter"
  type        = string
  default     = ""
}

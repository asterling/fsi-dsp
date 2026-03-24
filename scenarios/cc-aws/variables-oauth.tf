# =============================================================================
# OAuth Variables -- AWS IAM Identity Center
# =============================================================================

variable "aws_sso_instance_id" {
  description = "AWS IAM Identity Center (SSO) instance ID for OAUTHBEARER identity provider"
  type        = string
  default     = ""
}

variable "confluent_cloud_app_id" {
  description = "Confluent Cloud application ID registered in AWS IAM Identity Center"
  type        = string
  default     = ""
}

variable "aws_producer_group_name" {
  description = "AWS IAM Identity Center group name for Kafka producer identity pool filter"
  type        = string
  default     = ""
}

variable "aws_consumer_group_name" {
  description = "AWS IAM Identity Center group name for Kafka consumer identity pool filter"
  type        = string
  default     = ""
}

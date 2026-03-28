# =============================================================================
# CP Cluster Configuration Variables
# =============================================================================
# Values loaded from terraform.tfvars (gitignored).
# Source credentials from HashiCorp Vault or your organization's secret manager.

variable "cp_kafka_rest_endpoint" {
  description = "Kafka REST endpoint for the CP cluster (e.g., https://kafka:8090)"
  type        = string
}

variable "cp_kafka_api_key" {
  description = "API key for Kafka REST operations on the CP cluster"
  type        = string
  sensitive   = true
}

variable "cp_kafka_api_secret" {
  description = "API secret for Kafka REST operations on the CP cluster"
  type        = string
  sensitive   = true
}

variable "cp_sr_rest_endpoint" {
  description = "Schema Registry REST endpoint (e.g., https://sr:8081)"
  type        = string
}

variable "cp_sr_api_key" {
  description = "API key for Schema Registry REST operations"
  type        = string
  sensitive   = true
}

variable "cp_sr_api_secret" {
  description = "API secret for Schema Registry REST operations"
  type        = string
  sensitive   = true
}

variable "cp_kafka_cluster_id" {
  description = "Kafka cluster ID for resource references (e.g., kafka-east-cluster)"
  type        = string
}

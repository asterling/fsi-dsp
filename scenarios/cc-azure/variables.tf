# =============================================================================
# Cluster Configuration Variables
# =============================================================================
# Values loaded from clusters.auto.tfvars (gitignored).
# Copy clusters.auto.tfvars.example and fill with real values from Confluent Cloud.

variable "kafka_cluster_id" {
  description = "Confluent Cloud Kafka cluster ID (production/East)"
  type        = string
}

variable "kafka_rest_endpoint" {
  description = "Kafka REST endpoint for the production cluster"
  type        = string
}

variable "kafka_cluster_crn" {
  description = "Confluent Resource Name for the Kafka cluster (for RBAC bindings)"
  type        = string
}

variable "sr_cluster_id" {
  description = "Confluent Cloud Schema Registry cluster ID"
  type        = string
}

variable "sr_rest_endpoint" {
  description = "Schema Registry REST endpoint"
  type        = string
}

variable "sr_cluster_crn" {
  description = "Confluent Resource Name for Schema Registry (for RBAC bindings)"
  type        = string
}

variable "cluster_link_name" {
  description = "Name of the bidirectional cluster link for DR mirroring"
  type        = string
}

variable "dr_kafka_cluster_id" {
  description = "Confluent Cloud Kafka cluster ID (DR/West)"
  type        = string
}

variable "dr_kafka_rest_endpoint" {
  description = "Kafka REST endpoint for the DR cluster"
  type        = string
}

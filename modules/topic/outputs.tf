# =============================================================================
# Module Outputs — What teams can reference downstream
# =============================================================================

output "topic_name" {
  description = "The fully qualified topic name"
  value       = local.topic_name
}

output "topic_id" {
  description = "Confluent Cloud topic resource ID"
  value       = confluent_kafka_topic.this.id
}

output "value_subject" {
  description = "Schema Registry subject name for the value schema"
  value       = local.value_subject
}

output "schema_id" {
  description = "Schema Registry schema ID"
  value       = confluent_schema.value.schema_identifier
}

output "compatibility_mode" {
  description = "The compatibility mode applied to this topic's schema"
  value       = local.compatibility
}

output "partitions" {
  description = "Number of partitions"
  value       = local.partitions
}

output "retention_ms" {
  description = "Retention period in milliseconds"
  value       = local.retention_ms
}

output "dr_mirror_topic_id" {
  description = "DR mirror topic resource ID (empty if DR disabled)"
  value       = var.enable_dr_mirror ? confluent_kafka_mirror_topic.dr[0].id : ""
}

output "metadata" {
  description = "Schema metadata tags applied to this topic"
  value       = local.schema_metadata
}

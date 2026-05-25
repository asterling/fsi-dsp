# =============================================================================
# Module Outputs -- Database Connector
# =============================================================================

output "connector_name" {
  description = "The fully qualified connector name"
  value       = local.connector_name
}

output "connector_id" {
  description = "Confluent Cloud connector resource ID"
  value       = confluent_connector.this.id
}

output "connector_class" {
  description = "Effective connector class (e.g. MongoDbAtlasSource, PostgresCdcSourceV2, RedisSink, PostgresSink)"
  value       = local.connector_class
}

output "dlq_topic_name" {
  description = "Name of the per-connector DLQ topic"
  value       = local.dlq_topic_name
}

output "service_account_id" {
  description = "Service account ID used by the connector"
  value       = confluent_service_account.connector_sa.id
}

output "service_account_crn" {
  description = "Service account CRN principal (for downstream RBAC references)"
  value       = "User:${confluent_service_account.connector_sa.id}"
}

output "tasks_max" {
  description = "Effective tasks.max applied to the connector"
  value       = local.tasks_max
}

output "db_type" {
  description = "Database type echoed back (for cross-module references)"
  value       = var.db_type
}

output "direction" {
  description = "Direction echoed back (for cross-module references)"
  value       = var.direction
}

# =============================================================================
# Module Outputs -- Tableflow
# =============================================================================

output "table_name" {
  description = "The materialized table name (topic name with dots replaced by underscores)"
  value       = local.table_name
}

output "tableflow_topic_id" {
  description = "Confluent Cloud Tableflow topic resource ID"
  value       = confluent_tableflow_topic.this.id
}

output "storage_format" {
  description = "Storage format applied (ICEBERG or DELTA)"
  value       = var.storage_format
}

output "catalog_integration_id" {
  description = "Catalog integration resource ID (empty if catalog_target = none)"
  value       = var.catalog_target == "none" ? "" : confluent_catalog_integration.this[0].id
}

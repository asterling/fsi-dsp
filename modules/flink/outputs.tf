# =============================================================================
# Module Outputs -- Flink
# =============================================================================

output "compute_pool_id" {
  description = "Confluent Cloud Flink compute pool ID"
  value       = confluent_flink_compute_pool.pool.id
}

output "compute_pool_name" {
  description = "Flink compute pool display name"
  value       = confluent_flink_compute_pool.pool.display_name
}

output "compute_pool_resource_name" {
  description = "Flink compute pool Confluent resource name"
  value       = confluent_flink_compute_pool.pool.resource_name
}

output "statement_names" {
  description = "Names of submitted Flink SQL statements"
  value       = [for k, v in confluent_flink_statement.statements : k]
}

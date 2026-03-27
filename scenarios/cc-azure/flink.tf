# =============================================================================
# Flink on Confluent Cloud -- Azure Scenario
# =============================================================================
# Provisions a CC Flink compute pool and optionally submits SQL statements.
# CC Flink auto-discovers Schema Registry subjects -- topics with registered
# Avro schemas appear as queryable Flink tables automatically (FLINK-05).
#
# Enable by setting flink_enabled = true in terraform.tfvars.
# =============================================================================

module "flink" {
  count  = var.flink_enabled ? 1 : 0
  source = "../../modules/flink"

  compute_pool_name          = var.flink_compute_pool_name
  cloud_provider             = "AZURE"
  region                     = var.flink_region
  max_cfu                    = var.flink_max_cfu
  environment_id             = var.cc_environment_id
  environment_display_name   = var.cc_environment_display_name
  organization_id            = var.cc_org_id
  kafka_cluster_display_name = var.kafka_cluster_display_name
  flink_service_account_id   = var.flink_service_account_id
  flink_rest_endpoint        = var.flink_rest_endpoint
  flink_api_key              = var.flink_api_key
  flink_api_secret           = var.flink_api_secret
}

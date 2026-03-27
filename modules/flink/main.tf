# =============================================================================
# FSI Kafka Platform -- Flink Module
# =============================================================================
# Provisions a CC Flink compute pool and optionally submits Flink SQL
# statements. CC Flink auto-discovers Schema Registry subjects -- no manual
# CREATE TABLE definitions needed for existing CC topics with registered
# Avro schemas (FLINK-05).
#
# Usage:
#   module "flink" {
#     source                     = "../../modules/flink"
#     compute_pool_name          = "fsi-prod-pool"
#     cloud_provider             = "AWS"
#     region                     = "us-east-1"
#     max_cfu                    = 10
#     environment_id             = var.environment_id
#     environment_display_name   = var.environment_display_name
#     organization_id            = var.organization_id
#     kafka_cluster_display_name = var.kafka_cluster_display_name
#   }
# =============================================================================

terraform {
  required_providers {
    confluent = {
      source  = "confluentinc/confluent"
      version = "~> 2.0"
    }
  }
}

# ---------------------------------------------------------------------------
# Flink Compute Pool
# ---------------------------------------------------------------------------
# max_cfu cannot be decreased after creation (Pitfall 2 from research).
# Start conservative and scale up as needed.
resource "confluent_flink_compute_pool" "pool" {
  display_name = var.compute_pool_name
  cloud        = var.cloud_provider
  region       = var.region
  max_cfu      = var.max_cfu

  environment {
    id = var.environment_id
  }

  lifecycle {
    prevent_destroy = true
  }
}

# ---------------------------------------------------------------------------
# Flink SQL Statements
# ---------------------------------------------------------------------------
# Each statement is a managed Terraform resource with lifecycle control.
# Statements require: organization, environment, compute_pool, principal,
# credentials, and the SQL text.
#
# CC Flink auto-discovers SR subjects (FLINK-05) -- SQL statements can
# reference topics as tables without CREATE TABLE definitions.
#
# WARNING: terraform destroy drops running statements (Pitfall 4).
# prevent_destroy = true protects production jobs.
resource "confluent_flink_statement" "statements" {
  for_each = var.flink_statements

  organization {
    id = var.organization_id
  }
  environment {
    id = var.environment_id
  }
  compute_pool {
    id = confluent_flink_compute_pool.pool.id
  }
  principal {
    id = var.flink_service_account_id
  }

  statement  = each.value.sql
  properties = merge(
    {
      "sql.current-catalog"  = var.environment_display_name
      "sql.current-database" = var.kafka_cluster_display_name
    },
    each.value.properties
  )

  rest_endpoint = var.flink_rest_endpoint

  credentials {
    key    = var.flink_api_key
    secret = var.flink_api_secret
  }

  lifecycle {
    prevent_destroy = true
  }
}

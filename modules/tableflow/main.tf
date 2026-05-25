# =============================================================================
# FSI Kafka Platform -- Tableflow Module
# =============================================================================
# Enables Confluent Tableflow on an existing topic and wires the materialized
# table into a downstream catalog (Unity Catalog for Databricks, Snowflake
# Open Catalog / Horizon for Snowflake).
#
# TABLEFLOW IS A CONFLUENT CLOUD-ONLY FEATURE. This module will not work
# against Confluent Platform, CFK, or LinuxONE deployments. See
# docs/tableflow-guide.md for the deployment-model availability matrix and
# the DB-C / SF-A fallback paths.
#
# Catalog auth: both Unity Catalog and Snowflake Open Catalog integrations
# use OAuth client credentials (client_id + client_secret), not PAT or
# RSA key-pair. Pass values via Vault interpolation from the calling module.
# =============================================================================

terraform {
  required_providers {
    confluent = {
      source  = "confluentinc/confluent"
      version = "~> 2.0"
    }
  }
}

locals {
  # Tableflow table name follows the topic name with dots replaced by
  # underscores for catalog compatibility
  table_name = replace(var.source_topic_name, ".", "_")
}

# ---------------------------------------------------------------------------
# Tableflow Topic -- materializes the topic to managed storage
# ---------------------------------------------------------------------------
resource "confluent_tableflow_topic" "this" {
  environment {
    id = var.environment_id
  }

  kafka_cluster {
    id = var.kafka_cluster_id
  }

  display_name = var.source_topic_name

  byob_aws {
    bucket_name             = var.tableflow_bucket_name
    provider_integration_id = var.tableflow_provider_integration_id
  }

  table_formats = [var.storage_format]

  credentials {
    key    = var.tableflow_api_key
    secret = var.tableflow_api_secret
  }

  lifecycle {
    precondition {
      condition     = contains(["ICEBERG", "DELTA"], var.storage_format)
      error_message = "storage_format must be ICEBERG or DELTA. DELTA is Databricks-only; ICEBERG works with both Databricks (via UniForm) and Snowflake."
    }
    precondition {
      condition = (
        var.catalog_target != "unity-catalog"
        || (var.databricks_workspace_endpoint != "" && var.databricks_catalog_name != "" && var.databricks_oauth_client_id != "")
      )
      error_message = "Unity Catalog target requires databricks_workspace_endpoint, databricks_catalog_name, and OAuth client credentials."
    }
    precondition {
      condition = (
        var.catalog_target != "snowflake-horizon"
        || (var.snowflake_open_catalog_endpoint != "" && var.snowflake_warehouse != "" && var.snowflake_oauth_client_id != "")
      )
      error_message = "Snowflake Open Catalog target requires snowflake_open_catalog_endpoint, snowflake_warehouse, and OAuth client credentials."
    }
  }
}

# ---------------------------------------------------------------------------
# Catalog Integration -- registers the table with the downstream catalog
# ---------------------------------------------------------------------------
resource "confluent_catalog_integration" "this" {
  count = var.catalog_target == "none" ? 0 : 1

  environment {
    id = var.environment_id
  }

  kafka_cluster {
    id = var.kafka_cluster_id
  }

  display_name = "ci-${local.table_name}-${var.catalog_target}"

  # Unity Catalog branch -- Databricks
  dynamic "unity" {
    for_each = var.catalog_target == "unity-catalog" ? [1] : []
    content {
      catalog_name       = var.databricks_catalog_name
      workspace_endpoint = var.databricks_workspace_endpoint
      client_id          = var.databricks_oauth_client_id
      client_secret      = var.databricks_oauth_client_secret
    }
  }

  # Snowflake Open Catalog (Horizon) branch
  dynamic "snowflake" {
    for_each = var.catalog_target == "snowflake-horizon" ? [1] : []
    content {
      endpoint      = var.snowflake_open_catalog_endpoint
      warehouse     = var.snowflake_warehouse
      allowed_scope = var.snowflake_allowed_scope
      client_id     = var.snowflake_oauth_client_id
      client_secret = var.snowflake_oauth_client_secret
    }
  }

  credentials {
    key    = var.tableflow_api_key
    secret = var.tableflow_api_secret
  }

  depends_on = [confluent_tableflow_topic.this]
}

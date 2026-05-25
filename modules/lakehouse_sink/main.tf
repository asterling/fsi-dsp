# =============================================================================
# FSI Kafka Platform -- Lakehouse Sink Module
# =============================================================================
# One module call produces a fully governed Confluent Cloud managed sink
# connector: connector + service account + RBAC + DLQ topic + metadata.
#
# Supported sink types (var.sink_type):
#   - DatabricksDeltaLakeSink  -- DB-C: Databricks Delta Lake Sink Connector
#   - SnowflakeSink            -- SF-A: Snowflake Snowpipe Streaming Connector
#
# This module is the CC-managed path. For self-managed CP/CFK/LinuxONE
# deployments, use the connector JSON templates under
# reference/connect-configs/ and the ansible/roles/cp_databricks_sink and
# ansible/roles/cp_snowflake_sink roles.
#
# Scoped exception to ADR-004 (self-managed on-prem Connect): the source
# topic is in CC and the target is a SaaS lakehouse; no on-prem element
# exists in the pipeline.
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
# Local computed values
# ---------------------------------------------------------------------------
locals {
  # Connector name follows the same domain.application convention as topics
  connector_name = "lakehouse-${lower(var.sink_type)}-${var.source_topic_name}"

  # DLQ topic name (one DLQ per sink instance, not per source topic)
  dlq_topic_name = "lakehouse.dlq.${local.connector_name}"

  # Connector class string per sink_type
  connector_class_map = {
    DatabricksDeltaLakeSink = "DatabricksDeltaLakeSink"
    SnowflakeSink           = "SnowflakeSink"
  }
  connector_class = local.connector_class_map[var.sink_type]

  # Common config across both sink types
  common_config = {
    "topics"                                        = var.source_topic_name
    "input.data.format"                             = "AVRO"
    "input.key.format"                              = "STRING"
    "errors.tolerance"                              = "all"
    "errors.deadletterqueue.topic.name"             = local.dlq_topic_name
    "errors.deadletterqueue.context.headers.enable" = "true"
    "errors.log.enable"                             = "true"
    "errors.log.include.messages"                   = "false"
    "tasks.max"                                     = tostring(local.tasks_max)
  }

  # Sink-specific config -- built once per sink_type, merged with overrides
  databricks_config = var.sink_type == "DatabricksDeltaLakeSink" ? {
    "connector.class"            = "DatabricksDeltaLakeSink"
    "delta.lake.host.name"       = var.databricks_workspace_url
    "delta.lake.token"           = "$${secret:${var.credentials_secret_ref}}"
    "delta.lake.table.format"    = var.target_table
    "delta.lake.topic2table.map" = "${var.source_topic_name}:${var.target_table}"
    "auto.create"                = "false"
    "auto.evolve"                = tostring(var.auto_evolve)
    "flush.interval.ms"          = tostring(var.flush_interval_ms)
  } : {}

  snowflake_config = var.sink_type == "SnowflakeSink" ? {
    "connector.class"                 = "SnowflakeSink"
    "snowflake.url.name"              = var.snowflake_account_url
    "snowflake.user.name"             = var.snowflake_user
    "snowflake.private.key"           = "$${secret:${var.credentials_secret_ref}}"
    "snowflake.database.name"         = split(".", var.target_table)[0]
    "snowflake.schema.name"           = split(".", var.target_table)[1]
    "snowflake.topic2table.map"       = "${var.source_topic_name}:${split(".", var.target_table)[2]}"
    "snowflake.ingestion.method"      = "SNOWPIPE_STREAMING"
    "snowflake.enable.schematization" = tostring(var.enable_schematization)
  } : {}

  # Final config = common + sink-specific + user overrides
  connector_config = merge(
    local.common_config,
    local.databricks_config,
    local.snowflake_config,
    var.connector_overrides
  )

  # Task count derived from SLA tier (mirrors modules/topic partition logic)
  tasks_max_map = {
    critical    = 6
    standard    = 3
    best-effort = 1
    compliance  = 6
  }
  tasks_max = coalesce(
    var.tasks_max_override,
    lookup(local.tasks_max_map, var.sla_tier, 3)
  )
}

# ---------------------------------------------------------------------------
# Service Account for the connector identity
# ---------------------------------------------------------------------------
resource "confluent_service_account" "connector_sa" {
  display_name = "sa-${local.connector_name}"
  description  = "Connector identity for ${var.sink_type} sink reading ${var.source_topic_name}"
}

resource "confluent_api_key" "connector_key" {
  display_name = "key-${local.connector_name}"
  description  = "API key for ${local.connector_name}"

  owner {
    id          = confluent_service_account.connector_sa.id
    api_version = confluent_service_account.connector_sa.api_version
    kind        = confluent_service_account.connector_sa.kind
  }

  managed_resource {
    id          = var.kafka_cluster_id
    api_version = "cmk/v2"
    kind        = "Cluster"

    environment {
      id = var.environment_id
    }
  }
}

# ---------------------------------------------------------------------------
# RBAC -- DeveloperRead on source topic, DeveloperWrite on DLQ
# ---------------------------------------------------------------------------
resource "confluent_role_binding" "source_topic_read" {
  principal   = "User:${confluent_service_account.connector_sa.id}"
  role_name   = "DeveloperRead"
  crn_pattern = "${var.kafka_cluster_crn}/kafka=${var.kafka_cluster_id}/topic=${var.source_topic_name}"
}

resource "confluent_role_binding" "dlq_topic_write" {
  principal   = "User:${confluent_service_account.connector_sa.id}"
  role_name   = "DeveloperWrite"
  crn_pattern = "${var.kafka_cluster_crn}/kafka=${var.kafka_cluster_id}/topic=${local.dlq_topic_name}"
  depends_on  = [confluent_kafka_topic.dlq]
}

# Schema Registry read for AvroConverter on source topic
resource "confluent_role_binding" "sr_subject_read" {
  principal   = "User:${confluent_service_account.connector_sa.id}"
  role_name   = "DeveloperRead"
  crn_pattern = "${var.schema_registry_cluster_crn}/subject=${var.source_topic_name}-value"
}

# Consumer group read (connector internal consumer group)
resource "confluent_role_binding" "connector_group_read" {
  principal   = "User:${confluent_service_account.connector_sa.id}"
  role_name   = "DeveloperRead"
  crn_pattern = "${var.kafka_cluster_crn}/kafka=${var.kafka_cluster_id}/group=connect-${local.connector_name}-*"
}

# ---------------------------------------------------------------------------
# DLQ Topic -- one per sink, best-effort tier by default
# ---------------------------------------------------------------------------
resource "confluent_kafka_topic" "dlq" {
  kafka_cluster {
    id = var.kafka_cluster_id
  }
  topic_name       = local.dlq_topic_name
  partitions_count = 3

  config = {
    "retention.ms"     = tostring(var.dlq_retention_ms)
    "cleanup.policy"   = "delete"
    "compression.type" = "zstd"
  }

  rest_endpoint = var.kafka_rest_endpoint
  credentials {
    key    = var.kafka_api_key
    secret = var.kafka_api_secret
  }

  lifecycle {
    prevent_destroy = false # DLQ topics are operationally disposable
  }
}

# ---------------------------------------------------------------------------
# Managed Connector -- the resource that does the actual work
# ---------------------------------------------------------------------------
resource "confluent_connector" "this" {
  environment {
    id = var.environment_id
  }

  kafka_cluster {
    id = var.kafka_cluster_id
  }

  config_sensitive = {
    "kafka.api.key"    = confluent_api_key.connector_key.id
    "kafka.api.secret" = confluent_api_key.connector_key.secret
  }

  config_nonsensitive = merge(
    {
      "name"                                = local.connector_name
      "kafka.auth.mode"                     = "KAFKA_API_KEY"
      "schema.context.name"                 = "default"
      "value.converter"                     = "AVRO"
      "value.converter.schemas.enable"      = "true"
      "value.converter.schema.registry.url" = var.schema_registry_rest_endpoint
    },
    local.connector_config
  )

  depends_on = [
    confluent_role_binding.source_topic_read,
    confluent_role_binding.dlq_topic_write,
    confluent_role_binding.sr_subject_read,
    confluent_role_binding.connector_group_read,
    confluent_kafka_topic.dlq,
  ]

  lifecycle {
    precondition {
      condition     = contains(["DatabricksDeltaLakeSink", "SnowflakeSink"], var.sink_type)
      error_message = "sink_type must be one of: DatabricksDeltaLakeSink, SnowflakeSink."
    }
    precondition {
      condition     = var.credentials_secret_ref != ""
      error_message = "credentials_secret_ref is required (e.g., secret/fsi/databricks#token)."
    }
    precondition {
      condition = (
        var.sink_type != "DatabricksDeltaLakeSink"
        || (var.databricks_workspace_url != "" && length(split(".", var.target_table)) == 3)
      )
      error_message = "Databricks sink requires databricks_workspace_url and target_table in catalog.schema.table form."
    }
    precondition {
      condition = (
        var.sink_type != "SnowflakeSink"
        || (var.snowflake_account_url != "" && var.snowflake_user != "" && length(split(".", var.target_table)) == 3)
      )
      error_message = "Snowflake sink requires snowflake_account_url, snowflake_user, and target_table in DATABASE.SCHEMA.TABLE form."
    }
  }
}

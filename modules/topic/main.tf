# =============================================================================
# FSI Kafka Platform — Topic Module
# =============================================================================
# This is the single module teams use to create a fully governed Kafka topic.
# One module call produces: topic, schema, RBAC, metadata, DR mirror, alerts.
#
# Usage:
#   module "cncb_account_txn" {
#     source      = "../../modules/topic"
#     domain      = "cncb"
#     application = "core"
#     schema_version = "v1"
#     entity      = "account-transaction"
#     owner       = "cncb-team@fsi.org"
#     sla_tier    = "critical"
#     schema_file = "../../schemas/cncb-account-transaction.avsc"
#     pii_fields  = ["member_name", "ssn_last4", "account_number"]
#     producer_service_accounts = ["sa-cncb-producer"]
#     consumer_service_accounts = ["sa-cncb-consumer", "sa-rtfd-enrichment"]
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
# Local computed values
# ---------------------------------------------------------------------------
locals {
  # Assemble topic name from components
  topic_name = "${var.domain}.${var.application}.${var.schema_version}.${var.entity}"

  # Schema subject follows TopicNameStrategy
  value_subject = "${local.topic_name}-value"
  key_subject   = "${local.topic_name}-key"

  # Compatibility mode derived from SLA tier (override available)
  compatibility_map = {
    critical    = "FULL_TRANSITIVE"
    standard    = "BACKWARD_TRANSITIVE"
    best-effort = "BACKWARD"
    compliance  = "FULL_TRANSITIVE"    # Same as critical for audit integrity
  }
  compatibility = coalesce(
    var.compatibility_override,
    lookup(local.compatibility_map, var.sla_tier, "BACKWARD")
  )

  # Partition count derived from SLA tier (override available)
  partition_map = {
    critical    = 12
    standard    = 6
    best-effort = 3
    compliance  = 12                   # Same as critical for throughput
  }
  partitions = coalesce(
    var.partitions_override,
    lookup(local.partition_map, var.sla_tier, 6)
  )

  # Retention derived from SLA tier (override available, in ms)
  retention_map = {
    critical    = 604800000  # 7 days
    standard    = 259200000  # 3 days
    best-effort = 86400000   # 1 day
    # Compliance tier uses infinite retention; actual data lifecycle managed by archival platform
    compliance  = -1                   # Infinite retention for OFAC/AML/CFT regulatory compliance
  }
  retention_ms = coalesce(
    var.retention_ms_override,
    lookup(local.retention_map, var.sla_tier, 259200000)
  )

  # Schema metadata tags
  schema_metadata = {
    "owner"               = var.owner
    "sla-tier"            = var.sla_tier
    "data-classification" = var.data_classification
    "domain"              = var.domain
    "application"         = var.application
    "pii"                 = length(var.pii_fields) > 0 ? "true" : "false"
    "pii-fields"          = join(",", var.pii_fields)
  }
}

# ---------------------------------------------------------------------------
# Topic — Production (East)
# ---------------------------------------------------------------------------
resource "confluent_kafka_topic" "this" {
  kafka_cluster {
    id = var.kafka_cluster_id
  }

  topic_name       = local.topic_name
  partitions_count = local.partitions

  config = {
    "retention.ms"    = tostring(local.retention_ms)
    "cleanup.policy"  = var.cleanup_policy
    "compression.type" = "zstd"
  }

  rest_endpoint = var.kafka_rest_endpoint

  credentials {
    key    = var.kafka_api_key
    secret = var.kafka_api_secret
  }

  lifecycle {
    prevent_destroy = true
  }
}

# ---------------------------------------------------------------------------
# Schema — Value (Avro)
# ---------------------------------------------------------------------------
resource "confluent_schema" "value" {
  schema_registry_cluster {
    id = var.schema_registry_cluster_id
  }

  rest_endpoint = var.schema_registry_rest_endpoint

  credentials {
    key    = var.schema_registry_api_key
    secret = var.schema_registry_api_secret
  }

  subject_name = local.value_subject
  format       = "AVRO"
  schema       = file(var.schema_file)

  metadata {
    properties = local.schema_metadata
  }

  # Compatibility is set at the subject level
  depends_on = [confluent_kafka_topic.this]
}

# ---------------------------------------------------------------------------
# Subject compatibility mode
# ---------------------------------------------------------------------------
resource "confluent_subject_config" "value_compat" {
  schema_registry_cluster {
    id = var.schema_registry_cluster_id
  }

  rest_endpoint = var.schema_registry_rest_endpoint

  credentials {
    key    = var.schema_registry_api_key
    secret = var.schema_registry_api_secret
  }

  subject_name       = local.value_subject
  compatibility_level = local.compatibility

  depends_on = [confluent_schema.value]
}

# ---------------------------------------------------------------------------
# RBAC — Producer bindings
# ---------------------------------------------------------------------------
resource "confluent_role_binding" "producer" {
  for_each = toset(var.producer_service_accounts)

  principal   = "User:${each.value}"
  role_name   = "DeveloperWrite"
  crn_pattern = "${var.kafka_cluster_crn}/kafka=${var.kafka_cluster_id}/topic=${local.topic_name}"
}

# ---------------------------------------------------------------------------
# RBAC — Consumer bindings
# ---------------------------------------------------------------------------
resource "confluent_role_binding" "consumer" {
  for_each = toset(var.consumer_service_accounts)

  principal   = "User:${each.value}"
  role_name   = "DeveloperRead"
  crn_pattern = "${var.kafka_cluster_crn}/kafka=${var.kafka_cluster_id}/topic=${local.topic_name}"
}

# Consumer group bindings (consumers need read on their group)
resource "confluent_role_binding" "consumer_group" {
  for_each = toset(var.consumer_service_accounts)

  principal   = "User:${each.value}"
  role_name   = "DeveloperRead"
  crn_pattern = "${var.kafka_cluster_crn}/kafka=${var.kafka_cluster_id}/group=${each.value}-*"
}

# Schema Registry read for all producers and consumers
resource "confluent_role_binding" "sr_read" {
  for_each = toset(concat(var.producer_service_accounts, var.consumer_service_accounts))

  principal   = "User:${each.value}"
  role_name   = "DeveloperRead"
  crn_pattern = "${var.schema_registry_cluster_crn}/subject=${local.value_subject}"
}

# Schema Registry write for producers (to auto-register)
resource "confluent_role_binding" "sr_write" {
  for_each = toset(var.producer_service_accounts)

  principal   = "User:${each.value}"
  role_name   = "DeveloperWrite"
  crn_pattern = "${var.schema_registry_cluster_crn}/subject=${local.value_subject}"
}

# ---------------------------------------------------------------------------
# DR Mirror Topic (West cluster via Cluster Link)
# ---------------------------------------------------------------------------
resource "confluent_kafka_mirror_topic" "dr" {
  count = var.enable_dr_mirror ? 1 : 0

  source_kafka_topic {
    topic_name = local.topic_name
  }

  cluster_link {
    link_name = var.cluster_link_name
  }

  kafka_cluster {
    id            = var.dr_kafka_cluster_id
    rest_endpoint = var.dr_kafka_rest_endpoint

    credentials {
      key    = var.dr_kafka_api_key
      secret = var.dr_kafka_api_secret
    }
  }

  depends_on = [confluent_kafka_topic.this]
}

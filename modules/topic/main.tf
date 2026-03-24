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

  # Compliance retention: years-to-ms calculation (1 year = 365.25 * 24 * 60 * 60 * 1000 = 31557600000 ms)
  ms_per_year             = 31557600000
  compliance_retention_ms = var.retention_years == -1 ? -1 : var.retention_years * local.ms_per_year

  # Retention derived from SLA tier (override available, in ms)
  retention_map = {
    critical    = 604800000  # 7 days
    standard    = 259200000  # 3 days
    best-effort = 86400000   # 1 day
    # Compliance tier: uses retention_years variable for configurable regulatory retention
    compliance  = local.compliance_retention_ms
  }
  retention_ms = coalesce(
    var.retention_ms_override,
    lookup(local.retention_map, var.sla_tier, 259200000)
  )

  # Resolve effective SA IDs: created IDs when create mode, provided IDs when reference mode
  effective_producer_sa_ids = var.create_service_accounts ? [
    for sa in confluent_service_account.producer : sa.id
  ] : var.producer_service_accounts

  effective_consumer_sa_ids = var.create_service_accounts ? [
    for sa in confluent_service_account.consumer : sa.id
  ] : var.consumer_service_accounts

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
# Service Accounts — Conditional creation (per D-01, D-02)
# ---------------------------------------------------------------------------
resource "confluent_service_account" "producer" {
  for_each     = var.create_service_accounts ? toset(var.producer_sa_names) : toset([])
  display_name = each.value
  description  = "Producer SA for topic ${local.topic_name}"
}

resource "confluent_service_account" "consumer" {
  for_each     = var.create_service_accounts ? toset(var.consumer_sa_names) : toset([])
  display_name = each.value
  description  = "Consumer SA for topic ${local.topic_name}"
}

# ---------------------------------------------------------------------------
# CSFLE — Key Encryption Key (confidential topics only, per D-08)
# ---------------------------------------------------------------------------
resource "confluent_schema_registry_kek" "pii" {
  count = var.data_classification == "confidential" ? 1 : 0

  schema_registry_cluster {
    id = var.schema_registry_cluster_id
  }
  rest_endpoint = var.schema_registry_rest_endpoint
  credentials {
    key    = var.schema_registry_api_key
    secret = var.schema_registry_api_secret
  }

  name       = var.kek_name
  kms_type   = var.csfle_kms_type
  kms_key_id = var.csfle_kms_key_id
  shared     = var.csfle_shared_kek
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

    precondition {
      condition     = length(local.effective_producer_sa_ids) > 0
      error_message = "At least one producer SA is required. Set producer_service_accounts (reference mode) or producer_sa_names + create_service_accounts = true (create mode)."
    }
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

  # CSFLE encryption rules: only added for confidential topics (D-08)
  # WARNING: Do NOT define an empty ruleset {} block -- Confluent provider rejects it.
  dynamic "ruleset" {
    for_each = var.data_classification == "confidential" ? [1] : []
    content {
      domain_rules {
        name = "encryptPII"
        kind = "TRANSFORM"
        type = "ENCRYPT"
        mode = "WRITEREAD"
        tags = ["PII"]
        params = {
          "encrypt.kek.name" = var.kek_name
        }
      }
    }
  }

  # Compatibility is set at the subject level
  depends_on = [confluent_kafka_topic.this]

  lifecycle {
    # Confidential topic enforcement (D-09)
    precondition {
      condition     = var.data_classification != "confidential" || length(var.pii_fields) > 0
      error_message = "Confidential topics must specify at least one PII field in pii_fields."
    }
    precondition {
      condition     = var.data_classification != "confidential" || length(local.effective_consumer_sa_ids) > 0
      error_message = "Confidential topics must have at least one consumer SA (no open access)."
    }
    precondition {
      condition     = var.data_classification != "confidential" || var.kek_name != ""
      error_message = "Confidential topics require kek_name for CSFLE encryption."
    }
    precondition {
      condition     = var.data_classification != "confidential" || var.csfle_kms_type != ""
      error_message = "Confidential topics require csfle_kms_type (aws-kms, azure-kms, gcp-kms, or hcvault)."
    }
    precondition {
      condition     = var.data_classification != "confidential" || var.csfle_kms_key_id != ""
      error_message = "Confidential topics require csfle_kms_key_id (KMS key identifier)."
    }
  }
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
  for_each = toset(local.effective_producer_sa_ids)

  principal   = "User:${each.value}"
  role_name   = "DeveloperWrite"
  crn_pattern = "${var.kafka_cluster_crn}/kafka=${var.kafka_cluster_id}/topic=${local.topic_name}"
}

# ---------------------------------------------------------------------------
# RBAC — Consumer bindings
# ---------------------------------------------------------------------------
resource "confluent_role_binding" "consumer" {
  for_each = toset(local.effective_consumer_sa_ids)

  principal   = "User:${each.value}"
  role_name   = "DeveloperRead"
  crn_pattern = "${var.kafka_cluster_crn}/kafka=${var.kafka_cluster_id}/topic=${local.topic_name}"
}

# Consumer group bindings (consumers need read on their group)
resource "confluent_role_binding" "consumer_group" {
  for_each = toset(local.effective_consumer_sa_ids)

  principal   = "User:${each.value}"
  role_name   = "DeveloperRead"
  crn_pattern = "${var.kafka_cluster_crn}/kafka=${var.kafka_cluster_id}/group=${each.value}-*"
}

# Schema Registry read for all producers and consumers
resource "confluent_role_binding" "sr_read" {
  for_each = toset(concat(local.effective_producer_sa_ids, local.effective_consumer_sa_ids))

  principal   = "User:${each.value}"
  role_name   = "DeveloperRead"
  crn_pattern = "${var.schema_registry_cluster_crn}/subject=${local.value_subject}"
}

# Schema Registry write for producers (to auto-register)
resource "confluent_role_binding" "sr_write" {
  for_each = toset(local.effective_producer_sa_ids)

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

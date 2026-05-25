# =============================================================================
# FSI Kafka Platform -- Database Connector Module
# =============================================================================
# Polymorphic module producing a fully governed Confluent Cloud managed
# connector for an operational database: connector + service account +
# RBAC + DLQ topic.
#
# Supported (db_type, direction) combinations per ADR-012:
#   - (mongodb,     source)  MongoSourceConnector  (change streams)
#   - (mongodb,     sink)    MongoSinkConnector
#   - (redis,       sink)    RedisSinkConnector
#   - (cockroachdb, sink)    JdbcSinkConnector with Postgres driver, port 26257
#   - (postgres,    source)  Debezium PostgresConnector (logical decoding)
#   - (postgres,    sink)    JdbcSinkConnector
#
# Rejected combinations (validated in lifecycle.precondition):
#   - (redis,       source)  Redis is a cache, not a source of truth
#   - (cockroachdb, source)  Use the native CREATE CHANGEFEED SQL instead.
#                            See docs/cockroachdb-integration-guide.md.
#
# Scoped exception to ADR-004 parallel to ADR-011: the source cluster is
# CC and the target is a SaaS database. Self-managed deployments use the
# JSON templates under reference/connect-configs/ and the ansible/roles/
# cp_<db> roles.
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
  # Connector name -- distinct prefix from lakehouse to avoid collisions
  # in dashboard auto-discovery (lakehouse-* vs database-*).
  topic_or_pattern = var.direction == "sink" ? var.source_topic_name : var.target_topic_pattern
  # Slugify: replace dots (and any trailing dot leftover from a pattern like
  # corebanking.transactions.v1.) with dashes so the connector name is
  # RFC-1123-safe for CC connector IDs and K8s labels.
  connector_name_raw = "database-${var.db_type}-${var.direction}-${replace(local.topic_or_pattern, ".", "-")}"
  connector_name     = trim(local.connector_name_raw, "-")

  # DLQ topic name (one DLQ per connector instance)
  dlq_topic_name = "database.dlq.${local.connector_name}"

  # Connector class lookup table
  connector_class_map = {
    "mongodb-source"     = "MongoDbAtlasSource"        # CC managed-connector class
    "mongodb-sink"       = "MongoDbAtlasSink"
    "redis-sink"         = "RedisSink"
    "cockroachdb-sink"   = "PostgresSink"              # CC's managed JDBC sink that targets pg-wire (works for CRDB)
    "postgres-source"    = "PostgresCdcSourceV2"       # CC's managed Debezium-based source
    "postgres-sink"      = "PostgresSink"
  }
  combo_key       = "${var.db_type}-${var.direction}"
  connector_class = lookup(local.connector_class_map, local.combo_key, "INVALID")

  # Common config across every legal combination
  common_config = {
    "errors.tolerance"                              = "all"
    "errors.deadletterqueue.topic.name"             = local.dlq_topic_name
    "errors.deadletterqueue.context.headers.enable" = "true"
    "errors.log.enable"                             = "true"
    "errors.log.include.messages"                   = "false"
    "tasks.max"                                     = tostring(local.tasks_max)
    "output.data.format"                            = "AVRO"
    "input.data.format"                             = "AVRO"
    "input.key.format"                              = "STRING"
  }

  # ---- MongoDB source ----
  mongodb_source_config = local.combo_key == "mongodb-source" ? {
    "connector.class"                = "MongoDbAtlasSource"
    "connection.host"                = var.source_db_url
    "connection.user"                = "$${secret:${var.credentials_secret_ref}}"
    "database"                       = var.mongodb_database
    "collection"                     = var.mongodb_collection
    "output.format.value"            = "schema"
    "change.stream.full.document"    = "updateLookup"
    "topic.prefix"                   = var.target_topic_pattern
    "publish.full.document.only"     = "false"
  } : {}

  # ---- MongoDB sink ----
  mongodb_sink_config = local.combo_key == "mongodb-sink" ? {
    "connector.class"            = "MongoDbAtlasSink"
    "connection.host"            = var.target_db_url
    "connection.user"            = "$${secret:${var.credentials_secret_ref}}"
    "database"                   = var.mongodb_database
    "collection"                 = var.mongodb_collection
    "topics"                     = var.source_topic_name
    "doc.id.strategy"            = "com.mongodb.kafka.connect.sink.processor.id.strategy.KafkaMetaDataStrategy"
    "writemodel.strategy"        = "com.mongodb.kafka.connect.sink.writemodel.strategy.UpdateOneTimestampsStrategy"
    "delete.on.null.values"      = "true"
  } : {}

  # ---- Redis sink ----
  redis_sink_config = local.combo_key == "redis-sink" ? {
    "connector.class"           = "RedisSink"
    "redis.hosts"               = var.target_db_url
    "redis.password"            = "$${secret:${var.credentials_secret_ref}}"
    "redis.client.mode"         = var.redis_client_mode
    "topics"                    = var.source_topic_name
    "redis.key.prefix"          = var.redis_key_prefix
    "redis.expiration.time"     = tostring(var.redis_ttl_seconds)
    "tls.enabled"               = "true"
  } : {}

  # ---- CockroachDB sink (uses CC PostgresSink connector class -- wire compatible) ----
  cockroachdb_sink_config = local.combo_key == "cockroachdb-sink" ? {
    "connector.class"           = "PostgresSink"
    "connection.host"           = var.target_db_url
    "connection.port"           = "26257"
    "connection.user"           = "$${secret:${var.credentials_secret_ref}}"
    "db.name"                   = var.jdbc_database
    "ssl.mode"                  = "verify-full"
    "topics"                    = var.source_topic_name
    "table.name.format"         = var.jdbc_table_name
    "insert.mode"               = "UPSERT"
    "pk.mode"                   = "record_value"
    "pk.fields"                 = var.jdbc_pk_fields
    "auto.create"               = "false"
    "auto.evolve"               = "false"
  } : {}

  # ---- Postgres source (Debezium-based via CC managed connector) ----
  postgres_source_config = local.combo_key == "postgres-source" ? {
    "connector.class"           = "PostgresCdcSourceV2"
    "database.hostname"         = var.source_db_url
    "database.port"             = "5432"
    "database.user"             = "$${secret:${var.credentials_secret_ref}}"
    "database.dbname"           = var.postgres_database
    "database.sslmode"          = "verify-full"
    "publication.name"          = var.postgres_publication
    "slot.name"                 = var.postgres_slot_name
    "plugin.name"               = "pgoutput"
    "publication.autocreate.mode" = "disabled"
    "topic.prefix"              = var.target_topic_pattern
    "tombstones.on.delete"      = "true"
  } : {}

  # ---- Postgres sink ----
  postgres_sink_config = local.combo_key == "postgres-sink" ? {
    "connector.class"           = "PostgresSink"
    "connection.host"           = var.target_db_url
    "connection.port"           = "5432"
    "connection.user"           = "$${secret:${var.credentials_secret_ref}}"
    "db.name"                   = var.jdbc_database
    "ssl.mode"                  = "verify-full"
    "topics"                    = var.source_topic_name
    "table.name.format"         = var.jdbc_table_name
    "insert.mode"               = "UPSERT"
    "pk.mode"                   = "record_value"
    "pk.fields"                 = var.jdbc_pk_fields
    "auto.create"               = "false"
    "auto.evolve"               = "false"
  } : {}

  # Final config: common + the single matching block + user overrides
  connector_config = merge(
    local.common_config,
    local.mongodb_source_config,
    local.mongodb_sink_config,
    local.redis_sink_config,
    local.cockroachdb_sink_config,
    local.postgres_source_config,
    local.postgres_sink_config,
    var.connector_overrides
  )

  # SLA-tier-derived tasks.max (CDC sources favor fewer tasks for ordering;
  # sinks favor more for throughput)
  tasks_max_map_sink = {
    critical    = 6
    standard    = 3
    best-effort = 1
    compliance  = 6
  }
  tasks_max_map_source = {
    critical    = 4
    standard    = 2
    best-effort = 1
    compliance  = 4
  }
  tasks_max_map = var.direction == "sink" ? local.tasks_max_map_sink : local.tasks_max_map_source
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
  description  = "Connector identity for ${var.db_type} ${var.direction} -- ${local.topic_or_pattern}"
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
# RBAC -- direction-dependent
# ---------------------------------------------------------------------------
# Sinks: DeveloperRead on source topic, DeveloperWrite on DLQ.
# Sources: DeveloperWrite on target topic pattern (PREFIXED for Debezium
# which emits to multiple topics), DeveloperWrite on DLQ.
# ---------------------------------------------------------------------------

# Sink: read source topic
resource "confluent_role_binding" "source_topic_read" {
  count       = var.direction == "sink" ? 1 : 0
  principal   = "User:${confluent_service_account.connector_sa.id}"
  role_name   = "DeveloperRead"
  crn_pattern = "${var.kafka_cluster_crn}/kafka=${var.kafka_cluster_id}/topic=${var.source_topic_name}"
}

# Source: write to target topic pattern (PREFIXED -- Debezium emits per-table topics)
resource "confluent_role_binding" "target_topic_write" {
  count       = var.direction == "source" ? 1 : 0
  principal   = "User:${confluent_service_account.connector_sa.id}"
  role_name   = "DeveloperWrite"
  crn_pattern = "${var.kafka_cluster_crn}/kafka=${var.kafka_cluster_id}/topic=${var.target_topic_pattern}*"
}

# Both directions: write to DLQ
resource "confluent_role_binding" "dlq_topic_write" {
  principal   = "User:${confluent_service_account.connector_sa.id}"
  role_name   = "DeveloperWrite"
  crn_pattern = "${var.kafka_cluster_crn}/kafka=${var.kafka_cluster_id}/topic=${local.dlq_topic_name}"
  depends_on  = [confluent_kafka_topic.dlq]
}

# SR access -- sinks read source-topic subject; sources write target-topic subject
resource "confluent_role_binding" "sr_subject_read" {
  count       = var.direction == "sink" ? 1 : 0
  principal   = "User:${confluent_service_account.connector_sa.id}"
  role_name   = "DeveloperRead"
  crn_pattern = "${var.schema_registry_cluster_crn}/subject=${var.source_topic_name}-value"
}

resource "confluent_role_binding" "sr_subject_write" {
  count       = var.direction == "source" ? 1 : 0
  principal   = "User:${confluent_service_account.connector_sa.id}"
  role_name   = "DeveloperWrite"
  crn_pattern = "${var.schema_registry_cluster_crn}/subject=${var.target_topic_pattern}*"
}

# Consumer group read for sinks (connector internal consumer group)
resource "confluent_role_binding" "connector_group_read" {
  count       = var.direction == "sink" ? 1 : 0
  principal   = "User:${confluent_service_account.connector_sa.id}"
  role_name   = "DeveloperRead"
  crn_pattern = "${var.kafka_cluster_crn}/kafka=${var.kafka_cluster_id}/group=connect-${local.connector_name}-*"
}

# ---------------------------------------------------------------------------
# DLQ Topic
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
# Managed Connector
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
      "name"                                 = local.connector_name
      "kafka.auth.mode"                      = "KAFKA_API_KEY"
      "schema.context.name"                  = "default"
      "value.converter"                      = "AVRO"
      "value.converter.schemas.enable"       = "true"
      "value.converter.schema.registry.url"  = var.schema_registry_rest_endpoint
    },
    local.connector_config
  )

  depends_on = [
    confluent_role_binding.dlq_topic_write,
    confluent_kafka_topic.dlq,
  ]

  lifecycle {
    precondition {
      condition     = contains(["mongodb", "redis", "cockroachdb", "postgres"], var.db_type)
      error_message = "db_type must be one of: mongodb, redis, cockroachdb, postgres."
    }
    precondition {
      condition     = contains(["source", "sink"], var.direction)
      error_message = "direction must be source or sink."
    }
    precondition {
      condition     = !(var.db_type == "redis" && var.direction == "source")
      error_message = "Redis source is not supported -- Redis is a cache, not a source of truth (ADR-012)."
    }
    precondition {
      condition     = !(var.db_type == "cockroachdb" && var.direction == "source")
      error_message = "CockroachDB source is not supported via this module -- use the native CREATE CHANGEFEED SQL instead. See docs/cockroachdb-integration-guide.md."
    }
    precondition {
      condition     = local.connector_class != "INVALID"
      error_message = "Invalid (db_type, direction) combination -- no connector class mapped."
    }
    precondition {
      condition     = var.credentials_secret_ref != ""
      error_message = "credentials_secret_ref is required (e.g., secret/fsi/mongodb#connection_uri)."
    }
    precondition {
      condition     = var.direction != "sink" || var.source_topic_name != ""
      error_message = "Sinks require source_topic_name."
    }
    precondition {
      condition     = var.direction != "source" || var.target_topic_pattern != ""
      error_message = "Sources require target_topic_pattern."
    }
  }
}

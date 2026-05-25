# =============================================================================
# Database Connector Declarations -- CC-managed MongoDB / Redis / CRDB / Postgres
# =============================================================================
# Scoped exception to ADR-004 (parallel to ADR-011): these connectors are
# CC-managed because the source cluster is CC and the target is a SaaS
# database. No on-prem element in the pipeline.
#
# For self-managed CP/CFK/LinuxONE deployments, see:
#   - reference/connect-configs/{mongodb,redis,cockroachdb,postgres}-*.json
#   - ansible/playbooks/deploy-database-connectors.yml
#   - accelerators/confluent-on-linuxone/layers/07-database-connectors/
#
# For CockroachDB CDC source, see docs/cockroachdb-integration-guide.md
# (path A -- native CREATE CHANGEFEED, runs inside CRDB, no module here).
# =============================================================================

# ---------------------------------------------------------------------------
# MongoDB sink: corebanking transactions -> MongoDB Atlas collection
# ---------------------------------------------------------------------------
module "corebanking_to_mongodb" {
  source = "../../modules/db_connector"

  db_type                = "mongodb"
  direction              = "sink"
  source_topic_name      = module.corebanking_account_txn.topic_name
  target_db_url          = var.mongodb_atlas_host
  credentials_secret_ref = "secret/fsi/mongodb#connection_uri"
  sla_tier               = "critical"

  mongodb_database   = "kafka_corebanking"
  mongodb_collection = "account_transaction"

  environment_id                = var.environment_id
  kafka_cluster_id              = local.infra.kafka_cluster_id
  kafka_cluster_crn             = local.infra.kafka_cluster_crn
  kafka_rest_endpoint           = local.infra.kafka_rest_endpoint
  kafka_api_key                 = var.kafka_api_key
  kafka_api_secret              = var.kafka_api_secret
  schema_registry_cluster_crn   = local.infra.sr_cluster_crn
  schema_registry_rest_endpoint = local.infra.sr_rest_endpoint
}

# ---------------------------------------------------------------------------
# MongoDB source: member-profile change streams -> Kafka
# ---------------------------------------------------------------------------
module "member_updates_from_mongodb_atlas" {
  source = "../../modules/db_connector"

  db_type                = "mongodb"
  direction              = "source"
  target_topic_pattern   = "corebanking.transactions.v1.member-update"
  source_db_url          = var.mongodb_atlas_host
  credentials_secret_ref = "secret/fsi/mongodb#connection_uri"
  sla_tier               = "standard"

  mongodb_database   = "corebanking"
  mongodb_collection = "member_profile"

  environment_id                = var.environment_id
  kafka_cluster_id              = local.infra.kafka_cluster_id
  kafka_cluster_crn             = local.infra.kafka_cluster_crn
  kafka_rest_endpoint           = local.infra.kafka_rest_endpoint
  kafka_api_key                 = var.kafka_api_key
  kafka_api_secret              = var.kafka_api_secret
  schema_registry_cluster_crn   = local.infra.sr_cluster_crn
  schema_registry_rest_endpoint = local.infra.sr_rest_endpoint
}

# ---------------------------------------------------------------------------
# Redis sink: compliance screening results -> Redis hot cache
# ---------------------------------------------------------------------------
module "compliance_to_redis_cache" {
  source = "../../modules/db_connector"

  db_type                = "redis"
  direction              = "sink"
  source_topic_name      = module.compliance_screening_result.topic_name
  target_db_url          = var.redis_cache_url
  credentials_secret_ref = "secret/fsi/redis#password"
  sla_tier               = "best-effort"

  redis_client_mode = "Standalone"
  redis_key_prefix  = "compliance:screening:"
  redis_ttl_seconds = 3600

  environment_id                = var.environment_id
  kafka_cluster_id              = local.infra.kafka_cluster_id
  kafka_cluster_crn             = local.infra.kafka_cluster_crn
  kafka_rest_endpoint           = local.infra.kafka_rest_endpoint
  kafka_api_key                 = var.kafka_api_key
  kafka_api_secret              = var.kafka_api_secret
  schema_registry_cluster_crn   = local.infra.sr_cluster_crn
  schema_registry_rest_endpoint = local.infra.sr_rest_endpoint
}

# ---------------------------------------------------------------------------
# CockroachDB sink: corebanking transactions -> CRDB (via JDBC, port 26257)
# ---------------------------------------------------------------------------
module "corebanking_to_cockroachdb" {
  source = "../../modules/db_connector"

  db_type                = "cockroachdb"
  direction              = "sink"
  source_topic_name      = module.corebanking_account_txn.topic_name
  target_db_url          = var.cockroachdb_host
  credentials_secret_ref = "secret/fsi/cockroachdb#password"
  sla_tier               = "critical"

  jdbc_database   = "banking"
  jdbc_table_name = "kafka_account_transaction"
  jdbc_pk_fields  = "transaction_id"

  environment_id                = var.environment_id
  kafka_cluster_id              = local.infra.kafka_cluster_id
  kafka_cluster_crn             = local.infra.kafka_cluster_crn
  kafka_rest_endpoint           = local.infra.kafka_rest_endpoint
  kafka_api_key                 = var.kafka_api_key
  kafka_api_secret              = var.kafka_api_secret
  schema_registry_cluster_crn   = local.infra.sr_cluster_crn
  schema_registry_rest_endpoint = local.infra.sr_rest_endpoint
}

# ---------------------------------------------------------------------------
# Postgres CDC source: banking schema -> Kafka (Debezium via pgoutput)
# ---------------------------------------------------------------------------
module "corebanking_from_postgres_cdc" {
  source = "../../modules/db_connector"

  db_type                = "postgres"
  direction              = "source"
  target_topic_pattern   = "corebanking.transactions.v1."
  source_db_url          = var.postgres_primary_host
  credentials_secret_ref = "secret/fsi/postgres#password"
  sla_tier               = "critical"

  postgres_database    = "banking"
  postgres_publication = "fsi_kafka_publication"
  postgres_slot_name   = "fsi_kafka_prod"

  environment_id                = var.environment_id
  kafka_cluster_id              = local.infra.kafka_cluster_id
  kafka_cluster_crn             = local.infra.kafka_cluster_crn
  kafka_rest_endpoint           = local.infra.kafka_rest_endpoint
  kafka_api_key                 = var.kafka_api_key
  kafka_api_secret              = var.kafka_api_secret
  schema_registry_cluster_crn   = local.infra.sr_cluster_crn
  schema_registry_rest_endpoint = local.infra.sr_rest_endpoint
}

# ---------------------------------------------------------------------------
# Postgres sink: compliance results -> reporting Postgres
# ---------------------------------------------------------------------------
module "compliance_to_postgres_reporting" {
  source = "../../modules/db_connector"

  db_type                = "postgres"
  direction              = "sink"
  source_topic_name      = module.compliance_screening_result.topic_name
  target_db_url          = var.postgres_reporting_host
  credentials_secret_ref = "secret/fsi/postgres#password"
  sla_tier               = "standard"

  jdbc_database   = "reporting"
  jdbc_table_name = "compliance_screening_result"
  jdbc_pk_fields  = "match_id"

  environment_id                = var.environment_id
  kafka_cluster_id              = local.infra.kafka_cluster_id
  kafka_cluster_crn             = local.infra.kafka_cluster_crn
  kafka_rest_endpoint           = local.infra.kafka_rest_endpoint
  kafka_api_key                 = var.kafka_api_key
  kafka_api_secret              = var.kafka_api_secret
  schema_registry_cluster_crn   = local.infra.sr_cluster_crn
  schema_registry_rest_endpoint = local.infra.sr_rest_endpoint
}

# ---------------------------------------------------------------------------
# Variables specific to database connectors
# ---------------------------------------------------------------------------
variable "mongodb_atlas_host" {
  description = "MongoDB Atlas connection host (e.g., cluster0.abcde.mongodb.net). Auth via connection URI in Vault."
  type        = string
}

variable "redis_cache_url" {
  description = "Redis cache endpoint URL (e.g., rediss://redis-prod.fsi.internal:6380)"
  type        = string
}

variable "cockroachdb_host" {
  description = "CockroachDB primary host (port 26257 assumed)"
  type        = string
}

variable "postgres_primary_host" {
  description = "PostgreSQL primary host (CDC source -- requires logical replication slot)"
  type        = string
}

variable "postgres_reporting_host" {
  description = "PostgreSQL reporting host (JDBC sink target)"
  type        = string
}

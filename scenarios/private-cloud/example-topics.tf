# =============================================================================
# Example Topic Declarations -- Copy and adapt for your applications
# =============================================================================
# Private Cloud scenario reuses the shared governance module -- identical topic
# naming, schema compat, RBAC, and SLA-tier enforcement as CC and CFK scenarios.

module "corebanking_account_txn" {
  source         = "../../modules/topic"
  domain         = "corebanking"
  application    = "transactions"
  schema_version = "v1"
  entity         = "account-transaction"
  owner          = "core-banking-team@company.com"
  sla_tier       = "critical"
  schema_file    = "../../schemas/examples/account-transaction.avsc"
  pii_fields     = ["member_name", "ssn_last4", "account_number"]
  producer_service_accounts = ["sa-corebanking-producer"]
  consumer_service_accounts = ["sa-corebanking-consumer", "sa-fraud-enrichment"]

  kafka_cluster_id               = local.infra.kafka_cluster_id
  kafka_rest_endpoint            = local.infra.kafka_rest_endpoint
  kafka_api_key                  = var.cp_kafka_api_key
  kafka_api_secret               = var.cp_kafka_api_secret
  kafka_cluster_crn              = local.infra.kafka_cluster_crn
  schema_registry_cluster_id     = local.infra.sr_cluster_id
  schema_registry_rest_endpoint  = local.infra.sr_rest_endpoint
  schema_registry_api_key        = var.cp_sr_api_key
  schema_registry_api_secret     = var.cp_sr_api_secret
  schema_registry_cluster_crn    = local.infra.sr_cluster_crn
  cluster_link_name              = local.infra.cluster_link_name
  dr_kafka_cluster_id            = local.infra.dr_kafka_cluster_id
  dr_kafka_rest_endpoint         = local.infra.dr_kafka_rest_endpoint
  dr_kafka_api_key               = ""
  dr_kafka_api_secret            = ""
}

module "fraud_alert_signal" {
  source         = "../../modules/topic"
  domain         = "fraud"
  application    = "detection"
  schema_version = "v1"
  entity         = "alert-signal"
  owner          = "fraud-team@company.com"
  sla_tier       = "critical"
  schema_file    = "../../schemas/examples/fraud-alert-signal.avsc"
  pii_fields     = ["member_id", "account_number"]
  producer_service_accounts = ["sa-fraud-producer"]
  consumer_service_accounts = ["sa-fraud-investigator", "sa-corebanking-consumer"]

  kafka_cluster_id               = local.infra.kafka_cluster_id
  kafka_rest_endpoint            = local.infra.kafka_rest_endpoint
  kafka_api_key                  = var.cp_kafka_api_key
  kafka_api_secret               = var.cp_kafka_api_secret
  kafka_cluster_crn              = local.infra.kafka_cluster_crn
  schema_registry_cluster_id     = local.infra.sr_cluster_id
  schema_registry_rest_endpoint  = local.infra.sr_rest_endpoint
  schema_registry_api_key        = var.cp_sr_api_key
  schema_registry_api_secret     = var.cp_sr_api_secret
  schema_registry_cluster_crn    = local.infra.sr_cluster_crn
  cluster_link_name              = local.infra.cluster_link_name
  dr_kafka_cluster_id            = local.infra.dr_kafka_cluster_id
  dr_kafka_rest_endpoint         = local.infra.dr_kafka_rest_endpoint
  dr_kafka_api_key               = ""
  dr_kafka_api_secret            = ""
}

module "compliance_screening_result" {
  source               = "../../modules/topic"
  domain               = "compliance"
  application          = "screening"
  schema_version       = "v1"
  entity               = "match-result"
  owner                = "compliance-team@company.com"
  sla_tier             = "standard"
  compatibility_override = "FULL_TRANSITIVE"     # Audit/compliance override
  schema_file          = "../../schemas/examples/compliance-match-result.avsc"
  pii_fields           = ["member_name", "matched_name"]
  producer_service_accounts = ["sa-compliance-producer"]
  consumer_service_accounts = ["sa-compliance-reviewer"]

  kafka_cluster_id               = local.infra.kafka_cluster_id
  kafka_rest_endpoint            = local.infra.kafka_rest_endpoint
  kafka_api_key                  = var.cp_kafka_api_key
  kafka_api_secret               = var.cp_kafka_api_secret
  kafka_cluster_crn              = local.infra.kafka_cluster_crn
  schema_registry_cluster_id     = local.infra.sr_cluster_id
  schema_registry_rest_endpoint  = local.infra.sr_rest_endpoint
  schema_registry_api_key        = var.cp_sr_api_key
  schema_registry_api_secret     = var.cp_sr_api_secret
  schema_registry_cluster_crn    = local.infra.sr_cluster_crn
  cluster_link_name              = local.infra.cluster_link_name
  dr_kafka_cluster_id            = local.infra.dr_kafka_cluster_id
  dr_kafka_rest_endpoint         = local.infra.dr_kafka_rest_endpoint
  dr_kafka_api_key               = ""
  dr_kafka_api_secret            = ""
}

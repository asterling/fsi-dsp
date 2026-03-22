# =============================================================================
# Example Topic Declarations — Copy and adapt for your applications
# =============================================================================

module "corebanking_account_txn" {
  source      = "../../modules/topic"
  domain      = "corebanking"
  application = "transactions"
  version     = "v1"
  entity      = "account-transaction"
  owner       = "core-banking-team@company.com"
  sla_tier    = "critical"
  schema_file = "../../schemas/examples/account-transaction.avsc"
  pii_fields  = ["member_name", "ssn_last4", "account_number"]
  producer_service_accounts = ["sa-corebanking-producer"]
  consumer_service_accounts = ["sa-corebanking-consumer", "sa-fraud-enrichment"]

  kafka_cluster_id = local.infra.kafka_cluster_id
  kafka_rest_endpoint = local.infra.kafka_rest_endpoint
  kafka_api_key = var.kafka_api_key; kafka_api_secret = var.kafka_api_secret
  kafka_cluster_crn = local.infra.kafka_cluster_crn
  sr_cluster_id = local.infra.sr_cluster_id
  sr_rest_endpoint = local.infra.sr_rest_endpoint
  sr_api_key = var.sr_api_key; sr_api_secret = var.sr_api_secret
  sr_cluster_crn = local.infra.sr_cluster_crn
  cluster_link_name = local.infra.cluster_link_name
  dr_kafka_cluster_id = local.infra.dr_kafka_cluster_id
  dr_kafka_rest_endpoint = local.infra.dr_kafka_rest_endpoint
  dr_kafka_api_key = var.dr_kafka_api_key; dr_kafka_api_secret = var.dr_kafka_api_secret
}

module "fraud_alert_signal" {
  source      = "../../modules/topic"
  domain      = "fraud"
  application = "detection"
  version     = "v1"
  entity      = "alert-signal"
  owner       = "fraud-team@company.com"
  sla_tier    = "critical"
  schema_file = "../../schemas/examples/fraud-alert-signal.avsc"
  pii_fields  = ["member_id", "account_number"]
  producer_service_accounts = ["sa-fraud-producer"]
  consumer_service_accounts = ["sa-fraud-investigator", "sa-corebanking-consumer"]

  kafka_cluster_id = local.infra.kafka_cluster_id
  kafka_rest_endpoint = local.infra.kafka_rest_endpoint
  kafka_api_key = var.kafka_api_key; kafka_api_secret = var.kafka_api_secret
  kafka_cluster_crn = local.infra.kafka_cluster_crn
  sr_cluster_id = local.infra.sr_cluster_id
  sr_rest_endpoint = local.infra.sr_rest_endpoint
  sr_api_key = var.sr_api_key; sr_api_secret = var.sr_api_secret
  sr_cluster_crn = local.infra.sr_cluster_crn
  cluster_link_name = local.infra.cluster_link_name
  dr_kafka_cluster_id = local.infra.dr_kafka_cluster_id
  dr_kafka_rest_endpoint = local.infra.dr_kafka_rest_endpoint
  dr_kafka_api_key = var.dr_kafka_api_key; dr_kafka_api_secret = var.dr_kafka_api_secret
}

module "compliance_screening_result" {
  source      = "../../modules/topic"
  domain      = "compliance"
  application = "screening"
  version     = "v1"
  entity      = "match-result"
  owner       = "compliance-team@company.com"
  sla_tier    = "standard"
  compatibility_override = "FULL_TRANSITIVE"     # Audit/compliance override
  schema_file = "../../schemas/examples/compliance-match-result.avsc"
  pii_fields  = ["member_name", "matched_name"]
  producer_service_accounts = ["sa-compliance-producer"]
  consumer_service_accounts = ["sa-compliance-reviewer"]

  kafka_cluster_id = local.infra.kafka_cluster_id
  kafka_rest_endpoint = local.infra.kafka_rest_endpoint
  kafka_api_key = var.kafka_api_key; kafka_api_secret = var.kafka_api_secret
  kafka_cluster_crn = local.infra.kafka_cluster_crn
  sr_cluster_id = local.infra.sr_cluster_id
  sr_rest_endpoint = local.infra.sr_rest_endpoint
  sr_api_key = var.sr_api_key; sr_api_secret = var.sr_api_secret
  sr_cluster_crn = local.infra.sr_cluster_crn
  cluster_link_name = local.infra.cluster_link_name
  dr_kafka_cluster_id = local.infra.dr_kafka_cluster_id
  dr_kafka_rest_endpoint = local.infra.dr_kafka_rest_endpoint
  dr_kafka_api_key = var.dr_kafka_api_key; dr_kafka_api_secret = var.dr_kafka_api_secret
}

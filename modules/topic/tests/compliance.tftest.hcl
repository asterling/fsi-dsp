# =============================================================================
# Compliance Tests -- Retention years and CSFLE enforcement
# =============================================================================
# Validates compliance retention calculation (D-11) and confidential topic
# constraints (D-08, D-09) for CSFLE encryption enforcement.

mock_provider "confluent" {}

variables {
  domain                         = "testdomain"
  application                    = "testapp"
  schema_version                 = "v1"
  entity                         = "test-entity"
  owner                          = "test@fsi.org"
  sla_tier                       = "compliance"
  schema_file                    = "../../../schemas/examples/account-transaction.avsc"
  pii_fields                     = ["account_number"]
  create_service_accounts        = false
  producer_service_accounts      = ["sa-test-producer"]
  consumer_service_accounts      = ["sa-test-consumer"]
  kafka_cluster_id               = "lkc-test"
  kafka_rest_endpoint            = "https://test.confluent.cloud:443"
  kafka_api_key                  = "test-key"
  kafka_api_secret               = "test-secret"
  kafka_cluster_crn              = "crn://confluent.cloud/organization=test/environment=test/cloud-cluster=lkc-test"
  schema_registry_cluster_id     = "lsrc-test"
  schema_registry_rest_endpoint  = "https://test-sr.confluent.cloud"
  schema_registry_api_key        = "test-sr-key"
  schema_registry_api_secret     = "test-sr-secret"
  schema_registry_cluster_crn    = "crn://confluent.cloud/organization=test/environment=test/schema-registry=lsrc-test"
}

# ---------------------------------------------------------------------------
# Compliance tier: default infinite retention (retention_years = -1)
# ---------------------------------------------------------------------------
run "compliance_tier_default_infinite_retention" {
  command = plan

  assert {
    condition     = output.retention_ms == -1
    error_message = "Compliance tier with default retention_years (-1) must use infinite retention."
  }
}

# ---------------------------------------------------------------------------
# Compliance tier: 7-year retention (7 * 31557600000 = 220903200000)
# ---------------------------------------------------------------------------
run "compliance_tier_seven_year_retention" {
  command = plan

  variables {
    retention_years = 7
  }

  assert {
    condition     = output.retention_ms == 220903200000
    error_message = "Compliance tier with retention_years=7 must calculate 220903200000 ms."
  }
}

# ---------------------------------------------------------------------------
# Compliance tier: 10-year retention (10 * 31557600000 = 315576000000)
# ---------------------------------------------------------------------------
run "compliance_tier_ten_year_retention" {
  command = plan

  variables {
    retention_years = 10
  }

  assert {
    condition     = output.retention_ms == 315576000000
    error_message = "Compliance tier with retention_years=10 must calculate 315576000000 ms."
  }
}

# ---------------------------------------------------------------------------
# Compliance tier: retention below 7 years rejected
# ---------------------------------------------------------------------------
run "compliance_retention_below_seven_rejected" {
  command = plan

  variables {
    retention_years = 3
  }

  expect_failures = [var.retention_years]
}

# ---------------------------------------------------------------------------
# Confidential topic: missing pii_fields rejected
# ---------------------------------------------------------------------------
run "confidential_topic_requires_pii_fields" {
  command = plan

  variables {
    sla_tier            = "critical"
    data_classification = "confidential"
    pii_fields          = []
    kek_name            = "test-kek"
    csfle_kms_type      = "aws-kms"
    csfle_kms_key_id    = "arn:aws:kms:us-east-1:123:key/test"
  }

  expect_failures = [confluent_schema.value]
}

# ---------------------------------------------------------------------------
# Confidential topic: valid config succeeds (CSFLE resources present)
# ---------------------------------------------------------------------------
run "confidential_topic_with_valid_config" {
  command = plan

  variables {
    sla_tier            = "critical"
    data_classification = "confidential"
    pii_fields          = ["ssn"]
    kek_name            = "test-kek"
    csfle_kms_type      = "aws-kms"
    csfle_kms_key_id    = "arn:aws:kms:us-east-1:123:key/test"
  }

  assert {
    condition     = output.topic_name == "testdomain.testapp.v1.test-entity"
    error_message = "Confidential topic name must resolve correctly."
  }
}

# ---------------------------------------------------------------------------
# Non-confidential topic: no CSFLE resources created
# ---------------------------------------------------------------------------
run "non_confidential_topic_no_csfle" {
  command = plan

  variables {
    sla_tier            = "standard"
    data_classification = "internal"
    pii_fields          = []
  }

  assert {
    condition     = output.topic_name == "testdomain.testapp.v1.test-entity"
    error_message = "Non-confidential topic must plan successfully without CSFLE."
  }
}

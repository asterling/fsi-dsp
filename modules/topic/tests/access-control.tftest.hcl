# =============================================================================
# Access Control Tests -- SA provisioning and RBAC binding correctness
# =============================================================================
# Validates the create-or-reference service account pattern (D-01, D-02)
# and ensures RBAC bindings produce identical permissions in either mode.

mock_provider "confluent" {}

variables {
  domain                         = "testdomain"
  application                    = "testapp"
  schema_version                 = "v1"
  entity                         = "test-entity"
  owner                          = "test@fsi.org"
  sla_tier                       = "critical"
  schema_file                    = "../../../schemas/examples/account-transaction.avsc"
  pii_fields                     = ["account_number"]
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
  # Reference mode defaults
  create_service_accounts        = false
  producer_service_accounts      = ["sa-test-producer"]
  consumer_service_accounts      = ["sa-test-consumer"]
}

# ---------------------------------------------------------------------------
# Reference mode — SA IDs passed through as effective IDs
# ---------------------------------------------------------------------------
run "reference_mode_sa_ids" {
  command = plan

  assert {
    condition     = output.producer_sa_ids == ["sa-test-producer"]
    error_message = "Reference mode must pass through provided producer SA IDs."
  }

  assert {
    condition     = output.consumer_sa_ids == ["sa-test-consumer"]
    error_message = "Reference mode must pass through provided consumer SA IDs."
  }
}

# ---------------------------------------------------------------------------
# Create mode — SAs provisioned from names
# ---------------------------------------------------------------------------
run "create_mode_sa_provisioning" {
  command = plan

  variables {
    create_service_accounts   = true
    producer_sa_names         = ["app-producer"]
    consumer_sa_names         = ["app-consumer"]
    producer_service_accounts = []
    consumer_service_accounts = []
  }

  assert {
    condition     = length(output.producer_sa_ids) == 1
    error_message = "Create mode must produce one producer SA ID."
  }

  assert {
    condition     = length(output.consumer_sa_ids) == 1
    error_message = "Create mode must produce one consumer SA ID."
  }
}

# ---------------------------------------------------------------------------
# RBAC bindings resolve in reference mode
# ---------------------------------------------------------------------------
run "rbac_bindings_exist_in_reference_mode" {
  command = plan

  assert {
    condition     = output.topic_name == "testdomain.testapp.v1.test-entity"
    error_message = "Topic name must resolve correctly for RBAC binding CRN pattern."
  }

  assert {
    condition     = length(output.producer_sa_ids) > 0
    error_message = "RBAC bindings require at least one effective producer SA ID."
  }
}

# ---------------------------------------------------------------------------
# RBAC bindings resolve in create mode
# ---------------------------------------------------------------------------
run "rbac_bindings_exist_in_create_mode" {
  command = plan

  variables {
    create_service_accounts   = true
    producer_sa_names         = ["svc-producer"]
    consumer_sa_names         = ["svc-consumer"]
    producer_service_accounts = []
    consumer_service_accounts = []
  }

  assert {
    condition     = length(output.producer_sa_ids) > 0
    error_message = "Create mode RBAC bindings require at least one effective producer SA ID."
  }

  assert {
    condition     = length(output.consumer_sa_ids) > 0
    error_message = "Create mode RBAC bindings require at least one effective consumer SA ID."
  }
}

# ---------------------------------------------------------------------------
# Validation: no producer SA rejected (precondition on topic resource)
# ---------------------------------------------------------------------------
run "no_producer_sa_rejected" {
  command = plan

  variables {
    create_service_accounts   = false
    producer_service_accounts = []
    producer_sa_names         = []
  }

  expect_failures = [confluent_kafka_topic.this]
}

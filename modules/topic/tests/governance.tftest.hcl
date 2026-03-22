# =============================================================================
# Governance Tests — Validates SLA tier defaults and naming conventions
# =============================================================================
# Uses mock provider to run without live Confluent Cloud credentials.

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
# Critical tier — baseline governance defaults
# ---------------------------------------------------------------------------
run "critical_tier_governance" {
  command = plan

  assert {
    condition     = output.compatibility_mode == "FULL_TRANSITIVE"
    error_message = "Critical tier must use FULL_TRANSITIVE compatibility."
  }

  assert {
    condition     = output.partitions == 12
    error_message = "Critical tier must have 12 partitions."
  }
}

# ---------------------------------------------------------------------------
# Compliance tier — same as critical but with infinite retention
# ---------------------------------------------------------------------------
run "compliance_tier_governance" {
  command = plan

  variables {
    sla_tier = "compliance"
  }

  assert {
    condition     = output.compatibility_mode == "FULL_TRANSITIVE"
    error_message = "Compliance tier must use FULL_TRANSITIVE compatibility."
  }

  assert {
    condition     = output.partitions == 12
    error_message = "Compliance tier must have 12 partitions."
  }

  assert {
    condition     = output.retention_ms == -1
    error_message = "Compliance tier must use infinite retention (-1)."
  }
}

# ---------------------------------------------------------------------------
# Standard tier — mid-range defaults
# ---------------------------------------------------------------------------
run "standard_tier_governance" {
  command = plan

  variables {
    sla_tier = "standard"
  }

  assert {
    condition     = output.compatibility_mode == "BACKWARD_TRANSITIVE"
    error_message = "Standard tier must use BACKWARD_TRANSITIVE compatibility."
  }

  assert {
    condition     = output.partitions == 6
    error_message = "Standard tier must have 6 partitions."
  }
}

# ---------------------------------------------------------------------------
# Best-effort tier — minimal defaults
# ---------------------------------------------------------------------------
run "best_effort_tier_governance" {
  command = plan

  variables {
    sla_tier = "best-effort"
  }

  assert {
    condition     = output.compatibility_mode == "BACKWARD"
    error_message = "Best-effort tier must use BACKWARD compatibility."
  }

  assert {
    condition     = output.partitions == 3
    error_message = "Best-effort tier must have 3 partitions."
  }
}

# ---------------------------------------------------------------------------
# Topic naming convention
# ---------------------------------------------------------------------------
run "topic_naming_convention" {
  command = plan

  assert {
    condition     = output.topic_name == "testdomain.testapp.v1.test-entity"
    error_message = "Topic name must follow domain.application.version.entity pattern."
  }
}

# ---------------------------------------------------------------------------
# Validation: reject invalid domain
# ---------------------------------------------------------------------------
run "invalid_domain_rejected" {
  command = plan

  variables {
    domain = "UPPERCASE"
  }

  expect_failures = [var.domain]
}

# ---------------------------------------------------------------------------
# Validation: reject invalid SLA tier
# ---------------------------------------------------------------------------
run "invalid_sla_tier_rejected" {
  command = plan

  variables {
    sla_tier = "invalid"
  }

  expect_failures = [var.sla_tier]
}

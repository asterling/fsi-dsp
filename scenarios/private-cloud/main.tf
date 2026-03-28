terraform {
  required_version = ">= 1.5"
  required_providers {
    confluent = {
      source  = "confluentinc/confluent"
      version = "~> 2.0"
    }
  }
}

# Confluent provider configured for self-managed CP cluster via REST endpoints.
# Unlike CC scenarios, Private Cloud uses kafka_rest_endpoint to reach the
# on-prem/VPC cluster directly -- no cloud_api_key needed.
provider "confluent" {
  kafka_rest_endpoint = var.cp_kafka_rest_endpoint
  kafka_api_key       = var.cp_kafka_api_key
  kafka_api_secret    = var.cp_kafka_api_secret

  schema_registry_rest_endpoint = var.cp_sr_rest_endpoint
  schema_registry_api_key       = var.cp_sr_api_key
  schema_registry_api_secret    = var.cp_sr_api_secret
}

locals {
  # Infrastructure references for the shared topic module
  infra = {
    kafka_cluster_id               = var.cp_kafka_cluster_id
    kafka_rest_endpoint            = var.cp_kafka_rest_endpoint
    sr_rest_endpoint               = var.cp_sr_rest_endpoint
    # Private Cloud does not use CRNs -- set empty for module compatibility
    kafka_cluster_crn              = ""
    sr_cluster_id                  = ""
    sr_cluster_crn                 = ""
    # DR configuration (optional -- set if Cluster Linking or MM2 is configured)
    cluster_link_name              = ""
    dr_kafka_cluster_id            = ""
    dr_kafka_rest_endpoint         = ""
  }
}

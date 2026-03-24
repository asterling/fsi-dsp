# =============================================================================
# OAuth/OAUTHBEARER -- GCP Cloud Identity Identity Provider
# =============================================================================
# Implements ADR-006: OAuth as primary auth for CC on GCP.
# Teams configure their Google Workspace / Cloud Identity, then
# producers/consumers authenticate via OAUTHBEARER tokens.
#
# Prerequisites:
#   1. Google Workspace or Cloud Identity configured for the GCP organization
#   2. OIDC application registered for Confluent Cloud
#   3. Google Groups for Kafka producers and consumers
#   4. var.gcp_organization_id set in terraform.tfvars
# =============================================================================

resource "confluent_identity_provider" "gcp_identity" {
  display_name = "GCP Cloud Identity"
  description  = "FSI GCP Cloud Identity provider for OAUTHBEARER authentication"
  issuer       = "https://accounts.google.com"
  jwks_uri     = "https://www.googleapis.com/oauth2/v3/certs"
}

resource "confluent_identity_pool" "producers" {
  identity_provider {
    id = confluent_identity_provider.gcp_identity.id
  }
  display_name   = "Kafka Producers"
  description    = "Identity pool for GCP Cloud Identity authenticated Kafka producers"
  identity_claim = "sub"
  filter         = "claims.aud==\"${var.confluent_cloud_app_id}\" && claims.groups.exists(g, g==\"${var.gcp_producer_group_email}\")"
}

resource "confluent_identity_pool" "consumers" {
  identity_provider {
    id = confluent_identity_provider.gcp_identity.id
  }
  display_name   = "Kafka Consumers"
  description    = "Identity pool for GCP Cloud Identity authenticated Kafka consumers"
  identity_claim = "sub"
  filter         = "claims.aud==\"${var.confluent_cloud_app_id}\" && claims.groups.exists(g, g==\"${var.gcp_consumer_group_email}\")"
}

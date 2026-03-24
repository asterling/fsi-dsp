# =============================================================================
# OAuth/OAUTHBEARER -- Azure AD (Entra ID) Identity Provider
# =============================================================================
# Implements ADR-006: OAuth as primary auth for CC on Azure.
# Teams configure their Azure AD tenant and app registration, then
# producers/consumers authenticate via OAUTHBEARER tokens.
#
# Prerequisites:
#   1. Azure AD app registration with API permissions for Confluent Cloud
#   2. Azure AD group(s) for Kafka producers and consumers
#   3. var.azure_tenant_id set in terraform.tfvars
# =============================================================================

resource "confluent_identity_provider" "azure_ad" {
  display_name = "Azure AD (Entra ID)"
  description  = "FSI Azure AD identity provider for OAUTHBEARER authentication"
  issuer       = "https://login.microsoftonline.com/${var.azure_tenant_id}/v2.0"
  jwks_uri     = "https://login.microsoftonline.com/${var.azure_tenant_id}/discovery/v2.0/keys"
}

resource "confluent_identity_pool" "producers" {
  identity_provider {
    id = confluent_identity_provider.azure_ad.id
  }
  display_name   = "Kafka Producers"
  description    = "Identity pool for Azure AD authenticated Kafka producers"
  identity_claim = "sub"
  filter         = "claims.aud==\"${var.confluent_cloud_app_id}\" && claims.groups.exists(g, g==\"${var.azure_producer_group_id}\")"
}

resource "confluent_identity_pool" "consumers" {
  identity_provider {
    id = confluent_identity_provider.azure_ad.id
  }
  display_name   = "Kafka Consumers"
  description    = "Identity pool for Azure AD authenticated Kafka consumers"
  identity_claim = "sub"
  filter         = "claims.aud==\"${var.confluent_cloud_app_id}\" && claims.groups.exists(g, g==\"${var.azure_consumer_group_id}\")"
}

# =============================================================================
# OAuth/OAUTHBEARER -- AWS IAM Identity Center Identity Provider
# =============================================================================
# Implements ADR-006: OAuth as primary auth for CC on AWS.
# Teams configure their AWS IAM Identity Center (SSO) instance, then
# producers/consumers authenticate via OAUTHBEARER tokens.
#
# Prerequisites:
#   1. AWS IAM Identity Center (SSO) enabled in the AWS organization
#   2. OIDC application registered for Confluent Cloud
#   3. AWS SSO groups for Kafka producers and consumers
#   4. var.aws_sso_instance_id set in terraform.tfvars
# =============================================================================

resource "confluent_identity_provider" "aws_iam" {
  display_name = "AWS IAM Identity Center"
  description  = "FSI AWS IAM identity provider for OAUTHBEARER authentication"
  issuer       = "https://${var.aws_sso_instance_id}.awsapps.com/start"
  jwks_uri     = "https://${var.aws_sso_instance_id}.awsapps.com/start/keys"
}

resource "confluent_identity_pool" "producers" {
  identity_provider {
    id = confluent_identity_provider.aws_iam.id
  }
  display_name   = "Kafka Producers"
  description    = "Identity pool for AWS IAM authenticated Kafka producers"
  identity_claim = "sub"
  filter         = "claims.aud==\"${var.confluent_cloud_app_id}\" && claims.groups.exists(g, g==\"${var.aws_producer_group_name}\")"
}

resource "confluent_identity_pool" "consumers" {
  identity_provider {
    id = confluent_identity_provider.aws_iam.id
  }
  display_name   = "Kafka Consumers"
  description    = "Identity pool for AWS IAM authenticated Kafka consumers"
  identity_claim = "sub"
  filter         = "claims.aud==\"${var.confluent_cloud_app_id}\" && claims.groups.exists(g, g==\"${var.aws_consumer_group_name}\")"
}

# ADR-006: OAuth vs API Keys for Kafka Authentication

**Status:** Accepted
**Date:** 2026-03-21
**Author:** FSI C4E

## Context

The FSI Kafka Platform supports multiple deployment models (Confluent Cloud, CFK on OpenShift, CP on RHEL). Each requires authentication for producers, consumers, and administrative operations. Two primary authentication mechanisms are available:

1. **API Keys** (static credentials): Confluent Cloud service account API key/secret pairs. Simple to provision via Terraform. Require manual rotation. If leaked, remain valid until explicitly revoked.

2. **OAuth/OAUTHBEARER** (token-based): Short-lived tokens issued by an identity provider (IdP). Confluent Cloud supports OAUTHBEARER since 2023. Tokens auto-expire (typically 1 hour). Rotation is automatic via IdP token refresh. Requires IdP integration (Azure AD, AWS IAM, Okta).

Forces:
- FSI regulatory requirements mandate credential rotation policies (90-day maximum for static credentials)
- Zero-downtime credential rotation is operationally critical for 24/7 financial systems
- Different deployment models have different IdP ecosystems (Azure AD for Azure, AWS IAM for AWS, LDAP/AD for on-prem)
- API keys are simpler to set up initially but create operational burden for rotation
- OAuth requires IdP infrastructure but provides automatic rotation

## Decision

**Recommend OAuth/OAUTHBEARER as the primary authentication mechanism for Confluent Cloud deployments.** Retain API keys as the fallback for environments without IdP integration and for Terraform provider authentication (which does not support OAuth).

### Per Deployment Model

| Deployment Model | Primary Auth | Fallback | IdP |
|------------------|-------------|----------|-----|
| CC on Azure | OAUTHBEARER | API Keys | Azure AD (Entra ID) |
| CC on AWS | OAUTHBEARER | API Keys | AWS IAM Identity Center |
| CC on GCP | OAUTHBEARER | API Keys | Google Workspace / Cloud Identity |
| CFK on OpenShift | LDAP/AD via MDS | RBAC tokens | Active Directory |
| CP on RHEL | MDS with LDAP | SASL/PLAIN | Active Directory / LDAP |

### Credential Rotation Guidance

- **OAuth tokens:** Automatic. Configure token lifetime in IdP (recommended: 1 hour). Client libraries handle refresh.
- **API keys (when used):** Rotate via Vault integration. Create new key, update consumers (dual-credential window), revoke old key. Target: < 90 days per FSI policy.
- **Terraform provider credentials:** API keys only (Confluent Terraform provider does not support OAuth). Store in CI secrets (GitHub Actions) or Vault. Rotate quarterly.

## Consequences

**Easier:**
- Credential rotation is automatic for application workloads using OAuth
- Audit trail of authentication events via IdP logs
- Centralized identity management across Kafka and other services
- Revocation is instant (revoke IdP access, all tokens expire naturally)

**Harder:**
- Initial IdP setup requires identity team coordination
- Each cloud provider has different OAUTHBEARER configuration
- Terraform provider authentication remains API-key-based (separate rotation process)
- Local development may use API keys for simplicity (Docker Compose environments)
- Teams unfamiliar with OAuth need onboarding documentation

# Credential Rotation Runbook

## Overview

Financial services regulations require credential rotation policies with a maximum 90-day lifetime for static credentials. The FSI Kafka Platform supports two authentication mechanisms (see [ADR-006](adr/006-oauth-vs-api-keys.md)):

1. **OAuth/OAUTHBEARER** (recommended for CC) -- tokens auto-rotate via the identity provider. No manual rotation needed.
2. **API Keys** (fallback and Terraform provider) -- static credentials that require manual rotation with zero-downtime support.

This runbook covers the rotation procedure for API keys using a **dual-credential window** pattern that ensures zero downtime during credential transitions.

## Vault Golden Path (Recommended)

HashiCorp Vault KV v2 is the golden path for credential management across all CC scenarios (per D-04, D-07). Each scenario directory includes a `vault.tf.example` reference pattern.

### Path Convention

All Vault secrets follow a prescriptive path convention (per D-06):

```
secret/fsi-kafka/{env}/{domain}/{sa-name}
```

| Segment | Example | Description |
|---------|---------|-------------|
| `{env}` | `prod`, `staging`, `dev` | Environment name |
| `{domain}` | `corebanking`, `fraud`, `compliance` | Business domain |
| `{sa-name}` | `account-txn-producer`, `fraud-alert-consumer` | Service account display name |

Example paths:
- `secret/fsi-kafka/prod/corebanking/account-txn-producer`
- `secret/fsi-kafka/staging/fraud/alert-signal-consumer`
- `secret/fsi-kafka/prod/compliance/screening-result-producer-sr` (Schema Registry credentials)

### Reference Terraform Pattern

The Vault reference pattern uses KV v2 with `max_versions = 2` to support the dual-credential window:

```hcl
resource "vault_kv_secret_v2" "kafka_credentials" {
  mount = "secret"
  name  = "fsi-kafka/${var.environment}/${var.domain}/${var.sa_name}"

  data_json = jsonencode({
    api_key        = var.kafka_api_key
    api_secret     = var.kafka_api_secret
    bootstrap_url  = var.bootstrap_url
    cluster_id     = var.kafka_cluster_id
  })

  custom_metadata {
    max_versions = 2  # Keep current + previous for dual-credential window
  }
}
```

See `scenarios/cc-azure/vault.tf.example`, `scenarios/cc-aws/vault.tf.example`, or `scenarios/cc-gcp/vault.tf.example` for the complete reference pattern.

### Dual-Credential Rotation Procedure

The dual-credential window ensures zero downtime during rotation. Confluent Cloud supports multiple active API keys per service account, enabling an overlap period where both old and new credentials are valid.

**Default window: 24h** (configurable per team policy).

#### Step 1: Create New API Key

```bash
# Create a new API key for the service account
confluent api-key create \
  --resource lkc-xxxxx \
  --service-account sa-xxxxxx \
  --description "Rotated $(date +%Y-%m-%d)"
```

Record the new API key and secret from the output. Both the old and new keys are now active.

#### Step 2: Write New Credential to Vault

```bash
# Write new credential to Vault (creates a new version)
vault kv put secret/fsi-kafka/prod/corebanking/account-txn-producer \
  api_key="NEW_API_KEY" \
  api_secret="NEW_API_SECRET" \
  bootstrap_url="pkc-xxxxx.us-east-1.aws.confluent.cloud:9092" \
  cluster_id="lkc-xxxxx"
```

Vault KV v2 automatically versions the secret. With `max_versions = 2`, both current (new) and previous (old) versions are retained.

#### Step 3: Dual-Credential Window Begins

At this point, both the old and new API keys are active in Confluent Cloud, and Vault holds both versions. No action needed -- the window has started automatically.

#### Step 4: Deploy Applications with New Credential

Roll out the new credential to all applications consuming from Vault:

```bash
# Option A: Rolling restart (Kubernetes)
kubectl rollout restart deployment/my-kafka-producer -n kafka-apps

# Option B: Config reload (if supported by application)
# Application reads new Vault secret on next health check cycle

# Option C: Vault Agent sidecar (automatic)
# Vault Agent automatically detects new secret version and renders updated template
```

#### Step 5: Monitor During Window (24h Default)

Wait for the configurable window period (default 24h per D-05) and monitor for authentication failures:

```bash
# Check Confluent Cloud audit logs for auth failures
confluent audit-log search \
  --start "$(date -u -v-24H +%Y-%m-%dT%H:%M:%SZ)" \
  --resource-type kafka \
  --category AUTHENTICATION \
  | grep -i "failure"
```

Vault TTL enforcement (optional):

```bash
# Set TTL on the previous version to auto-expire after window
vault kv metadata put \
  -custom-metadata="rotation_deadline=$(date -u -v+24H +%Y-%m-%dT%H:%M:%SZ)" \
  secret/fsi-kafka/prod/corebanking/account-txn-producer
```

#### Step 6: Revoke Old API Key

After the window expires with no auth failures, revoke the old API key:

```bash
# List API keys for the service account
confluent api-key list --service-account sa-xxxxxx --resource lkc-xxxxx

# Delete the old API key (identified by key ID from step 1)
confluent api-key delete OLD_API_KEY_ID
```

#### Step 7: Verify

Confirm no authentication failures after revocation:

```bash
# Wait 5 minutes, then check audit logs
sleep 300
confluent audit-log search \
  --start "$(date -u -v-10M +%Y-%m-%dT%H:%M:%SZ)" \
  --resource-type kafka \
  --category AUTHENTICATION \
  | grep -i "failure"

# Expected: no failure events
```

### Vault TTL Configuration

Configure Vault TTL settings to enforce the rotation window automatically:

```bash
# Set default TTL for the secrets engine (90 days = rotation deadline)
vault secrets tune -default-lease-ttl=2160h secret/

# Set max TTL slightly beyond rotation deadline for grace period
vault secrets tune -max-lease-ttl=2400h secret/
```

For automated rotation with Vault, consider [HCP Vault Secrets auto-rotation for Confluent](https://developer.hashicorp.com/hcp/docs/vault-secrets/auto-rotation/create-rotating-secret/confluent) which automates the full create-deploy-revoke cycle.

## Cloud-Native Alternatives

For organizations not running HashiCorp Vault, each cloud provider offers a managed secret manager with rotation support (per D-07). These are documented alternatives -- no Terraform patterns are provided for cloud-native secret managers.

### Azure Key Vault

Store Confluent Cloud API keys as Azure Key Vault secrets. Use Managed Identity for access control.

**Rotation approach:**
1. Store API key/secret as a Key Vault secret (JSON payload)
2. Create an Azure Automation runbook that:
   - Creates a new Confluent API key via Confluent CLI or API
   - Updates the Key Vault secret with the new key
   - Waits for the dual-credential window (24h)
   - Revokes the old API key
3. Schedule the runbook to run every 90 days via Azure Automation

**Reference:** [Azure Key Vault rotation tutorial](https://learn.microsoft.com/en-us/azure/key-vault/secrets/tutorial-rotation)

### AWS Secrets Manager

Store Confluent Cloud API keys as AWS Secrets Manager secrets. Use IAM roles for access control.

**Rotation approach:**
1. Store API key/secret as a Secrets Manager secret (JSON payload)
2. Create a Lambda rotation function that:
   - Creates a new Confluent API key via Confluent API
   - Sets the new key as `AWSPENDING` version stage
   - Tests the new key against the Confluent Cloud cluster
   - Promotes the new key to `AWSCURRENT` and revokes the old key
3. Enable automatic rotation with a 90-day schedule

**Reference:** [AWS Secrets Manager rotation](https://docs.aws.amazon.com/secretsmanager/latest/userguide/rotating-secrets.html)

### GCP Secret Manager

Store Confluent Cloud API keys as GCP Secret Manager secrets. Use service account IAM bindings for access control.

**Rotation approach:**
1. Store API key/secret as a Secret Manager secret version (JSON payload)
2. Create a Cloud Function that:
   - Creates a new Confluent API key via Confluent API
   - Adds the new key as a new secret version
   - Waits for the dual-credential window (24h)
   - Disables the previous secret version and revokes the old API key
3. Trigger the function on a 90-day schedule via Cloud Scheduler

**Reference:** [GCP Secret Manager best practices](https://cloud.google.com/secret-manager/docs/best-practices)

## OAuth Token Rotation

For applications using OAuth/OAUTHBEARER (recommended for CC deployments per [ADR-006](adr/006-oauth-vs-api-keys.md)), token rotation is automatic:

- **Token lifetime:** 1 hour (recommended), configured in the identity provider
- **Refresh:** Kafka client libraries automatically refresh tokens before expiration
- **No manual rotation needed:** The IdP issues new tokens and handles key rotation via JWKS endpoint
- **Revocation:** Disable the user/group in the IdP; all tokens expire naturally within the configured lifetime

OAuth eliminates the operational burden of credential rotation for application workloads. See `scenarios/cc-azure/oauth.tf`, `scenarios/cc-aws/oauth.tf`, and `scenarios/cc-gcp/oauth.tf` for per-scenario IdP configuration.

## Terraform Provider Credentials

The Confluent Terraform Provider does not support OAuth -- it requires API keys for authentication (per [ADR-006](adr/006-oauth-vs-api-keys.md)).

**Rotation guidance:**
- Store provider API keys in CI secrets (GitHub Actions encrypted secrets)
- Rotate quarterly (every 90 days) as part of the credential rotation schedule
- Use a dedicated Cloud API key (not a cluster-scoped key) for the Terraform provider
- After rotation, update the CI secret and verify the next pipeline run succeeds

```bash
# Create new Cloud API key for Terraform provider
confluent api-key create --resource cloud

# Update GitHub Actions secret
gh secret set CONFLUENT_CLOUD_API_KEY --body "NEW_KEY"
gh secret set CONFLUENT_CLOUD_API_SECRET --body "NEW_SECRET"

# Verify: trigger a plan run
gh workflow run terraform-scenario.yml -f scenario-dir=scenarios/cc-azure -f mode=plan
```

## Emergency Rotation

If a credential is compromised, skip the dual-credential window and revoke immediately:

1. **Revoke immediately** -- accept brief downtime:
   ```bash
   confluent api-key delete COMPROMISED_KEY_ID --force
   ```

2. **Create new key:**
   ```bash
   confluent api-key create \
     --resource lkc-xxxxx \
     --service-account sa-xxxxxx \
     --description "Emergency rotation $(date +%Y-%m-%dT%H:%M:%SZ)"
   ```

3. **Deploy new key** to all consumers (fastest path -- direct config update or Vault write):
   ```bash
   vault kv put secret/fsi-kafka/prod/corebanking/account-txn-producer \
     api_key="NEW_KEY" \
     api_secret="NEW_SECRET" \
     bootstrap_url="..." \
     cluster_id="..."
   ```

4. **Force restart** all affected applications:
   ```bash
   kubectl rollout restart deployment -l app.kafka.credential=compromised -n kafka-apps
   ```

5. **Verify** no further unauthorized access in audit logs:
   ```bash
   confluent audit-log search \
     --start "$(date -u -v-1H +%Y-%m-%dT%H:%M:%SZ)" \
     --resource-type kafka \
     --principal "User:COMPROMISED_SA_ID"
   ```

6. **Incident report:** Document the compromise, rotation timeline, and blast radius assessment per your organization's incident response procedure.

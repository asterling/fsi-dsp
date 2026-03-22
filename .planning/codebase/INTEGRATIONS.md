# External Integrations

**Analysis Date:** 2026-03-21

## APIs & External Services

**Confluent Cloud:**
- Confluent Cloud REST API - Topic, schema, RBAC, and cluster management
  - SDK/Client: `confluentinc/confluent` Terraform provider
  - Auth: API key/secret pair (`CC_*_CLUSTER_ID`, `CC_*_API_KEY`, `CC_*_API_SECRET`)
  - Endpoints: `CC_KAFKA_REST_ENDPOINT`, `CC_SR_REST_ENDPOINT`, `CC_DR_KAFKA_REST_ENDPOINT`

**Schema Registry:**
- Confluent Schema Registry REST API - Schema registration, versioning, compatibility
  - Endpoint: `CC_SR_REST_ENDPOINT` (e.g., `https://psrc-xxxxx.eastus2.azure.confluent.cloud`)
  - Auth: Basic auth with API key/secret (`CC_SR_API_KEY`, `CC_SR_API_SECRET`)
  - Format: Avro with TopicNameStrategy
  - Consumed by: Java/C# producers and consumers, Kafka Connect connectors

**Kafka Connect REST API:**
- Connector management and deployment
  - Endpoint: `CONNECT_REST_URL` (e.g., `http://connect.internal:8083`)
  - Used for: JDBC source/sink connector configuration and monitoring
  - Example configs in `reference/connect-configs/`

## Data Storage

**Databases:**
- **Primary:** Oracle Database 11g+ (with DataGuard DR)
  - Connection: JDBC via `jdbc:oracle:thin:@{DB_HOST_PRIMARY}:{DB_PORT}/{DB_NAME}`
  - Credentials: Injected from Vault (`${vault:secret/fsi/oracle#username}`, `${vault:secret/fsi/oracle#password}`)
  - Used by: JDBC sink connector to write Kafka events to Oracle tables
  - Example: `reference/connect-configs/jdbc-sink-example.json` writes `corebanking.core.v1.account-balance` to `KAFKA_ACCOUNT_BALANCE` table

- **Alternative Supported:** SQL Server, PostgreSQL
  - Connection string format varies by DB type (`DB_TYPE`: oracle | sqlserver | postgresql)
  - DR technology: `DB_DR_TECHNOLOGY` (dataguard | always-on | streaming-replication)
  - Endpoint resolution: Via Consul DNS (`SD_DATABASE_ENDPOINT`)

**Kafka Cluster Storage:**
- Confluent Cloud Kafka cluster (production) - `CC_KAFKA_CLUSTER_ID`, `CC_KAFKA_BOOTSTRAP`
- Confluent Cloud Kafka cluster (DR) - `CC_DR_KAFKA_CLUSTER_ID`, `CC_DR_KAFKA_BOOTSTRAP`
- Cluster linking for bidirectional replication: `CC_CLUSTER_LINK_NAME`
- Connection: SASL/PLAIN over TLS (Confluent Cloud standard)

**Terraform State Storage:**
- Azure Blob Storage (default) - Storage account and container specified in `.env`
- AWS S3 (alternative) - Bucket and key prefix
- Google Cloud Storage (alternative) - Bucket and prefix

## Authentication & Identity

**Kafka/Schema Registry Auth:**
- Type: SASL/PLAIN over TLS (Confluent Cloud standard)
- Method: API key/secret pairs stored in `.env` (not committed)
  - `CC_KAFKA_API_KEY` / `CC_KAFKA_API_SECRET` - Production Kafka cluster
  - `CC_DR_KAFKA_API_KEY` / `CC_DR_KAFKA_API_SECRET` - DR Kafka cluster
  - `CC_SR_API_KEY` / `CC_SR_API_SECRET` - Schema Registry
- Cloud provider OAuth (optional, ADR in `docs/cloud-providers.md`):
  - Azure AD / Entra ID (OAUTHBEARER with `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`)
  - AWS IAM (with identity federation)
  - GCP Workload Identity Federation

**Confluent Cloud API Auth:**
- Type: API key/secret pair
- Variables: `CC_ORG_ID`, `CC_ENV_ID`, `CC_KAFKA_CLUSTER_ID`, `CC_SR_CLUSTER_ID`
- Used by: Terraform provider for all infrastructure provisioning
- Stored securely: GitHub Actions secrets (`CONFLUENT_CLOUD_API_KEY`, `CONFLUENT_CLOUD_API_SECRET`)

**Database Credentials:**
- Type: Username/password
- Storage: HashiCorp Vault (primary), Azure Key Vault, AWS Secrets Manager
- Injection method: Vault template syntax in Connect configs
  - Example: `connection.user: "${vault:secret/fsi/oracle#username}"`
- Retrieved by: Kafka Connect using Vault provider plugin

**Service Discovery Auth:**
- Consul service discovery - Accessed via `CONSUL_HTTP_ADDR` (e.g., `http://consul.internal:8500`)
- KV store updates: Administrative Consul tokens (not exposed in `.env`)
- Health checks: Consul built-in for Oracle failover detection

## Monitoring & Observability

**Error Tracking:**
- Dynatrace - Primary observability platform
  - Environment URL: `DYNATRACE_ENVIRONMENT_URL`
  - JMX metric exposure: Java producers/consumers expose metrics to Dynatrace
  - Alternative providers: Datadog, Splunk, Prometheus (selected via `OBSERVABILITY_PROVIDER`)

**Logs:**
- SLF4J logging (Java reference implementations)
- Connect worker logs sent to Kafka topics (`connect-offsets`, `connect-configs`, `connect-status`)
- Dead-letter queue (DLQ) topic: `corebanking.core.v1.dlq-account-balance` (example)
- Consumer lag monitoring: Confluent Cloud Metrics API
- Alert thresholds: `ALERT_CL_LAG_SECONDS`, `ALERT_CONSUMER_LAG_RECORDS`

**Metrics:**
- Kafka metrics: Exported via JMX port 9101 (local dev)
- Consumer lag: Monitored via Confluent Cloud API
- Connector metrics: Available at `http://connect.internal:8083/connectors`

## CI/CD & Deployment

**Hosting:**
- Confluent Cloud (fully managed SaaS)
  - Multi-cloud support: Azure, AWS, GCP
  - Regions: `CC_PROD_REGION` (e.g., eastus2), `CC_DR_REGION` (e.g., westus2)
  - High availability: Confluent Cloud manages multi-broker clusters internally

**CI Pipeline:**
- GitHub Actions - `.github/workflows/terraform-plan.yml`
  - Triggers on PR with changes to `environments/`, `modules/`, `schemas/`
  - Validation: Terraform fmt, topic naming convention checks, Avro schema JSON validation
  - Plan output posted as PR comment for review

**CD Pipeline:**
- GitHub Actions - `.github/workflows/terraform-apply.yml`
  - Triggers on push to `main` branch
  - Requires environment protection rules (`fsi-prod-east-apply`)
  - Secrets sourced from GitHub Actions repository/organization secrets
  - Auto-approve terraform apply (for unattended deployment)

**Infrastructure Provisioning:**
- Terraform Cloud or self-managed state
- Terraform version: 1.7.0 (enforced)
- Provider: `confluentinc/confluent` v2.0+
- Backend: `azurerm`, `s3`, or `gcs` (configurable via `TERRAFORM_BACKEND`)

## Environment Configuration

**Required env vars (from `.env`):**
- Confluent Cloud: `CC_ORG_ID`, `CC_ENV_ID`, `CC_KAFKA_CLUSTER_ID`, `CC_KAFKA_BOOTSTRAP`, `CC_KAFKA_API_KEY`, `CC_KAFKA_API_SECRET`
- Schema Registry: `CC_SR_CLUSTER_ID`, `CC_SR_REST_ENDPOINT`, `CC_SR_API_KEY`, `CC_SR_API_SECRET`
- DR cluster: `CC_DR_KAFKA_CLUSTER_ID`, `CC_DR_KAFKA_BOOTSTRAP`, `CC_DR_KAFKA_API_KEY`, `CC_DR_KAFKA_API_SECRET`
- Cloud provider: `CLOUD_PROVIDER` (azure | aws | gcp), region config
- Database: `DB_TYPE`, `DB_HOST_PRIMARY`, `DB_PORT`, `DB_NAME`, `DB_DR_TECHNOLOGY`
- Service discovery: `SD_PROVIDER` (consul | dns | none), `CONSUL_HTTP_ADDR`
- Secrets: `SECRETS_PROVIDER` (vault | azure-keyvault | aws-secrets-manager)
- Observability: `OBSERVABILITY_PROVIDER`, provider-specific URLs
- Terraform backend: `TERRAFORM_BACKEND`, backend-specific credentials

**Secrets location:**
- Primary: `.env` file (never committed, listed in `.gitignore`)
- CI/CD: GitHub Actions repository/organization secrets
- Runtime: HashiCorp Vault (`VAULT_ADDR`)
  - Secret paths: `secret/fsi/oracle`, `secret/fsi/sr`, etc.

**Cloud Provider Credentials:**
- Azure: `AZURE_SUBSCRIPTION_ID`, `AZURE_RESOURCE_GROUP`, `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET` (for AD auth)
- AWS: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` (for Terraform backend and IAM)
- GCP: Service account JSON (for Workload Identity or direct auth)

## Webhooks & Callbacks

**Incoming:**
- GitHub webhooks - PR events, push to main (trigger CI/CD workflows)
- Consul health check callbacks - Oracle database failover detection
- Schema Registry compatibility callbacks - Embedded in Terraform module, not explicit webhooks

**Outgoing:**
- Kafka Connect connector webhooks - Supported by connectors, optional for external notifications
- Confluent Cloud API notifications - Topic/cluster lifecycle events (optional)
- Terraform apply notifications - Via GitHub Actions (success/failure logged to PR)

## Cluster Linking & Disaster Recovery

**Cluster Link Configuration:**
- Link name: `CC_CLUSTER_LINK_NAME` (e.g., `cluster-link-bidir-prod-dr`)
- Direction: Bidirectional (ADR-005 rationale in `docs/adr/005-cluster-linking-over-mrc.md`)
- Source cluster: Production (East) - `CC_KAFKA_CLUSTER_ID`
- Destination cluster: DR (West) - `CC_DR_KAFKA_CLUSTER_ID`
- Mirrored topics: Automatically created via `confluent_kafka_mirror_topic` Terraform resource

**Failover Orchestration:**
- Consul KV key: `fsi/kafka/active-region` - Single point of control for region switching
- Related scripts: `scripts/mirror-failover.sh`, `scripts/mirror-failback.sh`
- Connect configuration switching: `reference/connect-configs/connect-distributed-east.properties` ↔ `connect-distributed-west.properties`

---

*Integration audit: 2026-03-21*

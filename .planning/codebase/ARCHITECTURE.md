# Architecture

**Analysis Date:** 2026-03-21

## Pattern Overview

**Overall:** Infrastructure-as-Code platform for declarative Kafka topic governance on Confluent Cloud.

**Key Characteristics:**
- Single reusable Terraform module produces fully governed topics (topic + schema + RBAC + DR mirror + metadata tags)
- Schema-first design with Avro as the canonical format and compatibility modes derived from SLA tier
- SLA-tier-based configuration (critical, standard, best-effort) determines compatibility, partitions, and retention automatically
- Dual-cluster topology: East (active production) + West (passive DR) connected via Confluent Cluster Linking
- Consul-based service discovery for atomic DR failover across Kafka, Schema Registry, and databases

## Layers

**Infrastructure (IaC) Layer:**
- Purpose: Provision Confluent Cloud resources (Kafka clusters, Schema Registry, topics, RBAC, cluster links)
- Location: `modules/topic/` (reusable module) and `environments/prod/` (environment-specific declarations)
- Contains: Terraform resource definitions for `confluent_kafka_topic`, `confluent_schema`, `confluent_subject_config`, `confluent_role_binding`, `confluent_kafka_mirror_topic`
- Depends on: Confluent Cloud provider, AWS/Azure/GCP backend for Terraform state
- Used by: CI/CD pipeline (GitHub Actions) triggers on topic or schema changes

**Schema Management Layer:**
- Purpose: Define, version, and validate Avro schemas; enforce compatibility across schema evolution
- Location: `schemas/examples/` (reference schemas), validated by CI pipeline
- Contains: `.avsc` files following `{domain}-{entity}.avsc` naming convention, with field-level documentation and PII tagging
- Depends on: Confluent Schema Registry (managed service on CC)
- Used by: Producers, consumers, and Kafka Connect connectors for serialization/deserialization

**Operations & DR Layer:**
- Purpose: Handle disaster recovery failover/failback and operational scripts
- Location: `scripts/` (failover, failback, connect pause/resume operations)
- Contains: Bash scripts that invoke Confluent CLI and Consul API to orchestrate DR operations
- Depends on: Confluent Cloud Kafka CLI, Consul HTTP API, cluster link configuration
- Used by: On-call engineers during regional outages

**Governance & Documentation Layer:**
- Purpose: Establish standards, patterns, and runbooks for teams using the platform
- Location: `docs/` (schema guide, onboarding, ADRs), `.github/` (PR template, CI validation)
- Contains: Architecture Decision Records (ADRs), self-service intake forms, schema evolution guidelines, cloud provider differences
- Depends on: GitHub, C4E review process
- Used by: Teams requesting new topics, schema evolution approvals

**Reference/Testing Layer:**
- Purpose: Provide working examples for producer/consumer development and integration testing
- Location: `reference/` (Java/dotnet producers/consumers, Connect configs, Docker Compose, integration tests)
- Contains: Complete working applications, Connect JDBC configs (East/West), local development Docker Compose
- Depends on: Confluent Community Edition (local dev), Java/dotnet SDKs (Confluent clients)
- Used by: Development teams bootstrapping new applications

## Data Flow

**Topic Creation Workflow:**

1. Team creates topic intake form (GitHub issue from `.github/ISSUE_TEMPLATE/`)
2. Team writes Avro schema in `schemas/{domain}-{entity}.avsc` with field-level docs and PII tags
3. Team adds Terraform module call in `environments/prod/main.tf` or example-topics.tf with domain/application/version/entity/sla_tier/pii_fields
4. PR opened → CI lints, validates schema JSON, validates topic naming, runs terraform plan
5. C4E review and approval (same business day SLA)
6. PR merged to main → `terraform-apply.yml` workflow runs → applies Terraform → creates topic, registers schema with compatibility mode, applies RBAC to service accounts, creates DR mirror topic on West cluster
7. Output: Fully governed topic ready for producers/consumers

**Producer/Consumer Onboarding:**

1. Producer fetches API key/secret from Confluent Cloud for their service account
2. Producer connects to Kafka bootstrap endpoint (resolved via Consul or hardcoded, default: hardcoded in reference apps)
3. Producer uses Confluent schema registry client to auto-register schema on first produce (RBAC: DeveloperWrite on topic + schema subject)
4. Messages serialized with Avro, produced to topic
5. Consumer uses same schema subject to deserialize messages
6. Consumer group RBAC enforced at consumer-group level (DeveloperRead)

**DR Failover Sequence:**

1. East cluster becomes unavailable
2. Operator runs `scripts/mirror-failover.sh` → promotes all mirror topics on West to R/W
3. Operator runs `scripts/consul-flip-region.sh` → updates Consul KV `fsi/kafka/active-region` = "west"
4. Applications query Consul DNS for Kafka bootstrap → resolves to West endpoints
5. Applications automatically connect to West cluster (no config change needed)
6. Schema Registry continues to serve from unified registry (cross-cluster support via CC)
7. RBAC unchanged (service accounts have access to topics on both clusters via cluster link)

**State Management:**

- **Topic state:** Kafka broker (replicated across partitions), Schema Registry (immutable schema versions)
- **Configuration state:** Terraform state (stored in S3/Azure Blob/GCS, locked during apply)
- **DR state:** Cluster link bidirectional replication with mirror lag visible via Confluent CLI
- **Service discovery state:** Consul KV store (`fsi/kafka/active-region` key determines which region endpoints are active)

## Key Abstractions

**Topic Module (`modules/topic/main.tf`):**
- Purpose: Encapsulates the pattern for creating a fully governed topic in a single reusable call
- Examples: `module "corebanking_account_txn"`, `module "fraud_alert_signal"`, `module "compliance_screening_result"`
- Pattern:
  - Takes domain, application, version, entity as inputs → assembles topic name as `{domain}.{application}.{version}.{entity}`
  - Maps SLA tier to compatibility mode, partition count, and retention
  - Creates topic, registers schema, applies RBAC for producers/consumers, creates DR mirror
  - Outputs topic name, schema subject, compatibility mode, partition count for downstream use

**SLA Tier as Configuration Multiplier:**
- Purpose: Reduce boilerplate; configuration (compatibility, partitions, retention) derived from single input
- Pattern (in `modules/topic/main.tf` locals):
  ```hcl
  compatibility_map = {
    critical    = "FULL_TRANSITIVE"      # Safe for critical domains
    standard    = "BACKWARD_TRANSITIVE"  # Flexible but safe
    best-effort = "BACKWARD"             # Most flexible
  }
  partition_map = {
    critical    = 12
    standard    = 6
    best-effort = 3
  }
  retention_map = {
    critical    = 604800000  # 7 days
    standard    = 259200000  # 3 days
    best-effort = 86400000   # 1 day
  }
  ```
- Allows overrides (compatibility_override, partitions_override, retention_ms_override) for documented exceptions

**Schema Metadata as Governance Tags:**
- Purpose: Enable data governance, PII detection, ownership tracking without external tools
- Pattern: Metadata properties on schema subject include owner, sla-tier, data-classification, domain, application, pii flag, pii-fields list
- Used by: Data lineage tools (Alation), compliance scanning, cost allocation

**Cluster Linking as DR Pattern:**
- Purpose: Achieve RPO ~2 hours (target) with passive async replication; automatic promotion on failover
- Pattern: Bidirectional cluster link from East (primary) to West (DR), mirror topics created on West, manual promotion via Confluent CLI (6 scripted steps)
- Consequence: RPO > 0 (bounded by mirror lag, typically seconds), RTO determined by failover script execution + Consul update propagation (~5-10 min)

**Consul-Based Service Discovery:**
- Purpose: Flip three endpoints atomically (Kafka, Schema Registry, Oracle JDBC) on failover with single KV update
- Pattern: Applications resolve `kafka-bootstrap`, `schema-registry`, `oracle-jdbc` via Consul DNS or KV lookup; point to active region
- Alternative: Hardcoded in app config (legacy reference apps use this), updated manually on failover

## Entry Points

**Terraform Apply (via GitHub Actions):**
- Location: `.github/workflows/terraform-apply.yml`
- Triggers: Merge to main on paths matching `environments/**`, `modules/**`, `schemas/**`
- Responsibilities:
  1. Check out code
  2. Initialize Terraform (with AWS backend credentials from secrets)
  3. Apply Terraform changes (auto-approve after review gate in plan workflow)
  4. Result: New topics created, schemas registered, RBAC updated, DR mirrors created

**Terraform Plan (via GitHub Actions):**
- Location: `.github/workflows/terraform-plan.yml`
- Triggers: Pull request with changes to `environments/`, `modules/`, or `schemas/`
- Responsibilities:
  1. Lint Terraform format
  2. Validate topic naming convention (regex: `^[a-z][a-z0-9-]{1,30}$` for domain/application/entity)
  3. Validate Avro schema JSON syntax, record type, namespace, fields
  4. Validate topic declaration (domain, application, version, entity, owner email, sla_tier, service accounts)
  5. Initialize and validate Terraform
  6. Run terraform plan
  7. Comment plan output on PR

**Local Development (Docker Compose):**
- Location: `reference/local-dev/docker-compose.yml`
- Triggers: Manual `docker compose up -d` by developer
- Responsibilities: Spin up single-node Kafka 7.6.0, Schema Registry 7.6.0, Kafka Connect 7.6.0 (with JDBC connector pre-installed)
- Endpoints: localhost:9092 (Kafka), localhost:8081 (SR), localhost:8083 (Connect)

**Integration Testing (Shell Script):**
- Location: `reference/integration-test/roundtrip-test.sh`
- Triggers: Manual execution or CI step
- Responsibilities: Produce → Schema Registry → Topic → Consume → Deserialize → Verify (5-step roundtrip)

## Error Handling

**Strategy:** Fail early during Terraform plan (validation gates), validate at deployment time (CI/CD), handle connection errors gracefully in reference apps.

**Patterns:**

**Terraform Validation:**
- Topic naming: Regex validation in module variables blocks CR+UX violations pre-apply
- Avro schema syntax: Python validation in CI pipeline (JSON parse, required field checks)
- Terraform format: `terraform fmt -check` enforces consistency
- Terraform validate: Ensures HCL is syntactically correct
- Example in `modules/topic/variables.tf`:
  ```hcl
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}$", var.domain))
    error_message = "Domain must be lowercase alphanumeric with hyphens, 2-31 chars, starting with a letter."
  }
  ```

**Schema Evolution Errors:**
- Blocked by compatibility mode enforcement: If a schema change violates FULL_TRANSITIVE (critical tier), Schema Registry rejects registration
- Documented in ADR-002: teams must plan schema changes carefully for critical topics
- Workaround: Create new versioned topic (e.g., v2) for incompatible changes

**DR Failover Error Handling:**
- Script exits on empty mirror topic list (prevents silent failure)
- Mirror status checked post-promotion: script verifies topics are R/W on West
- Failback has two confirmation gates: truncate-and-restore, then reverse-and-start (prevents accidents)

## Cross-Cutting Concerns

**Logging:**
- Terraform: Plan output captured in GitHub Actions, commented on PR
- DR scripts: Echo statements to stdout, Confluent CLI outputs operation results
- Reference apps (Java): Slf4j logging configured in pom.xml, logs to stdout
- Reference apps (.NET): Console logging

**Validation:**
- Topic naming: Regex in Terraform variables (early fail)
- Schema: JSON syntax + Avro record validation in CI pipeline
- Avro schemas: Field-level doc annotations required (governance standard, not enforced in code)
- RBAC: Confluent Cloud enforces role-based checks at API level (no application-level validation needed)

**Authentication:**
- Confluent Cloud: API key/secret (managed as GitHub Actions secrets)
- Kafka brokers: Authenticated via service account (API key/secret in app config or Vault)
- Schema Registry: Same service account credentials
- Consul: Optional authentication (not shown in reference scripts, assumed configured in Consul policy)

**Authorization:**
- Topics: RBAC via `confluent_role_binding` resources (producer = DeveloperWrite, consumer = DeveloperRead, plus consumer-group bindings)
- Schema Registry: RBAC via `confluent_role_binding` on subject CRN (producers can write, all can read)
- Handled entirely by Terraform module, developers don't implement auth logic

---

*Architecture analysis: 2026-03-21*

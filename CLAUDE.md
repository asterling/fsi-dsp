<!-- GSD:project-start source:PROJECT.md -->
## Project

**FSI Kafka Platform**

A universal, automation-first platform for standing up governed Kafka, Flink, and Schema Registry infrastructure across any deployment model — Confluent Cloud (AWS, Azure, GCP), Confluent Private Cloud, Confluent for Kubernetes on OpenShift, and Confluent Platform on RHEL. It packages FSI-specific C4E assets (Terraform modules, reference implementations, observability templates, DR automation, schema governance) into scenario-based starter kits that any financial institution can adopt in hours, not months.

**Core Value:** Any FSI team can stand up a fully governed, observable, DR-ready Kafka/Flink/SR cluster in their deployment model of choice with a single automation run — and onboard their first topic in under a day.

### Constraints

- **Deployment parity**: Core governance (topic naming, schema compat, RBAC) must work identically across all deployment models
- **No vendor lock-in on observability**: Templates per provider, no single-provider dependency
- **FSI compliance**: Retention policies must support regulatory requirements (up to 7-year for OFAC/AML)
- **Backward compatibility**: Existing Confluent Cloud Terraform modules must continue to work — extend, don't break
- **OpenShift compatibility**: CFK scenario must target OCP 4.x with operator lifecycle management
<!-- GSD:project-end -->

<!-- GSD:stack-start source:codebase/STACK.md -->
## Technology Stack

## Languages
- HCL (Terraform) - Infrastructure as code for Confluent Cloud topic management
- Java 17 - Reference implementations for Kafka producers/consumers
- Python 3 - Schema validation in CI/CD pipelines, integration testing
- C# / .NET - Alternative reference consumer for non-JVM teams
- Avro (JSON-based schema format) - Data serialization and schema registry format
- Bash/Shell - Operational scripts for DR failover, service management
- YAML - GitHub Actions workflows, Kubernetes-style configuration
## Runtime
- Java 17 (reference implementations)
- .NET Framework / Mono (reference consumer)
- Bash/Zsh (operational scripts)
- Docker (containerized local development)
- Terraform 1.7.0+ (infrastructure deployment)
- Maven 3.x (Java project build)
- pip/Python package manager (CI/CD validation)
- Docker Compose (local environment orchestration)
## Frameworks
- Terraform 1.7.0 (`terraform_version` in CI) - Infrastructure as code provider
- Confluent Terraform Provider 2.0+ (`confluentinc/confluent` provider) - Confluent Cloud resource management
- Apache Kafka 7.6.0 (CE and Confluent Cloud) - Message broker
- Confluent Schema Registry 7.6.0 - Schema management and Avro serialization
- Kafka Connect 7.6.0 - Data integration (JDBC source/sink, distributed mode)
- Apache Kafka Clients 3.7.0 - Producer/consumer API
- Confluent Kafka Avro Serializer 7.6.0 - Avro serialization for Kafka
- Avro 1.11.3 - Schema serialization and code generation
- JDBC Connector 10.7.6 - Oracle, SQL Server, PostgreSQL integration
- `kafka-clients` 3.7.0 (Java) - Kafka producer/consumer implementation
- `Confluent.Kafka` .NET package - C# Kafka client
- `Confluent.SchemaRegistry` .NET package - C# Schema Registry client
- SLF4J 2.0.12 - Java logging facade
- SLF4J Simple - Console logging backend (reference implementations)
- Dynatrace JMX exposure (referenced in producer/consumer docs)
## Key Dependencies
- `confluentinc/confluent` Terraform provider v2.0 - Manages Confluent Cloud topics, schemas, RBAC
- Apache Kafka 7.6.0 - Message broker engine
- Confluent Schema Registry 7.6.0 - Schema versioning and compatibility
- `org.apache.kafka:kafka-clients:3.7.0` - Kafka protocol client
- `io.confluent:kafka-avro-serializer:7.6.0` - Avro serialization with Schema Registry integration
- `org.apache.avro:avro:1.11.3` - Avro schema support and code generation
- `io.confluent.kafka.connect:kafka-connect-jdbc:10.7.6` - JDBC source/sink connector for database integration
- JDBC drivers: Oracle JDBC, SQL Server JDBC, PostgreSQL JDBC (database-specific)
- HashiCorp Vault - Referenced in Connect configurations for credential injection (`${vault:secret/...}`)
- Azure Key Vault - Cloud provider integration for Azure deployments
- AWS Secrets Manager - Cloud provider integration for AWS deployments
- Google Secret Manager - Cloud provider integration for GCP deployments
- HashiCorp Consul - Service discovery and endpoint failover management (ADR-003)
- Consul DNS - Resolves Kafka bootstrap, Schema Registry, and database endpoints
## Configuration
- `.env.example` - Single source of truth for all environment-specific variables
- Azure Blob Storage (default) - `azurerm` backend
- AWS S3 - `s3` backend with CloudFormation locking
- Google Cloud Storage - `gcs` backend
- `.github/workflows/terraform-plan.yml` - PR validation: lint, validate Avro schemas, terraform plan
- `.github/workflows/terraform-apply.yml` - Automated apply on merge to main
- Terraform 1.7.0 baseline version
- Environment protection rules for production apply
## Platform Requirements
- Docker 20.10+ (for local Kafka/Schema Registry stack)
- Docker Compose (included with Docker Desktop)
- Terraform 1.5+
- Java 17 JDK (for reference implementations)
- Python 3.8+ (for schema validation scripts)
- Git (for CI/CD workflows)
- Confluent Cloud account with organization and environment
- At minimum two Kafka clusters: Production (East) and DR (West) with cluster linking enabled
- Schema Registry cluster (Confluent Cloud)
- Azure/AWS/GCP VPC/networking for PrivateLink/Private Endpoint connectivity
- Consul cluster (HA recommended) for service discovery
- HashiCorp Vault or managed cloud secrets (Azure Key Vault, AWS Secrets Manager, Google Secret Manager)
- Database infrastructure: Oracle, SQL Server, or PostgreSQL with DR replication
- Dynatrace/Datadog/Splunk observability platform
- GitHub Actions runners (for CI/CD automation)
- Terraform Cloud/Enterprise (optional, for remote state and policy as code)
- Confluent Cloud provisioning (no on-premises Kafka required)
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions

## Naming Patterns
- Java source files: PascalCase class name matching `ClassName.java` (e.g., `FsiProducer.java`)
- Configuration files: kebab-case with extensions (e.g., `connect-distributed-east.properties`, `terraform.tfvars.example`)
- Schema files: kebab-case `.avsc` (e.g., `account-transaction.avsc`)
- Terraform files: `main.tf`, `variables.tf`, `outputs.tf` per module
- Shell scripts: kebab-case with shebang (e.g., `mirror-failover.sh`, `roundtrip-test.sh`)
- .NET classes: PascalCase (e.g., `FsiProducer.cs`, `FsiProducerConfig.cs`)
- Java: camelCase for instance methods (e.g., `send()`, `sendSync()`, `buildProperties()`)
- Java: UPPER_SNAKE_CASE for constants (e.g., `BOOTSTRAP_SERVERS_CONFIG`)
- Shell: snake_case for functions and variables (e.g., `$MIRROR_TOPICS`, `$CONFIRM`)
- .NET: PascalCase for public methods (e.g., `ProduceAsync()`, `Flush()`)
- Java: camelCase (e.g., `topicName`, `totalSent`, `recordHandler`)
- Java atomic counters: camelCase with clear intent (e.g., `totalConsumed`, `lastLatencyMs`)
- Terraform: snake_case (e.g., `var.domain`, `local.topic_name`, `var.producer_service_accounts`)
- Shell: UPPER_SNAKE_CASE for env vars and module-level state (e.g., `$DR_ENV_ID`, `$MIRROR_TOPICS`)
- Shell: lowercase for loop variables and temps (e.g., `i`, `err`)
- .NET: camelCase for private fields (e.g., `_producer`, `_topicName`, `_totalErrors`)
- Terraform: explicit type declarations (e.g., `type = string`, `type = list(string)`, `type = bool`)
- Avro schemas: snake_case field names with logical types (e.g., `transaction_id`, `timestamp` with `timestamp-millis` logical type)
- Java generics: single letter or clear abbreviation (e.g., `KafkaProducer<String, GenericRecord>`)
## Code Style
- Java: 4-space indentation (standard Java convention)
- Terraform: 2-space indentation (HCL standard)
- Shell: 2-space indentation
- .NET: 4-space indentation (C# standard)
- No automatic formatter detected — manual consistency required
- Java: No formal linter config found (Maven enforcer could be added)
- Terraform: Validation syntax is built-in (`terraform validate`)
- Shell: Uses `set -euo pipefail` for strict error handling (see `mirror-failover.sh`)
- .NET: No explicit linting configuration
- Java: JavaDoc for public methods with `/**` blocks (see `FsiProducer.java` lines 42-51, 65-68)
- Java: Single-line comments (`//`) for implementation details
- Shell: Full-width separator comments for sections (e.g., lines 2-3 in `mirror-failover.sh`)
- Terraform: Inline comments with `#` for documentation (see `modules/topic/main.tf` lines 32-34)
## Import Organization
- No explicit ordering — blocks grouped by logical function (e.g., topic config, RBAC bindings, DR mirror)
- Variable references via `var.x` and local computed values via `local.x`
- No path aliases detected in Java codebase
- Terraform uses relative file paths (e.g., `var.schema_file` expects a relative `.avsc` path from the calling module)
## Error Handling
- Log errors at `ERROR` level with context (topic, key, offset)
- Increment error counter atomically
- Include both message and exception (`.getMessage(), e`)
- Comments indicate options: DLQ, retry, alert (see `FsiProducer.java` lines 134-141)
- Exit code checked implicitly by `set -e`
- User confirmation before destructive operations (see `mirror-failover.sh` lines 34-35)
- Specific exception types caught
- Error counters incremented
- Exceptions re-thrown for caller handling
- Inline validation blocks with `regex()` for string constraints
- Clear error messages matching constraint description
- Replaces runtime errors with build-time validation
## Logging
- Static logger instance per class (see `FsiProducer.java` line 32)
- Use parameterized messages: `log.info("Message: {}", param)` not string concatenation
- Log levels:
- Console output with `[FSI Producer]` prefix for identification
- Errors to `Console.Error`
- No structured logging framework detected
## Comments
- Explain WHY, not WHAT (code shows what, comment explains business reason or non-obvious choice)
- Mark integration points and special behaviors (see `FsiProducer.java` line 28: "reference implementation. Copy and adapt")
- Document configuration defaults and justifications (see `modules/topic/main.tf` lines 72-107 for C4E mandatory settings)
- Public classes: Full block with purpose and key characteristics (see `FsiProducer.java` lines 18-29)
- Public methods: Block with `@param` and description (see line 42-51)
- Configuration/builder patterns: Explain the "why" of values (see lines 65-68)
## Function Design
- Map-based config injection: `FsiProducer(Map<String, String> config)` (see line 52)
- Handler functions as functional interfaces: `BiConsumer<String, GenericRecord> recordHandler` (see `FsiConsumer.java` line 44)
- No builder pattern — plain constructor with Map config, derived from environment/Vault at call site
- Void for fire-and-forget (asynchronous): `send(String key, GenericRecord value)` with callback
- RecordMetadata for synchronous: `sendSync()` returns offset/partition/topic
- Wrapper objects for multiple returns (e.g., `FsiProducerConfig` class holds config data)
## Module Design
- Public classes implement interfaces (e.g., `FsiProducer implements AutoCloseable`) for try-with-resources
- Private inner classes for metrics (e.g., `FsiProducerMetrics implements FsiProducerMetricsMBean`)
- Static logger and atomic counters for telemetry
- Single module `modules/topic/` exported via `source = "../../modules/topic"` in environment configs
- Outputs defined in `modules/topic/outputs.tf` (structure not shown, but patterns in `main.tf` lines 91-245 suggest topic name, partition count, schema subject)
- No barrel files — each Terraform module is a single unit
## Shutdown and Lifecycle
- Flush before close to ensure durability
- 30-second timeout for graceful termination
- Log final metrics (total sent, errors)
- Implement try-with-resources usage
- Named thread for identification in logs
- Calls `consumer.wakeup()` to unblock poll loop
## Cross-Cutting Concerns
- Terraform: Inline `validation` blocks with regex or function-based checks (see `modules/topic/variables.tf` lines 12-15, 103-106)
- Java: Constructor parameter validation with `IllegalArgumentException` (see `FsiProducer.java` lines 54-56)
- Email validation: RFC-like pattern `^[^@]+@[^@]+\\.[^@]+$` (see `variables.tf` line 56)
- Environment variable defaults in Java: `config.getOrDefault("key", "default")`
- Terraform locals for computed values (topic_name assembly, SLA-tier mappings)
- Shell: Environment variables with `${VAR:?Set VAR}` for required, `${VAR:-default}` for optional
- Map-based config object passed to constructor (not Spring annotations or frameworks)
- Handler functions injected as functional interfaces (consumer pattern)
- Terraform variables injected via tfvars files or environment
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

## Pattern Overview
- Single reusable Terraform module produces fully governed topics (topic + schema + RBAC + DR mirror + metadata tags)
- Schema-first design with Avro as the canonical format and compatibility modes derived from SLA tier
- SLA-tier-based configuration (critical, standard, best-effort) determines compatibility, partitions, and retention automatically
- Dual-cluster topology: East (active production) + West (passive DR) connected via Confluent Cluster Linking
- Consul-based service discovery for atomic DR failover across Kafka, Schema Registry, and databases
## Layers
- Purpose: Provision Confluent Cloud resources (Kafka clusters, Schema Registry, topics, RBAC, cluster links)
- Location: `modules/topic/` (reusable module) and `environments/prod/` (environment-specific declarations)
- Contains: Terraform resource definitions for `confluent_kafka_topic`, `confluent_schema`, `confluent_subject_config`, `confluent_role_binding`, `confluent_kafka_mirror_topic`
- Depends on: Confluent Cloud provider, AWS/Azure/GCP backend for Terraform state
- Used by: CI/CD pipeline (GitHub Actions) triggers on topic or schema changes
- Purpose: Define, version, and validate Avro schemas; enforce compatibility across schema evolution
- Location: `schemas/examples/` (reference schemas), validated by CI pipeline
- Contains: `.avsc` files following `{domain}-{entity}.avsc` naming convention, with field-level documentation and PII tagging
- Depends on: Confluent Schema Registry (managed service on CC)
- Used by: Producers, consumers, and Kafka Connect connectors for serialization/deserialization
- Purpose: Handle disaster recovery failover/failback and operational scripts
- Location: `scripts/` (failover, failback, connect pause/resume operations)
- Contains: Bash scripts that invoke Confluent CLI and Consul API to orchestrate DR operations
- Depends on: Confluent Cloud Kafka CLI, Consul HTTP API, cluster link configuration
- Used by: On-call engineers during regional outages
- Purpose: Establish standards, patterns, and runbooks for teams using the platform
- Location: `docs/` (schema guide, onboarding, ADRs), `.github/` (PR template, CI validation)
- Contains: Architecture Decision Records (ADRs), self-service intake forms, schema evolution guidelines, cloud provider differences
- Depends on: GitHub, C4E review process
- Used by: Teams requesting new topics, schema evolution approvals
- Purpose: Provide working examples for producer/consumer development and integration testing
- Location: `reference/` (Java/dotnet producers/consumers, Connect configs, Docker Compose, integration tests)
- Contains: Complete working applications, Connect JDBC configs (East/West), local development Docker Compose
- Depends on: Confluent Community Edition (local dev), Java/dotnet SDKs (Confluent clients)
- Used by: Development teams bootstrapping new applications
## Data Flow
- **Topic state:** Kafka broker (replicated across partitions), Schema Registry (immutable schema versions)
- **Configuration state:** Terraform state (stored in S3/Azure Blob/GCS, locked during apply)
- **DR state:** Cluster link bidirectional replication with mirror lag visible via Confluent CLI
- **Service discovery state:** Consul KV store (`fsi/kafka/active-region` key determines which region endpoints are active)
## Key Abstractions
- Purpose: Encapsulates the pattern for creating a fully governed topic in a single reusable call
- Examples: `module "corebanking_account_txn"`, `module "fraud_alert_signal"`, `module "compliance_screening_result"`
- Pattern:
- Purpose: Reduce boilerplate; configuration (compatibility, partitions, retention) derived from single input
- Pattern (in `modules/topic/main.tf` locals):
- Allows overrides (compatibility_override, partitions_override, retention_ms_override) for documented exceptions
- Purpose: Enable data governance, PII detection, ownership tracking without external tools
- Pattern: Metadata properties on schema subject include owner, sla-tier, data-classification, domain, application, pii flag, pii-fields list
- Used by: Data lineage tools (Alation), compliance scanning, cost allocation
- Purpose: Achieve RPO ~2 hours (target) with passive async replication; automatic promotion on failover
- Pattern: Bidirectional cluster link from East (primary) to West (DR), mirror topics created on West, manual promotion via Confluent CLI (6 scripted steps)
- Consequence: RPO > 0 (bounded by mirror lag, typically seconds), RTO determined by failover script execution + Consul update propagation (~5-10 min)
- Purpose: Flip three endpoints atomically (Kafka, Schema Registry, Oracle JDBC) on failover with single KV update
- Pattern: Applications resolve `kafka-bootstrap`, `schema-registry`, `oracle-jdbc` via Consul DNS or KV lookup; point to active region
- Alternative: Hardcoded in app config (legacy reference apps use this), updated manually on failover
## Entry Points
- Location: `.github/workflows/terraform-apply.yml`
- Triggers: Merge to main on paths matching `environments/**`, `modules/**`, `schemas/**`
- Responsibilities:
- Location: `.github/workflows/terraform-plan.yml`
- Triggers: Pull request with changes to `environments/`, `modules/`, or `schemas/`
- Responsibilities:
- Location: `reference/local-dev/docker-compose.yml`
- Triggers: Manual `docker compose up -d` by developer
- Responsibilities: Spin up single-node Kafka 7.6.0, Schema Registry 7.6.0, Kafka Connect 7.6.0 (with JDBC connector pre-installed)
- Endpoints: localhost:9092 (Kafka), localhost:8081 (SR), localhost:8083 (Connect)
- Location: `reference/integration-test/roundtrip-test.sh`
- Triggers: Manual execution or CI step
- Responsibilities: Produce → Schema Registry → Topic → Consume → Deserialize → Verify (5-step roundtrip)
## Error Handling
- Topic naming: Regex validation in module variables blocks CR+UX violations pre-apply
- Avro schema syntax: Python validation in CI pipeline (JSON parse, required field checks)
- Terraform format: `terraform fmt -check` enforces consistency
- Terraform validate: Ensures HCL is syntactically correct
- Example in `modules/topic/variables.tf`:
- Blocked by compatibility mode enforcement: If a schema change violates FULL_TRANSITIVE (critical tier), Schema Registry rejects registration
- Documented in ADR-002: teams must plan schema changes carefully for critical topics
- Workaround: Create new versioned topic (e.g., v2) for incompatible changes
- Script exits on empty mirror topic list (prevents silent failure)
- Mirror status checked post-promotion: script verifies topics are R/W on West
- Failback has two confirmation gates: truncate-and-restore, then reverse-and-start (prevents accidents)
## Cross-Cutting Concerns
- Terraform: Plan output captured in GitHub Actions, commented on PR
- DR scripts: Echo statements to stdout, Confluent CLI outputs operation results
- Reference apps (Java): Slf4j logging configured in pom.xml, logs to stdout
- Reference apps (.NET): Console logging
- Topic naming: Regex in Terraform variables (early fail)
- Schema: JSON syntax + Avro record validation in CI pipeline
- Avro schemas: Field-level doc annotations required (governance standard, not enforced in code)
- RBAC: Confluent Cloud enforces role-based checks at API level (no application-level validation needed)
- Confluent Cloud: API key/secret (managed as GitHub Actions secrets)
- Kafka brokers: Authenticated via service account (API key/secret in app config or Vault)
- Schema Registry: Same service account credentials
- Consul: Optional authentication (not shown in reference scripts, assumed configured in Consul policy)
- Topics: RBAC via `confluent_role_binding` resources (producer = DeveloperWrite, consumer = DeveloperRead, plus consumer-group bindings)
- Schema Registry: RBAC via `confluent_role_binding` on subject CRN (producers can write, all can read)
- Handled entirely by Terraform module, developers don't implement auth logic
<!-- GSD:architecture-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd:quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd:debug` for investigation and bug fixing
- `/gsd:execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->



<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd:profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->

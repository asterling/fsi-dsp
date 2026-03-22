# Codebase Structure

**Analysis Date:** 2026-03-21

## Directory Layout

```
fsi-kafka-platform/
├── .env.example                          # Environment variables template (copy → .env)
├── .github/                              # CI/CD pipelines and templates
│   ├── workflows/
│   │   ├── terraform-plan.yml            # PR validation pipeline
│   │   └── terraform-apply.yml           # Post-merge apply pipeline
│   ├── ISSUE_TEMPLATE/
│   │   └── new-topic-request.md          # Self-service intake form
│   └── pull_request_template.md          # Merge checklist
├── docs/                                 # Documentation and standards
│   ├── adr/                              # Architecture Decision Records (001-005)
│   │   ├── 001-avro-over-protobuf.md
│   │   ├── 002-compatibility-by-tier.md
│   │   ├── 003-consul-service-discovery.md
│   │   ├── 004-onprem-connect.md
│   │   └── 005-cluster-linking-over-mrc.md
│   ├── cloud-providers.md                # Azure vs AWS vs GCP differences
│   ├── schema-guide.md                   # Schema naming, compatibility, evolution rules
│   ├── onboarding.md                     # Self-service workflow for new teams
│   └── adr/000-template.md               # ADR template
├── modules/                              # Reusable Terraform modules
│   └── topic/                            # Single core module for topic provisioning
│       ├── main.tf                       # Topic, schema, RBAC, DR mirror resources
│       ├── variables.tf                  # Module inputs (domain, app, version, entity, etc.)
│       └── outputs.tf                    # Module outputs (topic_name, subject, compatibility, etc.)
├── environments/                         # Environment-specific IaC declarations
│   └── prod/                             # Production environment
│       ├── main.tf                       # Provider config, locals with infrastructure refs
│       ├── example-topics.tf             # 3 example module calls (copy & adapt)
│       ├── terraform.tfvars.example      # Variable values template
│       └── (+ additional topic files)    # Each team adds their topic declarations here
├── schemas/                              # Avro schema definitions
│   └── examples/                         # Reference schemas for common FSI entities
│       ├── account-balance.avsc
│       ├── account-transaction.avsc
│       ├── compliance-match-result.avsc
│       ├── fraud-alert-signal.avsc
│       ├── fraud-score-result.avsc
│       ├── integration-event.avsc
│       └── member-update.avsc
├── reference/                            # Working examples and reference implementations
│   ├── java-producer/                    # Complete idempotent producer with Dynatrace JMX
│   │   ├── pom.xml
│   │   └── src/main/java/org/fsi/kafka/producer/
│   │       ├── ExampleApp.java
│   │       └── FsiProducer.java
│   ├── java-consumer/                    # Complete consumer with manual commit and graceful shutdown
│   │   ├── pom.xml
│   │   └── src/main/java/org/fsi/kafka/consumer/
│   │       ├── ExampleApp.java
│   │       └── FsiConsumer.java
│   ├── dotnet-producer/                  # .NET reference for non-JVM teams
│   │   └── FsiProducer.cs
│   ├── dotnet-consumer/                  # .NET consumer reference
│   │   └── FsiConsumer.cs
│   ├── connect-configs/                  # Kafka Connect JDBC source/sink configs
│   │   ├── jdbc-source-example.json      # Oracle → Kafka
│   │   ├── jdbc-sink-example.json        # Kafka → Oracle
│   │   ├── connect-distributed-east.properties
│   │   └── connect-distributed-west.properties
│   ├── local-dev/                        # Docker Compose for local Kafka + SR + Connect
│   │   ├── docker-compose.yml            # Single-node broker, SR, Connect (JDBC pre-installed)
│   │   └── README.md
│   └── integration-test/                 # Roundtrip produce-consume verification
│       ├── roundtrip-test.sh             # 5-step integration test script
│       └── README.md
├── scripts/                              # Operational scripts for DR and maintenance
│   ├── mirror-failover.sh                # Step 1: Promote mirror topics on West cluster
│   ├── mirror-failback.sh                # Step 2: Restore East as primary
│   ├── consul-flip-region.sh             # Step 2: Update Consul KV for endpoint flip
│   └── connect-pause-all.sh              # Maintenance: pause all Kafka Connect workers
├── .gitignore                            # Git exclusions
├── README.md                             # Quick start guide
└── LICENSE                               # Proprietary — GoodLabs Studio
```

## Directory Purposes

**`.env.example`:**
- Purpose: Template for environment-specific variables
- Contains: Confluent Cloud organization ID, environment ID, cluster IDs, endpoints, API key references, Terraform backend config
- Copy to `.env` and fill in per engagement
- Never committed (`.env` in `.gitignore`)

**`.github/`:**
- Purpose: GitHub Actions workflows and issue/PR templates
- CI/CD: `terraform-plan.yml` (linting, validation, planning on PR) and `terraform-apply.yml` (apply on merge to main)
- Governance: Issue template (`new-topic-request.md`) for intake, PR template for merge checklist

**`docs/`:**
- Purpose: Standards, patterns, and decision records
- ADRs (001-005): Architectural decisions on Avro, compatibility tiers, Consul discovery, Cluster Linking
- Guides: Schema naming/compatibility evolution (`schema-guide.md`), cloud provider differences (`cloud-providers.md`)
- Onboarding: Self-service workflow for teams requesting new topics (`onboarding.md`)

**`modules/topic/`:**
- Purpose: Single reusable Terraform module that teams use to declare topics
- Core files:
  - `main.tf`: Kafka topic resource, Avro schema registration, subject compatibility config, RBAC role bindings (producer/consumer/SR), DR mirror topic
  - `variables.tf`: Validated inputs (domain, application, version, entity, owner, sla_tier, schema_file, pii_fields, service accounts, overrides)
  - `outputs.tf`: topic_name, schema_subject, compatibility_mode, partitions, retention_ms, DR mirror ID, schema metadata
- **Critical:** Do not modify per-engagement; extends via variables and locals only

**`environments/prod/`:**
- Purpose: Environment-specific Terraform configuration and topic declarations
- Core files:
  - `main.tf`: Terraform backend config, Confluent provider config, locals with infrastructure refs (cluster IDs, endpoints, CRNs)
  - `example-topics.tf`: 3 reference module calls (corebanking_account_txn, fraud_alert_signal, compliance_screening_result) for teams to copy and adapt
  - `terraform.tfvars.example`: Variable values template (copy → terraform.tfvars)
- Teams add their topic declarations in this directory (one `.tf` file per domain or application)

**`schemas/examples/`:**
- Purpose: Reference Avro schemas for common FSI entities
- Naming: `{domain}-{entity}.avsc` (e.g., `account-transaction.avsc`, `fraud-alert-signal.avsc`)
- Contents: Avro record definitions with field-level `doc` annotations, enum types, logical types (decimal for money, timestamp-millis for times, date for dates)
- Used by: Producers/consumers for serialization, Terraform module to register with Schema Registry

**`reference/`:**
- Purpose: Working examples and runnable code for teams bootstrapping services
- Java: Complete producer (`FsiProducer.java`) with idempotency, Avro serialization, Dynatrace JMX monitoring; complete consumer (`FsiConsumer.java`) with manual offset management and graceful shutdown
- .NET: `FsiProducer.cs` and `FsiConsumer.cs` for non-JVM teams
- Docker Compose: Single-node local development Kafka + SR + Connect with JDBC connector pre-installed
- Connect: JDBC source/sink configs and distributed properties files (East/West)
- Integration test: 5-step roundtrip validation script

**`scripts/`:**
- Purpose: DR failover/failback automation and operational maintenance
- DR: `mirror-failover.sh` (promote West mirror topics), `mirror-failback.sh` (restore East as primary), `consul-flip-region.sh` (update service discovery)
- Maintenance: `connect-pause-all.sh` (pause all Connect workers)

## Key File Locations

**Entry Points:**

- `environments/prod/main.tf`: Terraform provider and infrastructure configuration (start here for new deployments)
- `.github/workflows/terraform-plan.yml`: CI validation pipeline (defines merge gate)
- `.github/workflows/terraform-apply.yml`: Automated apply on merge to main
- `reference/local-dev/docker-compose.yml`: Local development bootstrap

**Configuration:**

- `.env.example`: Environment variables template (Confluent Cloud IDs, API key references, backend config)
- `environments/prod/terraform.tfvars.example`: Terraform variable values (copy and fill in)
- `modules/topic/variables.tf`: Module input schema (defines what teams must provide)

**Core Logic:**

- `modules/topic/main.tf`: Topic creation, schema registration, RBAC, DR mirror (the platform's core logic)
- `modules/topic/variables.tf`: Input validation (regex for naming, enum checks for sla_tier, email validation for owner)
- `modules/topic/locals`: SLA tier mapping to compatibility/partitions/retention (single source of truth for defaults)

**Testing:**

- `reference/integration-test/roundtrip-test.sh`: End-to-end validation (produce → consume → verify)
- `.github/workflows/terraform-plan.yml`: Schema JSON validation, topic naming validation, Terraform validate

**Reference Applications:**

- `reference/java-producer/src/main/java/org/fsi/kafka/producer/FsiProducer.java`: Idempotent producer pattern
- `reference/java-consumer/src/main/java/org/fsi/kafka/consumer/FsiConsumer.java`: Consumer with manual commit
- `reference/local-dev/docker-compose.yml`: Development environment setup

## Naming Conventions

**Files:**

- Terraform files: `.tf` extension, snake_case (e.g., `main.tf`, `example-topics.tf`, `terraform.tfvars`)
- Avro schemas: `.avsc` extension, `{domain}-{entity}.avsc` (e.g., `account-transaction.avsc`, `fraud-alert-signal.avsc`)
- Scripts: `.sh` extension, kebab-case (e.g., `mirror-failover.sh`, `connect-pause-all.sh`)
- GitHub workflows: `.yml` extension, kebab-case (e.g., `terraform-plan.yml`, `terraform-apply.yml`)
- Documentation: `.md` extension, UPPERCASE for codebase docs (e.g., `ARCHITECTURE.md`, `STRUCTURE.md`), lowercase for guides (e.g., `schema-guide.md`, `cloud-providers.md`)

**Directories:**

- IaC by environment: `environments/{environment-name}/` (e.g., `environments/prod/`)
- Modules: `modules/{module-name}/` (e.g., `modules/topic/`)
- Schema collections: `schemas/{collection}/` (e.g., `schemas/examples/`)
- Reference code by language/pattern: `reference/{language}-{pattern}/` (e.g., `reference/java-producer/`, `reference/dotnet-consumer/`)
- Infrastructure config: `reference/connect-configs/`, `reference/local-dev/`
- Governance docs: `docs/`, with `docs/adr/` for Architecture Decision Records

**Topic Naming (Kafka):**

Format: `{domain}.{application}.{version}.{entity}`

- **domain**: Business domain (lowercase, 2-31 chars, alphanumeric + hyphens, must start with letter)
  - Examples: `corebanking`, `fraud`, `compliance`, `ofac`, `eventgrid`
- **application**: App within domain (lowercase, 2-31 chars, alphanumeric + hyphens)
  - Examples: `core`, `alerts`, `detection`, `screening`
- **version**: Schema version (format: `v{number}`, e.g., `v1`, `v2`)
- **entity**: Data entity (lowercase, 2-61 chars, alphanumeric + hyphens)
  - Examples: `account-transaction`, `fraud-signal`, `alert-signal`, `match-result`

Full example: `corebanking.core.v1.account-transaction`

## Where to Add New Code

**New Topic (90% of requests):**

1. Create Avro schema: `schemas/{domain}-{entity}.avsc`
   - Use `schemas/examples/account-transaction.avsc` as template
   - Include field-level `doc` annotations
   - Tag PII fields in the schema or note them in Terraform `pii_fields` variable
2. Add Terraform module call: `environments/prod/{domain}.tf` (or append to existing domain file)
   - Copy from `example-topics.tf`
   - Fill in domain, application, version, entity, owner (team email), sla_tier, schema_file, pii_fields, producer/consumer service accounts
   - Reference infrastructure locals from `main.tf`
3. Submit PR → CI validates → C4E review → Merge → Auto-apply

**New Producer or Consumer Application:**

1. Copy reference implementation from `reference/java-producer/` or `reference/java-consumer/` (language-appropriate)
2. Update bootstrap server, topic name, schema subject
3. Fetch API key/secret for service account from Confluent Cloud
4. Test locally against `reference/local-dev/` Docker Compose

**New Kafka Connect Connector:**

1. Add connector JSON config: `reference/connect-configs/{connector-type}-{description}.json`
2. Reference `reference/connect-configs/jdbc-source-example.json` or `jdbc-sink-example.json` as template
3. Upload to Confluent Cloud (or local dev via Connect REST API on localhost:8083)
4. For distributed Connect setup, reference `connect-distributed-east.properties` / `connect-distributed-west.properties`

**Schema Evolution (existing topic):**

1. Update `schemas/{domain}-{entity}.avsc`
2. For **critical** SLA topics (FULL_TRANSITIVE): Only add optional fields with defaults (e.g., `{"name": "new_field", "type": ["null", "string"], "default": null}`)
3. For **standard** or **best-effort**: Can also remove fields or change types (BACKWARD_TRANSITIVE / BACKWARD allow this)
4. Submit PR → CI validates schema JSON → Terraform plan shows schema update → C4E review → Merge → Schema Registry registers new version
5. Deploy consumers first (can handle old + new data), then producers

**Override SLA Defaults (rare):**

1. In module call, add optional override variables:
   - `compatibility_override`: One of `BACKWARD`, `BACKWARD_TRANSITIVE`, `FULL_TRANSITIVE`, etc.
   - `partitions_override`: Integer (e.g., 24 for high-throughput topic)
   - `retention_ms_override`: Integer milliseconds (e.g., 1209600000 for 14 days)
2. Document override in PR description (C4E approval required for compliance topics)

**Add Utility Functions or Shared Code:**

- Helper functions: Add to `reference/{language}-{component}/` as new file or module (no single "shared utilities" directory; keep code co-located with examples)
- Terraform helpers: Add to `modules/topic/` as local blocks if applicable to all topics, otherwise keep in `environments/prod/main.tf` as environment locals

## Special Directories

**`modules/topic/`:**
- Purpose: Core reusable module
- Generated: No (hand-coded Terraform)
- Committed: Yes (source of truth)
- **CRITICAL:** Do not fork or create per-engagement variants; extend via variables only

**`environments/prod/`:**
- Purpose: Production topic declarations (teams own these)
- Generated: No (teams write module calls)
- Committed: Yes (infrastructure declarations)
- Expected growth: Each domain/team adds their `.tf` files here

**`schemas/examples/`:**
- Purpose: Reference schemas for common FSI data entities
- Generated: No (hand-curated)
- Committed: Yes
- Expected growth: Teams may add custom schemas to `schemas/` root or keep using examples with overrides

**`reference/local-dev/`:**
- Purpose: Local development environment
- Generated: Docker volumes and containers (temporary, cleaned up with `docker compose down`)
- Committed: `docker-compose.yml` and `README.md` only (volumes are not committed)

**`reference/java-producer/` and similar:**
- Purpose: Runnable reference code
- Generated: No (hand-coded examples)
- Committed: Yes (source code only, not `target/` directory)

**`.github/`:**
- Purpose: CI/CD automation and issue/PR templates
- Generated: No (hand-coded workflows)
- Committed: Yes (workflows are the source of truth for CI/CD)
- **Note:** Secrets are managed in GitHub Actions environment settings (not in repo)

---

*Structure analysis: 2026-03-21*

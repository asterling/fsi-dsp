# Technology Stack

**Analysis Date:** 2026-03-21

## Languages

**Primary:**
- HCL (Terraform) - Infrastructure as code for Confluent Cloud topic management
- Java 17 - Reference implementations for Kafka producers/consumers
- Python 3 - Schema validation in CI/CD pipelines, integration testing
- C# / .NET - Alternative reference consumer for non-JVM teams

**Markup/Configuration:**
- Avro (JSON-based schema format) - Data serialization and schema registry format
- Bash/Shell - Operational scripts for DR failover, service management
- YAML - GitHub Actions workflows, Kubernetes-style configuration

## Runtime

**Environment:**
- Java 17 (reference implementations)
- .NET Framework / Mono (reference consumer)
- Bash/Zsh (operational scripts)
- Docker (containerized local development)
- Terraform 1.7.0+ (infrastructure deployment)

**Package Manager:**
- Maven 3.x (Java project build)
- pip/Python package manager (CI/CD validation)
- Docker Compose (local environment orchestration)

## Frameworks

**Core Infrastructure:**
- Terraform 1.7.0 (`terraform_version` in CI) - Infrastructure as code provider
- Confluent Terraform Provider 2.0+ (`confluentinc/confluent` provider) - Confluent Cloud resource management
- Apache Kafka 7.6.0 (CE and Confluent Cloud) - Message broker
- Confluent Schema Registry 7.6.0 - Schema management and Avro serialization
- Kafka Connect 7.6.0 - Data integration (JDBC source/sink, distributed mode)

**Messaging & Data Flow:**
- Apache Kafka Clients 3.7.0 - Producer/consumer API
- Confluent Kafka Avro Serializer 7.6.0 - Avro serialization for Kafka
- Avro 1.11.3 - Schema serialization and code generation
- JDBC Connector 10.7.6 - Oracle, SQL Server, PostgreSQL integration

**Client Libraries:**
- `kafka-clients` 3.7.0 (Java) - Kafka producer/consumer implementation
- `Confluent.Kafka` .NET package - C# Kafka client
- `Confluent.SchemaRegistry` .NET package - C# Schema Registry client

**Observability & Logging:**
- SLF4J 2.0.12 - Java logging facade
- SLF4J Simple - Console logging backend (reference implementations)
- Dynatrace JMX exposure (referenced in producer/consumer docs)

## Key Dependencies

**Critical Infrastructure:**
- `confluentinc/confluent` Terraform provider v2.0 - Manages Confluent Cloud topics, schemas, RBAC
- Apache Kafka 7.6.0 - Message broker engine
- Confluent Schema Registry 7.6.0 - Schema versioning and compatibility

**Required for Producers/Consumers:**
- `org.apache.kafka:kafka-clients:3.7.0` - Kafka protocol client
- `io.confluent:kafka-avro-serializer:7.6.0` - Avro serialization with Schema Registry integration
- `org.apache.avro:avro:1.11.3` - Avro schema support and code generation

**Data Integration:**
- `io.confluent.kafka.connect:kafka-connect-jdbc:10.7.6` - JDBC source/sink connector for database integration
- JDBC drivers: Oracle JDBC, SQL Server JDBC, PostgreSQL JDBC (database-specific)

**Secrets & Credentials:**
- HashiCorp Vault - Referenced in Connect configurations for credential injection (`${vault:secret/...}`)
- Azure Key Vault - Cloud provider integration for Azure deployments
- AWS Secrets Manager - Cloud provider integration for AWS deployments
- Google Secret Manager - Cloud provider integration for GCP deployments

**Service Discovery:**
- HashiCorp Consul - Service discovery and endpoint failover management (ADR-003)
- Consul DNS - Resolves Kafka bootstrap, Schema Registry, and database endpoints

## Configuration

**Environment:**
- `.env.example` - Single source of truth for all environment-specific variables
  - Confluent Cloud credentials (`CC_*` variables)
  - Cloud provider configuration (`CLOUD_PROVIDER`, `AZURE_*`, etc.)
  - Database endpoints (`DB_*` variables)
  - Observability endpoints (`OBSERVABILITY_PROVIDER`, `DYNATRACE_*`)
  - Service discovery configuration (`SD_PROVIDER`, `CONSUL_*`)
  - Secrets provider selection (`SECRETS_PROVIDER`)
  - Terraform backend selection (`TERRAFORM_BACKEND`)

**Terraform Backend Targets:**
- Azure Blob Storage (default) - `azurerm` backend
- AWS S3 - `s3` backend with CloudFormation locking
- Google Cloud Storage - `gcs` backend

**Build & CI/CD:**
- `.github/workflows/terraform-plan.yml` - PR validation: lint, validate Avro schemas, terraform plan
- `.github/workflows/terraform-apply.yml` - Automated apply on merge to main
- Terraform 1.7.0 baseline version
- Environment protection rules for production apply

## Platform Requirements

**Development:**
- Docker 20.10+ (for local Kafka/Schema Registry stack)
- Docker Compose (included with Docker Desktop)
- Terraform 1.5+
- Java 17 JDK (for reference implementations)
- Python 3.8+ (for schema validation scripts)
- Git (for CI/CD workflows)

**Production:**
- Confluent Cloud account with organization and environment
- At minimum two Kafka clusters: Production (East) and DR (West) with cluster linking enabled
- Schema Registry cluster (Confluent Cloud)
- Azure/AWS/GCP VPC/networking for PrivateLink/Private Endpoint connectivity
- Consul cluster (HA recommended) for service discovery
- HashiCorp Vault or managed cloud secrets (Azure Key Vault, AWS Secrets Manager, Google Secret Manager)
- Database infrastructure: Oracle, SQL Server, or PostgreSQL with DR replication
- Dynatrace/Datadog/Splunk observability platform

**Deployment:**
- GitHub Actions runners (for CI/CD automation)
- Terraform Cloud/Enterprise (optional, for remote state and policy as code)
- Confluent Cloud provisioning (no on-premises Kafka required)

---

*Stack analysis: 2026-03-21*

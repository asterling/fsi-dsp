# Phase 6: Flink on Confluent Cloud - Research

**Researched:** 2026-03-26
**Domain:** Confluent Cloud Flink SQL (compute pools, SQL statements, Schema Registry integration, observability, DLQ handling) via Terraform
**Confidence:** MEDIUM-HIGH

## Summary

Phase 6 adds Flink stream processing to the FSI Kafka Platform via Confluent Cloud's managed Flink service. The core deliverables are: (1) a Terraform module for provisioning CC Flink compute pools and submitting Flink SQL statements, (2) reference SQL templates for three FSI-relevant stream processing patterns (tumbling window aggregation, stream-table join enrichment, filter-and-route), (3) Schema Registry auto-discovery for Avro serde, (4) Flink job metrics wired into the existing observability provider dashboards (all 6 providers already have Flink stub panels from Phase 5), and (5) DLQ handling for deserialization/processing failures.

The Confluent Terraform provider (currently at v2.65.0 in this project) has GA-level support for `confluent_flink_compute_pool` and `confluent_flink_statement` resources. CC Flink auto-discovers Schema Registry subjects and maps them to Flink tables automatically -- no manual connector or format configuration needed. The DLQ pattern in CC Flink uses `error-handling.mode` and `error-handling.log.target` table properties (not Apache Flink's side output API), which is a significant difference from open-source Flink.

**Primary recommendation:** Create a `modules/flink/` Terraform module for compute pool provisioning, add reference SQL templates in `reference/flink-sql/`, wire Flink Metrics API metrics (`io.confluent.flink/*`) into the existing observability stubs, and extend scenario directories to include Flink resources.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| FLINK-01 | CC Flink compute pool provisioned via Terraform (`confluent_flink_compute_pool`, `confluent_flink_statement`) | Confluent provider v2.65.0 has GA support for both resources. Compute pool requires: display_name, cloud, region, max_cfu, environment. Statement requires: statement SQL, properties, compute_pool, principal, credentials. |
| FLINK-04 | Flink SQL reference templates for tumbling window aggregation, stream-table join enrichment, and filter-and-route patterns | CC Flink SQL supports TUMBLE() TVF with GROUP BY window_start/window_end, temporal JOIN with FOR SYSTEM_TIME AS OF, and EXECUTE STATEMENT SET for multi-output filter-and-route. |
| FLINK-05 | Flink integrates with Schema Registry for Avro serde (CC Flink auto-discovers SR subjects) | CC Flink auto-infers environments, clusters, topics, and schemas. No manual table definition needed -- topics with registered Avro schemas appear as queryable tables automatically. |
| FLINK-06 | Flink job metrics (checkpoint duration, backpressure, throughput) exported to each provider's dashboard templates | CC Metrics API exposes `io.confluent.flink/num_records_in`, `io.confluent.flink/num_records_out`, `io.confluent.flink/pending_records`, and CFU utilization metrics. Phase 5 created stub panels in all 6 provider dashboards. |
| FLINK-07 | Flink dead letter handling routes deserialization/processing failures to `{topic}.dlq` topics via side output pattern | CC Flink uses `error-handling.mode = 'log'` and `error-handling.log.target = '{topic}.dlq'` table properties -- NOT Apache Flink side outputs. DLQ table is auto-created. Only deserialization errors are routed; UDF errors are not. |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Confluent Terraform Provider | ~> 2.0 (installed: 2.65.0) | `confluent_flink_compute_pool` and `confluent_flink_statement` resources | GA resources in the provider already used by this project for topics, schemas, RBAC |
| Confluent Cloud Flink SQL | Managed (CC current) | Stream processing engine | Fully managed, auto-scales via Autopilot, auto-discovers SR subjects |
| Confluent Cloud Metrics API | v2 | Flink job metrics export | Same API already used for Kafka/Connect metrics in Phase 5 observability |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `confluent_flink_compute_pool` (data source) | ~> 2.0 | Reference existing compute pools | When pool is created outside Terraform |
| `confluent_flink_connection` | ~> 2.0 | External database connections from Flink | Future: when Flink needs to join with external data sources |
| `confluent_api_key` (Flink type) | ~> 2.0 | Flink-specific API key for statement execution | Required for `confluent_flink_statement` credentials |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| CC managed Flink | Self-managed Flink on K8s | CC is zero-ops but less configurable; K8s Flink deferred to Phase 8 |
| Flink SQL via Terraform | Flink SQL via Confluent CLI | Terraform enables IaC/GitOps; CLI is for ad-hoc interactive use |
| error-handling.mode DLQ | Custom side output (Java API) | CC Flink SQL does not expose Apache Flink side output API; DLQ table properties are the only option |

## Architecture Patterns

### Recommended Project Structure
```
modules/
  topic/            # Existing: governed topic module
  flink/            # NEW: Flink compute pool + statement module
    main.tf         # compute_pool + flink_statement resources
    variables.tf    # Pool config, statement SQL, DLQ settings
    outputs.tf      # Pool ID, statement status
reference/
  flink-sql/        # NEW: Reference SQL templates
    tumbling-window-aggregation.sql
    stream-table-join-enrichment.sql
    filter-and-route.sql
    dlq-pattern.sql
    README.md       # Usage guide with FSI examples
scenarios/
  cc-aws/
    flink.tf        # NEW: Flink resources for AWS scenario
  cc-azure/
    flink.tf        # NEW: Flink resources for Azure scenario
  cc-gcp/
    flink.tf        # NEW: Flink resources for GCP scenario
observability/
  {provider}/
    dashboard-flink-jobs.json  # EXISTS (Grafana), UPDATE stubs in others
    alerts-flink.yaml          # NEW: Flink-specific alert rules
```

### Pattern 1: Flink Compute Pool Provisioning
**What:** A reusable module that provisions a CC Flink compute pool and optionally submits Flink SQL statements
**When to use:** Every CC deployment that needs stream processing
**Example:**
```hcl
# Source: Confluent Terraform Provider docs + CC Flink docs
resource "confluent_flink_compute_pool" "main" {
  display_name = "fsi-${var.environment}-pool"
  cloud        = var.cloud_provider  # "AWS", "AZURE", "GCP"
  region       = var.flink_region
  max_cfu      = var.max_cfu         # 5, 10, 20, 30, 40, or 50

  environment {
    id = var.environment_id
  }

  lifecycle {
    prevent_destroy = true  # Protect production pools
  }
}
```

### Pattern 2: Flink SQL Statement as Terraform Resource
**What:** Each Flink SQL statement is a managed Terraform resource with lifecycle control
**When to use:** For persistent streaming jobs (not ad-hoc queries)
**Example:**
```hcl
# Source: Confluent Terraform Provider docs
resource "confluent_flink_statement" "tumbling_agg" {
  organization {
    id = var.organization_id
  }
  environment {
    id = var.environment_id
  }
  compute_pool {
    id = confluent_flink_compute_pool.main.id
  }
  principal {
    id = var.flink_service_account_id
  }

  statement = file("${path.module}/sql/tumbling-window-aggregation.sql")

  properties = {
    "sql.current-catalog"  = var.environment_display_name
    "sql.current-database" = var.kafka_cluster_display_name
  }

  rest_endpoint = var.flink_rest_endpoint

  credentials {
    key    = var.flink_api_key
    secret = var.flink_api_secret
  }

  lifecycle {
    prevent_destroy = true
  }
}
```

### Pattern 3: CC Flink Auto-Discovery of Schema Registry
**What:** CC Flink automatically maps CC environments to Flink catalogs, Kafka clusters to Flink databases, and topics with registered schemas to Flink tables
**When to use:** This is automatic in CC -- no configuration needed
**Key insight:** Unlike open-source Flink where you must define CREATE TABLE with connectors and format, CC Flink auto-discovers all topics with SR subjects. A topic named `corebanking.transactions.v1.account-transaction` with a registered Avro schema appears as a queryable table in Flink SQL immediately.

### Pattern 4: DLQ via Table Properties (CC-Specific)
**What:** Deserialization errors route to a DLQ table via table properties
**When to use:** For any source table that may encounter poison pills or schema mismatches
**Example:**
```sql
-- CC Flink DLQ pattern (NOT Apache Flink side outputs)
ALTER TABLE `corebanking`.`transactions`.`v1`.`account-transaction`
SET (
  'error-handling.mode' = 'log',
  'error-handling.log.target' = 'corebanking.transactions.v1.account-transaction.dlq'
);
```

### Pattern 5: Filter-and-Route via EXECUTE STATEMENT SET
**What:** Route records from one source to multiple output topics based on conditions
**When to use:** Fan-out patterns where different consumers need filtered subsets
**Example:**
```sql
EXECUTE STATEMENT SET
BEGIN
  INSERT INTO `fraud`.`detection`.`v1`.`high-risk-alert`
  SELECT * FROM `fraud`.`detection`.`v1`.`alert-signal`
  WHERE risk_score >= 90;

  INSERT INTO `fraud`.`detection`.`v1`.`low-risk-alert`
  SELECT * FROM `fraud`.`detection`.`v1`.`alert-signal`
  WHERE risk_score < 90;
END;
```

### Anti-Patterns to Avoid
- **Manual CREATE TABLE for existing topics:** CC Flink auto-discovers topics with SR subjects. Do not define CREATE TABLE with explicit connectors and formats for existing CC topics -- this creates duplicate resources.
- **Using Apache Flink side output API:** CC Flink SQL does not expose the Java DataStream side output API. Use `error-handling.mode` table properties for DLQ routing.
- **Decreasing max_cfu after creation:** CC compute pools do not support decreasing max_cfu. Start conservatively (5-10 CFU) and scale up as needed.
- **Multiple statements reading same source without STATEMENT SET:** When multiple INSERT INTO statements read from the same source, use EXECUTE STATEMENT SET to optimize shared intermediate results.
- **Running statements under user accounts:** Always use service accounts as principals for production Flink statements. User-bound statements create lifecycle coupling.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Flink compute provisioning | Custom scripts calling REST API | `confluent_flink_compute_pool` Terraform resource | IaC lifecycle management, drift detection, state tracking |
| Flink SQL deployment | Manual CLI execution or custom CI scripts | `confluent_flink_statement` Terraform resource | Versioned, reproducible, auditable deployments |
| Schema registration for Flink | Manual schema creation for Flink tables | CC auto-discovery from Schema Registry | CC Flink auto-maps topics + schemas to tables; manual registration is redundant |
| DLQ error routing | Custom error handling application | `error-handling.mode` + `error-handling.log.target` table properties | Built-in CC feature, auto-creates DLQ topic and schema |
| Metrics collection | Custom metrics scraper for Flink | CC Metrics API (`io.confluent.flink/*` namespace) | Same API used for Kafka/Connect metrics; consistent across all CC resources |
| Watermark strategy | Manual watermark definition per table | CC default watermark on `$rowtime` | CC automatically applies watermark strategy on all tables (180ms default out-of-orderness) |

**Key insight:** CC Flink is heavily opinionated and auto-configured compared to open-source Flink. Resist the urge to add manual configuration that CC already handles.

## Common Pitfalls

### Pitfall 1: Confusing CC Flink with Apache Flink
**What goes wrong:** Developers try to use Apache Flink Java API patterns (side outputs, DataStream API, custom connectors) in CC Flink SQL
**Why it happens:** Apache Flink documentation is much more prevalent; CC Flink is a managed subset with different capabilities
**How to avoid:** Reference CC Flink docs explicitly (`docs.confluent.io/cloud/current/flink/`), not Apache Flink docs. CC Flink supports only SQL/Table API, not DataStream API.
**Warning signs:** References to side outputs, ProcessFunction, DataStream, custom sources/sinks

### Pitfall 2: max_cfu Cannot Be Decreased
**What goes wrong:** Team provisions a large compute pool, then tries to reduce max_cfu for cost control
**Why it happens:** Intuition says resource limits should be adjustable in both directions
**How to avoid:** Start with conservative max_cfu (5-10 for dev/test, 10-20 for staging, appropriate value for production). Document that increase-only constraint in module variables.
**Warning signs:** Terraform plan shows destroy+recreate for compute pool when reducing max_cfu

### Pitfall 3: DLQ Table Permissions
**What goes wrong:** Flink statement fails because the principal cannot create the DLQ topic/schema
**Why it happens:** `error-handling.log.target` triggers auto-creation of a DLQ topic, which requires topic create + schema write permissions
**How to avoid:** Ensure the Flink service account principal has ResourceOwner or equivalent permissions that allow topic creation, OR pre-create the DLQ topic via the topic module
**Warning signs:** Flink job status shows FAILED with permission errors related to DLQ target

### Pitfall 4: Flink Statement Lifecycle vs Terraform Lifecycle
**What goes wrong:** `terraform destroy` drops a running Flink statement, causing data processing interruption
**Why it happens:** Default Terraform behavior is to destroy resources on removal
**How to avoid:** Always set `lifecycle { prevent_destroy = true }` on production `confluent_flink_statement` resources. Stop statements before compute pool changes.
**Warning signs:** Compute pools with running statements cannot be deleted

### Pitfall 5: Flink API Keys vs Kafka API Keys
**What goes wrong:** Using Kafka API keys for Flink REST API calls
**Why it happens:** Both are Confluent Cloud API keys but scoped differently
**How to avoid:** Create dedicated Flink API keys using `confluent_api_key` resource scoped to the Flink compute pool, OR use Cloud API keys for the Flink REST endpoint
**Warning signs:** 401/403 errors when submitting Flink statements

### Pitfall 6: Avro Enum Handling
**What goes wrong:** Flink cannot create or evolve enum types in Avro schemas
**Why it happens:** CC Flink treats Avro enums as STRING type, with limited read/write support but no creation capability
**How to avoid:** If schemas use Avro enums, accept that Flink will treat them as strings. Do not try to create new enum-typed columns via Flink DDL.
**Warning signs:** Type mismatch errors when Flink writes to topics with enum fields

### Pitfall 7: Temporal Join Primary Key Requirement
**What goes wrong:** Temporal JOIN (stream-table enrichment) fails with unclear error
**Why it happens:** Event-time temporal joins require the primary key to be part of the join condition equivalence
**How to avoid:** Ensure the dimension/lookup table has a PRIMARY KEY constraint and the join ON clause includes the primary key
**Warning signs:** Query validation errors mentioning primary key or temporal join conditions

## Code Examples

### Tumbling Window Aggregation (FLINK-04)
```sql
-- Source: Confluent CC Flink docs - aggregate-tumbling-window guide
-- FSI use case: 1-minute transaction volume aggregation per domain
INSERT INTO `corebanking`.`analytics`.`v1`.`txn-volume-1m`
SELECT
  window_start,
  window_end,
  COUNT(*) AS transaction_count,
  SUM(amount) AS total_amount,
  AVG(amount) AS avg_amount,
  MIN(amount) AS min_amount,
  MAX(amount) AS max_amount
FROM TUMBLE(
  TABLE `corebanking`.`transactions`.`v1`.`account-transaction`,
  DESCRIPTOR($rowtime),
  INTERVAL '1' MINUTE
)
GROUP BY window_start, window_end;
```

### Stream-Table Join Enrichment (FLINK-04)
```sql
-- Source: Confluent CC Flink docs - joins guide
-- FSI use case: Enrich transaction stream with customer data for fraud detection
INSERT INTO `fraud`.`enrichment`.`v1`.`enriched-transaction`
SELECT
  txn.transaction_id,
  txn.account_number,
  txn.amount,
  txn.transaction_type,
  cust.risk_rating,
  cust.kyc_status,
  cust.country_code
FROM `corebanking`.`transactions`.`v1`.`account-transaction` AS txn
JOIN `corebanking`.`customers`.`v1`.`customer-profile`
  FOR SYSTEM_TIME AS OF txn.$rowtime AS cust
ON txn.account_number = cust.account_number;
```

### Filter-and-Route (FLINK-04)
```sql
-- Source: Confluent CC Flink docs - statement-set guide
-- FSI use case: Route compliance screening results by match severity
EXECUTE STATEMENT SET
BEGIN
  INSERT INTO `compliance`.`screening`.`v1`.`high-match`
  SELECT * FROM `compliance`.`screening`.`v1`.`match-result`
  WHERE match_score >= 85;

  INSERT INTO `compliance`.`screening`.`v1`.`low-match`
  SELECT * FROM `compliance`.`screening`.`v1`.`match-result`
  WHERE match_score < 85;
END;
```

### DLQ Configuration (FLINK-07)
```sql
-- Source: Confluent CC Flink docs - error-handling table properties
-- Apply DLQ to a source table before starting a streaming query
ALTER TABLE `corebanking`.`transactions`.`v1`.`account-transaction`
SET (
  'error-handling.mode' = 'log',
  'error-handling.log.target' = 'corebanking.transactions.v1.account-transaction.dlq'
);
```

### Terraform Flink Module (FLINK-01)
```hcl
# modules/flink/main.tf - Compute pool provisioning
resource "confluent_flink_compute_pool" "pool" {
  display_name = var.compute_pool_name
  cloud        = var.cloud_provider
  region       = var.region
  max_cfu      = var.max_cfu

  environment {
    id = var.environment_id
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Flink SQL statement submission
resource "confluent_flink_statement" "statements" {
  for_each = var.flink_statements

  organization {
    id = var.organization_id
  }
  environment {
    id = var.environment_id
  }
  compute_pool {
    id = confluent_flink_compute_pool.pool.id
  }
  principal {
    id = var.flink_service_account_id
  }

  statement = each.value.sql

  properties = {
    "sql.current-catalog"  = var.environment_display_name
    "sql.current-database" = var.kafka_cluster_display_name
  }

  rest_endpoint = var.flink_rest_endpoint

  credentials {
    key    = var.flink_api_key
    secret = var.flink_api_secret
  }

  lifecycle {
    prevent_destroy = true
  }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual Flink SQL via CC Console or CLI | `confluent_flink_statement` Terraform resource | Provider ~v1.70+ (2024) | IaC-managed Flink jobs |
| Custom connector configs for SR integration | CC Flink auto-discovers SR subjects | GA launch | Zero-config schema integration |
| Apache Flink side outputs for DLQ | `error-handling.mode` table property | CC Flink GA | Declarative DLQ, no Java code needed |
| Fixed parallelism configuration | Autopilot auto-scaling | CC current | Auto-scales compute within max_cfu limit |
| Manual watermark definition per table | Default `$rowtime` watermark on all CC tables | CC current | Eliminates common misconfiguration |
| User account statement execution | Service account principal for statements | Provider v2.38+ | Separates identity from deployment |

**Deprecated/outdated:**
- `confluent_flink_compute_pool` cannot decrease `max_cfu` -- plan accordingly
- Apache Flink DataStream API concepts (side outputs, ProcessFunction) do not apply to CC Flink SQL
- Open-source Flink connector configurations (`connector = 'kafka'`, `format = 'avro-confluent'`) are not used in CC Flink -- auto-discovery replaces them

## Open Questions

1. **Exact Flink Metrics API metric names for observability dashboards**
   - What we know: `io.confluent.flink/num_records_in`, `io.confluent.flink/num_records_out`, `io.confluent.flink/pending_records` confirmed. CFU utilization metrics exist.
   - What's unclear: Full list of all available `io.confluent.flink/*` metrics, especially checkpoint duration and backpressure as individual exportable metrics (vs. only visible in CC Console)
   - Recommendation: During implementation, query `GET /v2/metrics/cloud/descriptors/metrics` with Metrics API credentials to enumerate all available Flink metrics. Update dashboard templates with actual metric names.

2. **Flink API key provisioning pattern**
   - What we know: Flink statements require credentials (API key/secret) scoped to the Flink REST endpoint
   - What's unclear: Whether these should be Cloud API keys or resource-scoped Flink API keys created via `confluent_api_key`
   - Recommendation: Use `confluent_api_key` resource with `managed_resource` block pointing to the Flink compute pool for proper RBAC scoping

3. **DLQ schema inheritance**
   - What we know: DLQ topic is auto-created when `error-handling.log.target` is set
   - What's unclear: What schema the DLQ topic uses (error envelope? raw bytes? source schema + error metadata?)
   - Recommendation: Test DLQ creation in dev and document the schema format. Pre-creating DLQ topics via the topic module gives governance control over naming and schema.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Terraform validate + custom bash smoke scripts |
| Config file | scenarios/cc-{cloud}/main.tf (per scenario) |
| Quick run command | `terraform validate` in scenario directory |
| Full suite command | `terraform plan` with real credentials (CI) |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| FLINK-01 | Compute pool + statement provisioning via Terraform | integration (terraform plan) | `cd scenarios/cc-aws && terraform init -backend=false && terraform validate` | Wave 0: flink.tf |
| FLINK-04 | SQL templates are valid Flink SQL syntax | unit (syntax validation) | `python3 ci/scripts/validate-flink-sql.py --sql-dir reference/flink-sql/` | Wave 0: validate-flink-sql.py |
| FLINK-05 | SR auto-discovery works (no manual CREATE TABLE for existing topics) | smoke (documentation) | Manual: verify SQL templates reference topics without CREATE TABLE connectors | N/A -- doc review |
| FLINK-06 | Flink metrics in dashboard templates | unit (JSON/YAML lint) | `python3 -c "import json; json.load(open('observability/grafana/dashboard-flink-jobs.json'))"` | Exists (stub) |
| FLINK-07 | DLQ table properties in SQL templates | unit (syntax presence) | `grep 'error-handling.mode' reference/flink-sql/dlq-pattern.sql` | Wave 0: dlq-pattern.sql |

### Sampling Rate
- **Per task commit:** `terraform validate` on changed scenario directories
- **Per wave merge:** `terraform plan` on all 3 scenario directories
- **Phase gate:** All scenarios validate, SQL templates parseable, dashboards valid JSON

### Wave 0 Gaps
- [ ] `modules/flink/main.tf` -- Flink compute pool + statement module
- [ ] `reference/flink-sql/*.sql` -- SQL template files
- [ ] `ci/scripts/validate-flink-sql.py` -- Optional: SQL syntax validation script
- [ ] `scenarios/cc-{aws,azure,gcp}/flink.tf` -- Flink resources per scenario

## Sources

### Primary (HIGH confidence)
- Confluent Terraform Provider docs - `confluent_flink_compute_pool` resource (GA)
- Confluent Terraform Provider docs - `confluent_flink_statement` resource (GA)
- Confluent CC Flink docs - aggregate-tumbling-window guide
- Confluent CC Flink docs - joins guide (temporal JOIN for enrichment)
- Confluent CC Flink docs - statement-set guide (EXECUTE STATEMENT SET)
- Confluent CC Flink docs - create-table reference (error-handling.mode, error-handling.log.target)
- Confluent CC Flink docs - comparison with Apache Flink (auto-discovery, auto-watermark, schema formats)
- Confluent CC Flink docs - serialization/data type mappings (Avro limitations, enum handling)

### Secondary (MEDIUM confidence)
- Confluent CC Flink docs - monitor-statements guide (Messages Behind, CFU consumption, statement states)
- Confluent CC Metrics API docs (io.confluent.flink/* metric namespace confirmed)
- Pulumi FlinkStatement docs (cross-verified attributes: stopped, properties_sensitive, statement_name)
- Confluent blog - Flink Actions, Terraform support, Multi-Cloud Availability

### Tertiary (LOW confidence)
- Exact complete list of `io.confluent.flink/*` Metrics API metrics (partial list confirmed, full enumeration requires API query)
- DLQ auto-created topic schema format (not found in docs, needs empirical verification)
- Flink API key scoping best practice (Cloud API key vs resource-scoped key -- multiple patterns seen in examples)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Terraform provider resources are GA, provider v2.65.0 already installed in project
- Architecture: HIGH - Patterns follow existing project conventions (modules/, scenarios/, observability/)
- Flink SQL patterns: HIGH - Documented in official Confluent CC Flink guides with working examples
- DLQ handling: MEDIUM - error-handling.mode confirmed, but DLQ schema format and permission model need verification
- Observability metrics: MEDIUM - Metric namespace confirmed, but complete metric list needs API enumeration
- Pitfalls: MEDIUM-HIGH - Combination of official docs and cross-verified community sources

**Research date:** 2026-03-26
**Valid until:** 2026-04-26 (30 days -- CC Flink and Terraform provider are stable/GA)

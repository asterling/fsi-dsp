# Flink SQL Reference Templates

Reference Flink SQL templates for common FSI stream processing patterns on Confluent Cloud. Copy, adapt, and submit via Terraform (`modules/flink`) or the Confluent Cloud console.

## Prerequisites

- Confluent Cloud Flink compute pool provisioned (see `modules/flink/`)
- Source and sink topics created with registered Avro schemas (see `modules/topic/`)
- Flink service account with appropriate RBAC permissions

## Schema Registry Auto-Discovery

CC Flink **auto-discovers** topics with registered Schema Registry subjects. Topics appear as queryable tables using the naming convention:

```
`{environment}`.`{cluster}`.`{topic_name_with_dots_as_separators}`
```

**Do NOT use `CREATE TABLE` with connector/format properties for existing CC topics.** This is an anti-pattern that creates duplicate resources. CC Flink handles schema mapping automatically.

## Templates

### Tumbling Window Aggregation

**File:** `tumbling-window-aggregation.sql`
**Pattern:** Continuous time-window aggregation over a stream
**FSI use case:** 1-minute transaction volume summary (count, sum, avg, min, max) for real-time dashboards and alerting
**Key SQL:** `TUMBLE(TABLE source, DESCRIPTOR($rowtime), INTERVAL '1' MINUTE)`

### Stream-Table Join Enrichment

**File:** `stream-table-join-enrichment.sql`
**Pattern:** Enrich an unbounded stream with the latest version of a compacted lookup table
**FSI use case:** Enrich transaction stream with customer risk rating and KYC status for fraud detection
**Key SQL:** `JOIN dimension FOR SYSTEM_TIME AS OF stream.$rowtime`

**Important:** The lookup table must be a compacted topic (cleanup.policy=compact) with a primary key. The JOIN ON clause must include the primary key.

### Filter-and-Route

**File:** `filter-and-route.sql`
**Pattern:** Route records from one source to multiple output topics based on conditions
**FSI use case:** Split compliance screening results into high-match (immediate review) and low-match (batch review) queues
**Key SQL:** `EXECUTE STATEMENT SET BEGIN ... END;`

**Important:** Always use `EXECUTE STATEMENT SET` when multiple INSERT INTO statements read from the same source. This optimizes shared intermediate results.

### Dead Letter Queue (DLQ)

**File:** `dlq-pattern.sql`
**Pattern:** Route deserialization failures to a DLQ topic instead of failing the job
**FSI use case:** Poison pill handling in production transaction streams
**Key SQL:** `ALTER TABLE ... SET ('error-handling.mode' = 'log', 'error-handling.log.target' = '...')`

**CC-specific:** This uses CC Flink's `error-handling.mode` table property -- NOT Apache Flink's side output API. Only deserialization errors are captured; UDF/processing errors are not.

**Recommendation:** Pre-create DLQ topics via `modules/topic/` for naming governance and SLA tier control, rather than relying on auto-creation.

## Submitting via Terraform

Each SQL template can be submitted as a managed Flink statement:

```hcl
module "flink" {
  source = "../../modules/flink"
  # ... compute pool config ...

  flink_statements = {
    "txn-volume-1m" = {
      sql = file("../../reference/flink-sql/tumbling-window-aggregation.sql")
    }
  }
}
```

## Common Pitfalls

1. **Do not use Apache Flink DataStream API patterns** -- CC Flink supports SQL/Table API only
2. **max_cfu cannot be decreased** -- Start conservative (5-10 CFU) and scale up
3. **DLQ requires topic create permissions** -- Flink SA needs permissions for auto-created DLQ topics
4. **Temporal joins require primary key** -- Lookup table must be compacted with PK in join condition
5. **Avro enums are treated as STRING** -- Flink cannot create or evolve enum types
6. **Use service accounts, not user accounts** -- For production statement principals

## Further Reading

- [Confluent CC Flink SQL docs](https://docs.confluent.io/cloud/current/flink/)
- `modules/flink/` -- Terraform module for compute pool provisioning
- `observability/grafana/dashboard-flink-jobs.json` -- Flink monitoring dashboard
- `docs/adr/` -- Architecture Decision Records

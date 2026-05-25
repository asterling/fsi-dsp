# ADR-011: Lakehouse Integration Patterns — Databricks & Snowflake

**Status:** Accepted
**Date:** 2026-05-25
**Author:** Platform C4E

## Context

FSI teams adopting the platform need to push streaming data into downstream
lakehouses — Databricks (Delta Lake / Unity Catalog) and Snowflake — for
analytics, ML feature pipelines, and regulatory reporting. The platform
previously shipped zero opinionated assets for either target. Each team was
left to invent its own connector configuration, secret management, schema
mapping, and DLQ handling, producing five different patterns across five
business units.

Four mechanisms exist in 2026 to bridge Kafka and a lakehouse:

| Code | Path | Mechanism | Operational model |
|---|---|---|---|
| **DB-A** | Confluent Tableflow → Databricks | Topic materialized to Delta/Iceberg in Tableflow-managed storage; Unity Catalog reads the table | Zero-copy from Kafka's perspective; CC-only feature |
| **DB-C** | Databricks Delta Lake Sink Connector | Kafka Connect connector pushes records into a Delta table | Push, managed (CC) or self-managed (CP/CFK) |
| **SF-A** | Snowpipe Streaming Kafka Connector | Snowflake-supplied connector using `SNOWPIPE_STREAMING` ingestion method | Push, sub-second latency, managed (CC) or self-managed (CP/CFK) |
| **SF-B** | Tableflow → Iceberg + Open Data Catalog → Snowflake | Topic materialized to Iceberg in Tableflow storage; Snowflake reads via external table or Horizon catalog | Zero-copy from Kafka's perspective; CC-only feature |

Two cross-cutting constraints shape this decision:

1. **Tableflow is a Confluent Cloud feature.** No on-prem CP, CFK, or LinuxONE
   variant of Tableflow ships today. DB-A and SF-B are therefore valid only
   when the source cluster is CC.
2. **ADR-004 (Accepted 2026-03-21) chose self-managed Connect on-prem.** The
   rationale — latency-sensitive JDBC, existing Connect operations team, data
   contract handling — still applies to most enterprise workloads. ADR-011
   does not reverse ADR-004. It carves out a narrow exception for CC-managed
   lakehouse sinks where the source cluster is already in CC and the target
   is a SaaS lakehouse: in that case there is no on-prem element in the
   pipeline, and a managed connector eliminates worker operations entirely.

## Decision

**The platform ships first-class assets for all four mechanisms, gated by
deployment model.**

| Path | CC | CP on RHEL | CFK on OCP | CP on RHEL on L1 | CFK on OCP on L1 |
|---|---|---|---|---|---|
| DB-A (Tableflow → Databricks) | ✅ supported | ❌ → use DB-C | ❌ → use DB-C | ❌ → use DB-C | ❌ → use DB-C |
| DB-C (Delta Sink connector) | ✅ managed | ✅ self-managed | ✅ self-managed | ✅ self-managed | ✅ self-managed |
| SF-A (Snowpipe Streaming) | ✅ managed | ✅ self-managed | ✅ self-managed | ✅ self-managed | ✅ self-managed |
| SF-B (Tableflow → Iceberg → Snowflake) | ✅ supported | ❌ → use SF-A | ❌ → use SF-A | ❌ → use SF-A | ❌ → use SF-A |

A new reusable Terraform module — `modules/lakehouse_sink/` — emits a fully
governed CC-managed connector (DB-C or SF-A) in a single call, mirroring the
philosophy of `modules/topic/`. A second module — `modules/tableflow/` —
enables Tableflow plus catalog integration on an existing topic (DB-A / SF-B).

Self-managed paths reuse the existing `cp_connect` Ansible role and the CFK
`Connector` CR convention from `scenarios/cfk-openshift/mm2/`. Two new roles
— `cp_databricks_sink` and `cp_snowflake_sink` — wrap `cp_connect` with
connector-specific defaults and validation.

For CFK on OCP on LinuxONE a new Kustomize layer `06-lakehouse-sinks` mounts
into the accelerator alongside the existing five hardening layers.

### Default selection guidance (when a team asks "which one")

1. **Source cluster in CC + target is Databricks/Snowflake SaaS** → start
   with Tableflow (DB-A / SF-B). Lowest operational burden, no Connect
   workers, materialized table is the contract.
2. **Source cluster in CC + need sub-100ms latency to Snowflake** → SF-A
   managed (Snowpipe Streaming). Tableflow's materialization cadence is
   minutes, not milliseconds.
3. **Source cluster on-prem (CP / CFK / LinuxONE)** → DB-C or SF-A
   self-managed. Same `${vault:...}` secret pattern, same `cp_connect` role,
   same DLQ defaults as JDBC sink.
4. **Source cluster on-prem + Databricks is the target** → DB-C is the only
   option. Tableflow is unavailable.

## Consequences

**Easier:**
- A topic in CC can be reflected into Databricks UC or Snowflake with a
  single Terraform module call — no Connect cluster, no JAR install, no
  worker tuning, no DLQ topic to provision.
- On-prem teams get the same connector JSON template they already use for
  JDBC, with vault placeholders and DLQ wired in.
- LinuxONE customers get a Kustomize layer that mirrors `04-audit`
  structurally — no new operational pattern to learn.
- Schema evolution is governed by Schema Registry compatibility mode in
  every path; lakehouse table schema follows the topic schema, not the
  reverse.

**Harder:**
- Tableflow's CC-only constraint means a multi-cluster FSI organization
  cannot pick one pattern and apply it everywhere. Documentation explicitly
  calls out the fallback so teams do not waste time looking for a phantom
  on-prem Tableflow.
- This is the first `confluent_connector` Terraform resource type in the
  repo. Operators need to understand which connector class strings map to
  which DB-C / SF-A path; the `modules/lakehouse_sink/` `sink_type`
  variable enumerates them.
- Secrets for Databricks PAT and Snowflake key-pair auth must be available
  to the connector at runtime. The vault pattern is reused, but operators
  must populate two new Vault paths (`secret/fsi/databricks#token`,
  `secret/fsi/snowflake#private_key`).
- DLQ topic explosion: every lakehouse sink gets a per-sink DLQ. With four
  paths × N source topics this can multiply quickly. The module wires a
  single DLQ per sink instance, not per source topic, to keep the count
  bounded.

**Neutral but worth noting:**
- ADR-004 remains in effect for non-lakehouse sinks (JDBC, IBM MQ source,
  HTTP, etc.). ADR-011 is a scoped exception, not a reversal.
- Tableflow storage cost is borne by the CC account, not the platform. The
  `modules/tableflow/` module's `storage_format` variable defaults to
  `ICEBERG` because Iceberg supports both Databricks (via Delta UniForm) and
  Snowflake (via Horizon / external tables); pure `DELTA` is available when
  the only target is Databricks and Delta-native features (e.g. Delta
  Sharing, Liquid Clustering) are required.

## Cross-References

- ADR-004 — On-prem Connect (self-managed) decision; ADR-011 is a scoped
  exception, not a reversal
- ADR-001 — Avro over Protobuf (lakehouse sinks reuse the AvroConverter
  pattern, never JsonConverter for governed topics)
- ADR-002 — Compatibility by tier (lakehouse table schema follows the topic
  schema's compatibility mode)
- `docs/databricks-integration-guide.md` — operator-facing guide for DB-A
  and DB-C
- `docs/snowflake-integration-guide.md` — operator-facing guide for SF-A
  and SF-B
- `docs/tableflow-guide.md` — CC-only feature, availability matrix,
  fallback paths

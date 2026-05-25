-- =============================================================================
-- FSI Kafka Platform -- CockroachDB Native Changefeed Examples
-- =============================================================================
-- Path A from docs/cockroachdb-integration-guide.md: CRDB emits CDC events
-- directly to Kafka via SQL DDL. No Kafka Connect, no JAR install, no DLQ
-- provisioned by the platform. The CRDB DBA owns the lifecycle.
--
-- Run as a CRDB user with the CHANGEFEED privilege (CRDB 23.1+); earlier
-- versions require admin. Requires CRDB Enterprise licence.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Preflight: confirm Enterprise licence and rangefeed are enabled
-- -----------------------------------------------------------------------------
SHOW CLUSTER SETTING enterprise.license;
-- Expected: a non-empty license string. If empty, native changefeed is unavailable.

SHOW CLUSTER SETTING kv.rangefeed.enabled;
-- Expected: 'true'. If 'false', enable via:
--   SET CLUSTER SETTING kv.rangefeed.enabled = true;

-- -----------------------------------------------------------------------------
-- Grant minimal privileges (CRDB 23.1+)
-- -----------------------------------------------------------------------------
-- Create a dedicated changefeed role rather than running as admin:
CREATE ROLE fsi_changefeed WITH LOGIN PASSWORD '<rotated-vault-managed-password>';
GRANT SYSTEM CHANGEFEED TO fsi_changefeed;
GRANT SELECT ON TABLE corebanking.account_transaction TO fsi_changefeed;
GRANT SELECT ON TABLE corebanking.member_profile TO fsi_changefeed;

-- -----------------------------------------------------------------------------
-- Example 1: SLA=critical, single table, full FSI options
-- -----------------------------------------------------------------------------
-- - envelope=wrapped emits {before, after, updated, resolved} for every change.
-- - format=avro registers schemas with Confluent Schema Registry.
-- - resolved='10s' emits watermark timestamps every 10 seconds (downstream
--   consumers use these to determine "no event before time T was missed").
-- - updated adds the MVCC timestamp to every row, enabling exactly-once
--   downstream processing via row-version dedup.
-- - mvcc_timestamp adds the version-as-of timestamp to the envelope.
CREATE CHANGEFEED FOR TABLE corebanking.account_transaction
INTO 'kafka://kafka-east.fsi.internal:9093?topic_name=corebanking.transactions.v1.account-transaction'
WITH
  envelope = 'wrapped',
  format = 'avro',
  confluent_schema_registry = 'https://schema.fsi.internal',
  updated,
  resolved = '10s',
  mvcc_timestamp,
  kafka_sink_config = '{"Flush": {"MaxMessages": 1000, "Frequency": "1s"}}';

-- -----------------------------------------------------------------------------
-- Example 2: SLA=standard, multiple tables, resolved cadence relaxed to 60s
-- -----------------------------------------------------------------------------
CREATE CHANGEFEED FOR TABLE corebanking.member_profile, corebanking.account_balance
INTO 'kafka://kafka-east.fsi.internal:9093'
WITH
  envelope = 'wrapped',
  format = 'avro',
  confluent_schema_registry = 'https://schema.fsi.internal',
  topic_in_value,
  updated,
  resolved = '60s',
  full_table_name;

-- -----------------------------------------------------------------------------
-- Example 3: mTLS authentication to Kafka brokers
-- -----------------------------------------------------------------------------
-- The kafka_sink_config Sasl/Tls options carry the connection parameters.
-- Certs must be present on every CRDB node at the path referenced.
CREATE CHANGEFEED FOR TABLE compliance.screening_result
INTO 'kafka://kafka-east.fsi.internal:9093?topic_name=compliance.screening.v1.match-result&tls_enabled=true&ca_cert=/var/lib/cockroach/certs/kafka-ca.crt&client_cert=/var/lib/cockroach/certs/kafka-client.crt&client_key=/var/lib/cockroach/certs/kafka-client.key'
WITH
  envelope = 'wrapped',
  format = 'avro',
  confluent_schema_registry = 'https://schema.fsi.internal',
  resolved = '10s';

-- -----------------------------------------------------------------------------
-- Example 4: SLA=compliance, with cursor for replay from a known LSN-equivalent
-- -----------------------------------------------------------------------------
-- cursor accepts a cluster_logical_timestamp (HLC). Used to replay from a
-- precise point in time, e.g. for regulatory audit reconstruction.
CREATE CHANGEFEED FOR TABLE compliance.audit_event
INTO 'kafka://kafka-east.fsi.internal:9093?topic_name=compliance.audit.v1.event'
WITH
  envelope = 'wrapped',
  format = 'avro',
  confluent_schema_registry = 'https://schema.fsi.internal',
  cursor = '1716595200000000000.0',   -- replace with replay-point HLC
  resolved = '5s',
  updated,
  diff;

-- -----------------------------------------------------------------------------
-- DISCOURAGED: webhook sink (no audit trail)
-- -----------------------------------------------------------------------------
-- CRDB also supports webhook sinks. Avoid in FSI: the webhook auth lives
-- in the URL and there is no per-event audit trail of which endpoint
-- received what. Use the Kafka sink and let Kafka audit log do the work.
--
-- DO NOT USE for FSI workloads:
--   CREATE CHANGEFEED FOR TABLE x INTO 'webhook-https://...'
--     WITH webhook_auth_header='Authorization: Bearer ...';

-- -----------------------------------------------------------------------------
-- Lifecycle: list, pause, resume, cancel
-- -----------------------------------------------------------------------------
SHOW CHANGEFEED JOBS;
-- Returns job_id, status, full_uri, statement, topics, error.

-- PAUSE during maintenance window (slot is held; rangefeed keeps producing)
PAUSE JOB <job_id>;

-- RESUME after maintenance
RESUME JOB <job_id>;

-- CANCEL irrevocably; offsets in Kafka are NOT cleaned up
CANCEL JOB <job_id>;

-- -----------------------------------------------------------------------------
-- Verification
-- -----------------------------------------------------------------------------
-- 1. Run a test INSERT against the source table:
INSERT INTO corebanking.account_transaction (transaction_id, account_number, amount)
VALUES ('test-txn-001', 'acct-123', 100.00);

-- 2. Confirm the event in Kafka (using the confluent CLI as the changefeed user):
--    confluent kafka topic consume corebanking.transactions.v1.account-transaction \
--      --from-beginning --max-messages 1

-- 3. Confirm the Avro schema is registered:
--    curl https://schema.fsi.internal/subjects/corebanking.transactions.v1.account-transaction-value/versions/latest

-- 4. Confirm resolved timestamps are arriving (one every 10s for critical tier):
--    confluent kafka topic consume corebanking.transactions.v1.account-transaction \
--      --from-beginning --print-key | grep '_resolved'

-- -----------------------------------------------------------------------------
-- Observability handoff
-- -----------------------------------------------------------------------------
-- Native changefeed metrics live in the CRDB Prometheus endpoint, NOT in
-- the Kafka Connect REST API. Scrape CRDB:8080 (or :26258 for v23.2+).
-- See observability/grafana/dashboard-cockroachdb-changefeed.json for the
-- panel set: changefeed.emitted_messages, changefeed.emit_latency_p95,
-- changefeed.error_retries, changefeed.checkpoint_progress.

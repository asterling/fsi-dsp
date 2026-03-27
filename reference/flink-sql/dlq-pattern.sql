-- =============================================================================
-- Flink SQL: Dead Letter Queue (DLQ) Pattern
-- =============================================================================
-- FSI use case: Route deserialization failures to a DLQ topic instead of
-- failing the entire Flink job. Essential for poison pill handling in
-- production streams.
--
-- CC Flink DLQ uses table properties (FLINK-07) -- NOT Apache Flink side
-- outputs. This is a CC-specific feature.
--
-- How it works:
--   1. ALTER TABLE sets error-handling.mode = 'log' on the source table
--   2. error-handling.log.target specifies the DLQ topic name
--   3. CC auto-creates the DLQ topic and schema if they don't exist
--   4. Only deserialization errors are routed -- UDF/processing errors
--      are NOT captured by this mechanism
--
-- DLQ permissions (Pitfall 3 from 06-RESEARCH.md):
--   The Flink service account principal must have topic create + schema
--   write permissions for auto-creation. Alternatively, pre-create the
--   DLQ topic via the topic module for governance control.
--
-- Recommended: Pre-create DLQ topics via modules/topic for naming
-- governance and SLA tier assignment:
--   module "account_txn_dlq" {
--     source   = "../../modules/topic"
--     domain   = "corebanking"
--     application = "transactions"
--     schema_version = "v1"
--     entity   = "account-transaction-dlq"
--     sla_tier = "standard"
--     ...
--   }
--
-- Adapt: Change table reference and DLQ topic name to your domain
-- =============================================================================

-- Step 1: Enable DLQ on the source table
ALTER TABLE `corebanking`.`transactions`.`v1`.`account-transaction`
SET (
  'error-handling.mode' = 'log',
  'error-handling.log.target' = 'corebanking.transactions.v1.account-transaction.dlq'
);

-- Step 2: After DLQ is configured, start your streaming query.
-- Deserialization errors on the source table will be routed to the DLQ
-- topic instead of failing the job.
--
-- Example: Run the tumbling window aggregation from tumbling-window-aggregation.sql
-- INSERT INTO `corebanking`.`analytics`.`v1`.`txn-volume-1m`
-- SELECT ... FROM TUMBLE(TABLE `corebanking`.`transactions`.`v1`.`account-transaction`, ...)
-- GROUP BY window_start, window_end;

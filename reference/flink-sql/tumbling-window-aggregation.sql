-- =============================================================================
-- Flink SQL: Tumbling Window Aggregation
-- =============================================================================
-- FSI use case: 1-minute transaction volume aggregation by domain.
-- Produces a continuous summary of transaction counts, totals, and averages
-- into an output topic for dashboards and alerting.
--
-- CC Flink auto-discovers topics with SR subjects as tables (FLINK-05).
-- No CREATE TABLE needed for existing CC topics.
--
-- Prerequisites:
--   1. Source topic exists with registered Avro schema
--   2. Output topic exists (or use auto-create if permitted)
--   3. Flink compute pool provisioned via modules/flink
--
-- Adapt: Change table references to your {domain}.{app}.{version}.{entity}
-- =============================================================================

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

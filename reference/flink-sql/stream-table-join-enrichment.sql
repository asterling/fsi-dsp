-- =============================================================================
-- Flink SQL: Stream-Table Join Enrichment
-- =============================================================================
-- FSI use case: Enrich real-time transaction stream with customer profile data
-- for fraud detection. Joins the unbounded transaction stream against the
-- latest snapshot of the customer-profile compacted topic.
--
-- CC Flink auto-discovers topics with SR subjects as tables (FLINK-05).
--
-- IMPORTANT: Temporal joins (FOR SYSTEM_TIME AS OF) require:
--   1. The dimension/lookup table has a PRIMARY KEY (compacted topic)
--   2. The JOIN ON clause includes the primary key
--   See Pitfall 7 in 06-RESEARCH.md.
--
-- Prerequisites:
--   1. Transaction stream topic with registered Avro schema
--   2. Customer profile topic (cleanup.policy=compact) with registered schema
--   3. Output enriched-transaction topic with registered schema
--
-- Adapt: Change table references and field names to your domain
-- =============================================================================

INSERT INTO `fraud`.`enrichment`.`v1`.`enriched-transaction`
SELECT
  txn.transaction_id,
  txn.account_number,
  txn.amount,
  txn.transaction_type,
  txn.`timestamp`,
  cust.risk_rating,
  cust.kyc_status,
  cust.country_code
FROM `corebanking`.`transactions`.`v1`.`account-transaction` AS txn
JOIN `corebanking`.`customers`.`v1`.`customer-profile`
  FOR SYSTEM_TIME AS OF txn.$rowtime AS cust
ON txn.account_number = cust.account_number;

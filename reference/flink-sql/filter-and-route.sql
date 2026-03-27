-- =============================================================================
-- Flink SQL: Filter-and-Route (EXECUTE STATEMENT SET)
-- =============================================================================
-- FSI use case: Route compliance screening results to separate topics based
-- on match severity. High-match records go to immediate review queue;
-- low-match records go to batch review queue.
--
-- EXECUTE STATEMENT SET is required when multiple INSERT INTO statements
-- read from the same source table -- it optimizes shared intermediate
-- results (Anti-pattern from 06-RESEARCH.md).
--
-- CC Flink auto-discovers topics with SR subjects as tables (FLINK-05).
--
-- Prerequisites:
--   1. Source topic with registered Avro schema containing a score/severity field
--   2. Output topics for each route with registered schemas
--   3. Schemas for output topics should be subsets or extensions of source schema
--
-- Adapt: Change table references, field names, and filter conditions
-- =============================================================================

EXECUTE STATEMENT SET
BEGIN
  -- High-severity matches: immediate investigation required
  INSERT INTO `compliance`.`screening`.`v1`.`high-match`
  SELECT *
  FROM `compliance`.`screening`.`v1`.`match-result`
  WHERE match_score >= 85;

  -- Low-severity matches: batch review queue
  INSERT INTO `compliance`.`screening`.`v1`.`low-match`
  SELECT *
  FROM `compliance`.`screening`.`v1`.`match-result`
  WHERE match_score < 85;
END;

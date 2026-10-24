-- Aggregates only (no uid, name or email): rows end up in the built site.
-- An empty table still yields one all-NULL row: Evidence writes an invalid
-- Parquet file for a source with no rows, and the pages skip NULL keys.
SELECT m.*
FROM (SELECT 1 AS one)
LEFT JOIN simsplit_metrics.metrics_operations AS m ON TRUE

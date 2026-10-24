-- Metric: operations (use cases) per day — runs, failure rate and median duration.
SELECT
    event_date AS day,
    event_name AS operation,
    COUNT(*) AS runs,
    COUNTIF(result != 'success') AS failures,
    SAFE_DIVIDE(COUNTIF(result != 'success'), COUNT(*)) AS failure_rate,
    APPROX_QUANTILES(duration_ms, 2)[OFFSET(1)] AS median_duration_ms
FROM {{ ref("fct_usage_events") }}
WHERE event_kind = 'op'
GROUP BY day, operation

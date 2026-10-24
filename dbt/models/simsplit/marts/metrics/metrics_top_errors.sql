-- Metric: error types ranked by how often they happen, with when they were first and last seen.
SELECT
    error_type,
    platform,
    shown_to_user,
    COUNT(*) AS reports,
    SUM(occurrences) AS occurrences,
    COUNT(DISTINCT report_id) AS installs,
    MIN(received_at) AS first_seen,
    MAX(received_at) AS last_seen
FROM {{ ref("fct_error_reports") }}
GROUP BY error_type, platform, shown_to_user

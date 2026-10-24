-- Metric: how often each screen and action is used, per day.
SELECT
    event_date AS day,
    event_kind,
    event_name,
    COUNT(*) AS events,
    COUNT(DISTINCT uid) AS users
FROM {{ ref("fct_usage_events") }}
GROUP BY day, event_kind, event_name

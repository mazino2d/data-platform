-- Metric: sessions per day and platform — count, median length and events per session.
WITH
sessions AS (
    SELECT
        session_id,
        platform,
        MIN(event_date) AS day,
        COUNT(*) AS events,
        TIMESTAMP_DIFF(MAX(received_at), MIN(received_at), SECOND) AS length_seconds
    FROM {{ ref("fct_usage_events") }}
    GROUP BY session_id, platform
)

SELECT
    day,
    platform,
    COUNT(*) AS sessions,
    APPROX_QUANTILES(length_seconds, 2)[OFFSET(1)] AS median_session_seconds,
    AVG(events) AS events_per_session
FROM sessions
GROUP BY day, platform

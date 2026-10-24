-- Metric: errors per 100 sessions by day, platform and app version. Error
-- reports and usage events share the app's session ID, so sessions with no
-- signed-in usage (the sign-in screen) count from their error reports.
WITH
errors AS (
    SELECT
        report_date AS day,
        platform,
        app_version,
        SUM(occurrences) AS errors,
        COUNT(DISTINCT session_id) AS error_sessions
    FROM {{ ref("fct_error_reports") }}
    GROUP BY day, platform, app_version
),

usage_sessions AS (
    SELECT
        event_date AS day,
        platform,
        app_version,
        COUNT(DISTINCT session_id) AS sessions
    FROM {{ ref("fct_usage_events") }}
    GROUP BY day, platform, app_version
)

SELECT
    COALESCE(e.day, s.day) AS day,
    COALESCE(e.platform, s.platform) AS platform,
    COALESCE(e.app_version, s.app_version) AS app_version,
    COALESCE(e.errors, 0) AS errors,
    GREATEST(COALESCE(s.sessions, 0), COALESCE(e.error_sessions, 0)) AS sessions,
    SAFE_DIVIDE(
        100 * COALESCE(e.errors, 0),
        GREATEST(COALESCE(s.sessions, 0), COALESCE(e.error_sessions, 0))
    ) AS errors_per_100_sessions
FROM errors AS e
FULL OUTER JOIN usage_sessions AS s
    ON e.day = s.day AND e.platform = s.platform AND e.app_version = s.app_version

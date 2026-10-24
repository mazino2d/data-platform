-- Fact: error_reports — one row per anonymous error report (no account).
SELECT
    report_id,
    session_id,
    error_time,
    received_at,
    platform,
    os,
    app_version,
    language,
    signed_in,
    online,
    shown_to_user,
    error_type,
    message,
    stack,
    occurrences,
    breadcrumbs,
    DATE(received_at) AS report_date
FROM {{ ref("stg_error_reports") }}

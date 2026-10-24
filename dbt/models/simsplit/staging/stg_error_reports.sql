-- Staging: error_reports — anonymous error reports (sim-split R-4 AC1-AC5):
-- no account, only the install's report ID and a random session ID.
SELECT
    report_id,
    session_id,
    client_time AS error_time,
    received_at,
    platform,
    os,
    app_version,
    language,
    signed_in,
    online,
    message,
    stack,
    count AS occurrences,
    breadcrumbs,
    STARTS_WITH(error_type, 'shown:') AS shown_to_user,
    REGEXP_REPLACE(error_type, r'^shown:', '') AS error_type
FROM {{ source("simsplit_telemetry", "error_reports") }}

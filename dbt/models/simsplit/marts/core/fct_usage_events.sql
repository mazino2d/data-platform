-- Fact: usage_events — one row per tracked action of a signed-in account.
-- Kept indefinitely; uid stays after the account is deleted, with no name or
-- email behind it (sim-split R-4 AC11).
SELECT
    uid,
    session_id,
    event_time,
    received_at,
    event_kind,
    event_name,
    screen,
    result,
    duration_ms,
    platform,
    app_version,
    language,
    online,
    DATE(received_at) AS event_date
FROM {{ ref("stg_usage_events") }}

-- Staging: usage_events — every screen, tap, form, dialog, gesture and
-- operation of signed-in accounts (sim-split R-4 AC8). event_time is the
-- device clock; received_at the endpoint's.
SELECT
    uid,
    session_id,
    client_time AS event_time,
    received_at,
    kind AS event_kind,
    name AS event_name,
    screen,
    result,
    duration_ms,
    platform,
    app_version,
    language,
    online
FROM {{ source("simsplit_telemetry", "usage_events") }}

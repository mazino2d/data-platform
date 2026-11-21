-- Staging: crm_sends — one row per push the crm service tried to send
-- (sim-split R-9 AC24). message_id embeds group IDs, so it stays in staging:
-- later layers carry only its hash.
SELECT
    message_id,
    sent_at,
    source,
    source_id,
    category,
    uid,
    platform,
    locale,
    result
FROM {{ source("simsplit_telemetry", "crm_sends") }}

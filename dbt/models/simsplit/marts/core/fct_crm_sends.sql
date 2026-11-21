-- Fact: crm_sends — one row per push the crm service tried to send, kept
-- indefinitely like the other telemetry facts. message_id embeds group IDs,
-- so only its hash is kept, as the row's key.
SELECT
    sent_at,
    source,
    source_id,
    category,
    uid,
    platform,
    locale,
    result,
    TO_HEX(SHA256(message_id)) AS send_id,
    DATE(sent_at) AS send_date
FROM {{ ref("stg_crm_sends") }}

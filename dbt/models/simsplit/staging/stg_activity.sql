-- Staging: activity — the audit history of every change in a group.
SELECT
    doc_id AS activity_id,
    group_id,
    actor_uid,
    action,
    entity_type,
    entity_id,
    synced_at,
    before AS before_json,
    after AS after_json,
    TIMESTAMP_MILLIS(client_time) AS client_time
FROM {{ source("simsplit", "activity") }}

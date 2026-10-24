-- Staging: members — the people of each group; linked_uid is set once an account claims one.
SELECT
    doc_id AS member_id,
    group_id,
    name AS member_name,
    emoji,
    linked_uid,
    created_by,
    updated_by,
    updated_at,
    TIMESTAMP_MILLIS(created_at) AS created_at,
    COALESCE(deleted, FALSE) AS is_deleted
FROM {{ source("simsplit", "members") }}

-- Staging: groups — current state of each group (soft deletes kept).
SELECT
    doc_id AS group_id,
    name AS group_name,
    emoji,
    currency_code,
    is_archived,
    owner_uid,
    created_by,
    updated_by,
    updated_at,
    ARRAY_LENGTH(JSON_QUERY_ARRAY(member_uids)) AS account_count,
    TIMESTAMP_MILLIS(created_at) AS created_at,
    COALESCE(deleted, FALSE) AS is_deleted
FROM {{ source("simsplit", "groups") }}

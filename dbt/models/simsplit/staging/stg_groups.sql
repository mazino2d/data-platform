-- Staging: groups — current state of each group (soft deletes kept).
SELECT
    doc_id AS group_id,
    name AS group_name,
    emoji,
    currency_code,
    is_archived,
    settlement_hub_member_id,
    owner_uid,
    created_by,
    updated_by,
    updated_at,
    ARRAY_LENGTH(JSON_QUERY_ARRAY(member_uids)) AS account_count,
    TIMESTAMP_MILLIS(created_at) AS created_at,
    COALESCE(deleted, FALSE) AS is_deleted,
    -- Groups from before sim-split R-7 have no mode: fewest transfers.
    COALESCE(settlement_mode, 'simplified') AS settlement_mode
FROM {{ source("simsplit", "groups") }}

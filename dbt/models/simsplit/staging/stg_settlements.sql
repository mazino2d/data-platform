-- Staging: settlements — payments between members. Amounts are integer cents.
SELECT
    doc_id AS settlement_id,
    group_id,
    from_member_id,
    to_member_id,
    amount_cents,
    currency_code,
    note,
    created_by,
    updated_by,
    updated_at,
    TIMESTAMP_MILLIS(settled_at) AS settled_at,
    TIMESTAMP_MILLIS(created_at) AS created_at,
    COALESCE(deleted, FALSE) AS is_deleted
FROM {{ source("simsplit", "settlements") }}

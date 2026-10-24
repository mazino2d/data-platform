-- Fact: settlements — one row per settlement (current state). Amounts are integer cents.
SELECT
    settlement_id,
    group_id,
    from_member_id,
    to_member_id,
    amount_cents,
    currency_code,
    settled_at,
    created_at,
    created_by,
    is_deleted
FROM {{ ref("stg_settlements") }}

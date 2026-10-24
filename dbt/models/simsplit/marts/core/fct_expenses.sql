-- Fact: expenses — one row per expense (current state), with the account
-- that paid when its member is claimed. Amounts are integer cents.
SELECT
    e.expense_id,
    e.group_id,
    e.paid_by_member_id,
    m.linked_uid AS payer_uid,
    e.amount_cents,
    e.currency_code,
    e.category,
    e.split_type,
    e.expense_date,
    e.created_at,
    e.created_by,
    e.edited_at,
    e.is_deleted
FROM {{ ref("stg_expenses") }} AS e
LEFT JOIN {{ ref("stg_members") }} AS m ON e.paid_by_member_id = m.member_id

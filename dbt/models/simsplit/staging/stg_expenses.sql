-- Staging: expenses — current state of each expense. Amounts are integer cents.
SELECT
    doc_id AS expense_id,
    group_id,
    title,
    amount_cents,
    currency_code,
    paid_by_member_id,
    split_type,
    category,
    note,
    created_by,
    updated_by,
    updated_at,
    TIMESTAMP_MILLIS(expense_date) AS expense_date,
    TIMESTAMP_MILLIS(created_at) AS created_at,
    TIMESTAMP_MILLIS(edited_at) AS edited_at,
    COALESCE(deleted, FALSE) AS is_deleted
FROM {{ source("simsplit", "expenses") }}

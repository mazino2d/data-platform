-- Staging: expense_splits — each member's share of an expense, unnested from
-- the JSON list Firestore embeds in the expense.
SELECT
    e.doc_id AS expense_id,
    e.group_id,
    JSON_VALUE(split, '$.id') AS split_id,
    JSON_VALUE(split, '$.memberId') AS member_id,
    SAFE_CAST(JSON_VALUE(split, '$.value') AS NUMERIC) AS split_value,
    SAFE_CAST(JSON_VALUE(split, '$.amountCents') AS INT64) AS amount_cents
FROM {{ source("simsplit", "expenses") }} AS e,
    UNNEST(JSON_QUERY_ARRAY(e.splits)) AS split

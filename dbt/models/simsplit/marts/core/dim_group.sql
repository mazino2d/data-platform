-- Dimension: group — one row per group with its size and activity totals.
WITH
members AS (
    SELECT
        group_id,
        COUNT(*) AS member_count
    FROM {{ ref("stg_members") }}
    WHERE NOT is_deleted
    GROUP BY group_id
),

expenses AS (
    SELECT
        group_id,
        COUNT(*) AS expense_count,
        MIN(created_at) AS first_expense_at,
        MAX(created_at) AS last_expense_at
    FROM {{ ref("stg_expenses") }}
    WHERE NOT is_deleted
    GROUP BY group_id
)

SELECT
    g.group_id,
    g.currency_code,
    g.owner_uid,
    g.account_count,
    g.created_at,
    g.is_archived,
    g.is_deleted,
    e.first_expense_at,
    e.last_expense_at,
    COALESCE(m.member_count, 0) AS member_count,
    COALESCE(e.expense_count, 0) AS expense_count
FROM {{ ref("stg_groups") }} AS g
LEFT JOIN members AS m ON g.group_id = m.group_id
LEFT JOIN expenses AS e ON g.group_id = e.group_id

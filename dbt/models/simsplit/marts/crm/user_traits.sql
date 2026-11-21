-- CRM traits (sim-split R-9): one row per account that exists today, with the
-- traits notification audiences select on. Traits only: no name, email, amount
-- or free text, since this is the only dataset the crm service can read.
-- Rebuilt daily from dim_user, so a deleted account's row is gone after the
-- next run. All ages are whole days before the run.
WITH latest_event AS (
    -- The endpoint's clock (received_at), not the device's, orders events.
    SELECT
        uid,
        MAX(received_at) AS last_active_at,
        -- Each of platform, language and version from the latest event that has one.
        ARRAY_AGG(
            platform IGNORE NULLS
            ORDER BY received_at DESC
            LIMIT 1
        )[SAFE_OFFSET(0)] AS platform,
        ARRAY_AGG(
            language IGNORE NULLS
            ORDER BY received_at DESC
            LIMIT 1
        )[SAFE_OFFSET(0)] AS language,  -- noqa: RF04
        ARRAY_AGG(
            app_version IGNORE NULLS
            ORDER BY received_at DESC
            LIMIT 1
        )[SAFE_OFFSET(0)] AS app_version,
        COUNT(
            DISTINCT IF(received_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY), session_id, NULL)
        ) AS sessions_30d
    FROM {{ ref("fct_usage_events") }}
    GROUP BY uid
),

open_groups AS (
    SELECT group_id
    FROM {{ ref("stg_groups") }}
    WHERE NOT is_deleted AND NOT COALESCE(is_archived, FALSE)
),

members AS (
    -- Members claimed by an account, in open groups.
    SELECT
        m.member_id,
        m.group_id,
        m.linked_uid AS uid
    FROM {{ ref("stg_members") }} AS m
    INNER JOIN open_groups AS g ON m.group_id = g.group_id
    WHERE NOT m.is_deleted AND m.linked_uid IS NOT NULL
),

expenses AS (
    SELECT
        expense_id,
        group_id,
        paid_by_member_id,
        amount_cents,
        created_at
    FROM {{ ref("stg_expenses") }}
    WHERE NOT is_deleted
),

-- Signed amounts in integer cents: what a member put in minus what they owe.
movements AS (
    SELECT
        paid_by_member_id AS member_id,
        amount_cents
    FROM expenses
    UNION ALL
    SELECT
        s.member_id,
        -s.amount_cents AS amount_cents
    FROM {{ ref("stg_expense_splits") }} AS s
    INNER JOIN expenses AS e ON s.expense_id = e.expense_id
    UNION ALL
    SELECT
        from_member_id AS member_id,
        amount_cents
    FROM {{ ref("stg_settlements") }}
    WHERE NOT is_deleted
    UNION ALL
    SELECT
        to_member_id AS member_id,
        -amount_cents AS amount_cents
    FROM {{ ref("stg_settlements") }}
    WHERE NOT is_deleted
),

member_balances AS (
    SELECT
        member_id,
        SUM(COALESCE(amount_cents, 0)) AS balance_cents
    FROM movements
    GROUP BY member_id
),

account_groups AS (
    -- One row per account and open group; an account with two members in a
    -- group gets their balances summed.
    SELECT
        m.uid,
        m.group_id,
        SUM(COALESCE(b.balance_cents, 0)) AS balance_cents
    FROM members AS m
    LEFT JOIN member_balances AS b ON m.member_id = b.member_id
    GROUP BY m.uid, m.group_id
),

group_accounts AS (
    SELECT
        group_id,
        COUNT(DISTINCT uid) AS account_count
    FROM members
    GROUP BY group_id
),

group_oldest_expense AS (
    SELECT
        group_id,
        MIN(created_at) AS oldest_expense_at
    FROM expenses
    GROUP BY group_id
),

group_traits AS (
    SELECT
        a.uid,
        COUNT(*) AS open_groups,
        COUNTIF(c.account_count >= 2) AS shared_groups,
        COUNTIF(a.balance_cents <= -1) AS owes_groups,
        COUNTIF(a.balance_cents >= 1) AS owed_groups,
        MIN(IF(a.balance_cents <= -1, o.oldest_expense_at, NULL)) AS oldest_unsettled_at
    FROM account_groups AS a
    INNER JOIN group_accounts AS c ON a.group_id = c.group_id
    LEFT JOIN group_oldest_expense AS o ON a.group_id = o.group_id
    GROUP BY a.uid
)

SELECT
    u.uid,
    e.platform,
    e.language,
    -- CalVer only: drop build numbers and dev suffixes (2026.11.21-dev.5182a8c+28025831).
    REGEXP_EXTRACT(e.app_version, r'^\d+\.\d+\.\d+') AS app_version,
    TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), u.created_at, DAY) AS signup_days,
    TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), e.last_active_at, DAY) AS last_active_days,
    COALESCE(e.sessions_30d, 0) AS sessions_30d,
    COALESCE(g.open_groups, 0) AS open_groups,
    COALESCE(g.shared_groups, 0) AS shared_groups,
    COALESCE(g.owes_groups, 0) AS owes_groups,
    COALESCE(g.owed_groups, 0) AS owed_groups,
    TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), g.oldest_unsettled_at, DAY) AS oldest_unsettled_days
FROM {{ ref("dim_user") }} AS u
LEFT JOIN latest_event AS e ON u.uid = e.uid
LEFT JOIN group_traits AS g ON u.uid = g.uid

-- Metric: activation funnel per sign-up week — signed up (agreed), created or
-- joined a group, logged a first expense, had a friend join through an invite.
-- Covers existing accounts only: a deleted account leaves the warehouse.
WITH
users AS (
    SELECT
        uid,
        DATE_TRUNC(DATE(created_at), WEEK (MONDAY)) AS signup_week
    FROM {{ ref("dim_user") }}
),

first_group AS (
    SELECT uid
    FROM {{ ref("stg_group_accounts") }}
    GROUP BY uid
),

first_expense AS (
    SELECT created_by AS uid
    FROM {{ ref("fct_expenses") }}
    GROUP BY uid
),

invite_accepted AS (
    -- Someone else joined a group this account belongs to.
    SELECT ga.uid
    FROM {{ ref("stg_activity") }} AS a
    INNER JOIN {{ ref("stg_group_accounts") }} AS ga
        ON a.group_id = ga.group_id AND a.actor_uid != ga.uid
    WHERE a.action = 'join'
    GROUP BY ga.uid
)

SELECT
    u.signup_week,
    COUNT(*) AS signed_up,
    COUNT(g.uid) AS in_a_group,
    COUNT(e.uid) AS logged_an_expense,
    COUNT(i.uid) AS friend_joined
FROM users AS u
LEFT JOIN first_group AS g ON u.uid = g.uid
LEFT JOIN first_expense AS e ON u.uid = e.uid
LEFT JOIN invite_accepted AS i ON u.uid = i.uid
GROUP BY u.signup_week

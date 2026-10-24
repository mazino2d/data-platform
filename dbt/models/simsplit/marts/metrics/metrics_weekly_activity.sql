-- Metric: groups, expenses and settlements created per week.
WITH
created AS (
    SELECT
        'groups' AS entity,
        created_at
    FROM {{ ref("dim_group") }}
    UNION ALL
    SELECT
        'expenses' AS entity,
        created_at
    FROM {{ ref("fct_expenses") }}
    UNION ALL
    SELECT
        'settlements' AS entity,
        created_at
    FROM {{ ref("fct_settlements") }}
)

SELECT
    entity,
    DATE_TRUNC(DATE(created_at), WEEK (MONDAY)) AS week_start,
    COUNT(*) AS created
FROM created
GROUP BY entity, week_start

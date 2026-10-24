-- Metric: active users per day — daily, weekly (7-day) and monthly (28-day)
-- active accounts, from usage events.
WITH
days AS (
    SELECT day
    FROM UNNEST(GENERATE_DATE_ARRAY(
        (SELECT MIN(event_date) FROM {{ ref("fct_usage_events") }}),
        CURRENT_DATE()
    )) AS day
),

active AS (
    SELECT DISTINCT
        event_date,
        uid
    FROM {{ ref("fct_usage_events") }}
)

SELECT
    d.day,
    COUNT(DISTINCT IF(a.event_date = d.day, a.uid, NULL)) AS daily_active_users,
    COUNT(DISTINCT IF(a.event_date > DATE_SUB(d.day, INTERVAL 7 DAY), a.uid, NULL)) AS weekly_active_users,
    COUNT(DISTINCT a.uid) AS monthly_active_users
FROM days AS d
LEFT JOIN active AS a
    ON a.event_date BETWEEN DATE_SUB(d.day, INTERVAL 27 DAY) AND d.day
GROUP BY d.day

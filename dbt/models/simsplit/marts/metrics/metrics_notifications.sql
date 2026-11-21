-- Metric: pushes per day, source and source_id (sim-split R-9 AC24): send
-- results, recipients, and opens from the app's op_notification_opened usage
-- events. An open's result is <source>:<source_id>; builds from before that
-- logged the category instead, so a result without a colon counts under an
-- unknown source. Opens count on the day they happen, not the day of the send.
WITH
sends AS (
    SELECT
        send_date AS day,
        source,
        source_id,
        COUNT(*) AS sends,
        COUNTIF(result = 'sent') AS sent,
        COUNTIF(result = 'invalid_token') AS invalid_token,
        COUNTIF(result = 'failed') AS failed,
        COUNT(DISTINCT uid) AS recipients
    FROM {{ ref("fct_crm_sends") }}
    GROUP BY day, source, source_id
),

opens AS (
    SELECT
        event_date AS day,
        IF(STRPOS(result, ':') > 0, SPLIT(result, ':')[OFFSET(0)], 'unknown') AS source,  -- noqa: RF04
        IF(STRPOS(result, ':') > 0, SUBSTR(result, STRPOS(result, ':') + 1), 'unknown') AS source_id,
        COUNT(*) AS opens
    FROM {{ ref("fct_usage_events") }}
    WHERE event_kind = 'op' AND event_name = 'op_notification_opened'
    GROUP BY day, source, source_id
)

SELECT
    COALESCE(s.day, o.day) AS day,
    COALESCE(s.source, o.source) AS source,  -- noqa: RF04
    COALESCE(s.source_id, o.source_id) AS source_id,
    COALESCE(s.sends, 0) AS sends,
    COALESCE(s.sent, 0) AS sent,
    COALESCE(s.invalid_token, 0) AS invalid_token,
    COALESCE(s.failed, 0) AS failed,
    COALESCE(s.recipients, 0) AS recipients,
    COALESCE(o.opens, 0) AS opens,
    SAFE_DIVIDE(o.opens, s.sent) AS open_rate,
    SAFE_DIVIDE(s.invalid_token, s.sends) AS invalid_token_rate
FROM sends AS s
FULL OUTER JOIN opens AS o
    ON s.day = o.day AND s.source = o.source AND s.source_id = o.source_id

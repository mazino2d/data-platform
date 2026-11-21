-- Metric: pushes per day, source and source_id (sim-split R-9 AC24): send
-- results, recipients, and opens from the app's op_notification_opened usage
-- events. The app records an open's result as <source>_<source_id> with '-'
-- turned into '_' (e.g. trigger_group_activity), so sends join on the same
-- normalised id; builds from before that logged the category instead, which
-- counts under an unknown source. Opens count on the day they happen.
WITH
sends AS (
    SELECT
        send_date AS day,
        source,
        source_id,
        REPLACE(source_id, '-', '_') AS source_key,
        COUNT(*) AS sends,
        COUNTIF(result = 'sent') AS sent,
        COUNTIF(result = 'invalid_token') AS invalid_token,
        COUNTIF(result = 'failed') AS failed,
        COUNT(DISTINCT uid) AS recipients
    FROM {{ ref("fct_crm_sends") }}
    GROUP BY day, source, source_id, source_key
),

opens AS (
    SELECT
        event_date AS day,
        COALESCE(REGEXP_EXTRACT(result, r'^(trigger|schedule|campaign)_.+$'), 'unknown') AS source,  -- noqa: RF04
        COALESCE(REGEXP_EXTRACT(result, r'^(?:trigger|schedule|campaign)_(.+)$'), 'unknown') AS source_key,
        COUNT(*) AS opens
    FROM {{ ref("fct_usage_events") }}
    WHERE event_kind = 'op' AND event_name = 'op_notification_opened'
    GROUP BY day, source, source_key
)

SELECT
    COALESCE(s.day, o.day) AS day,
    COALESCE(s.source, o.source) AS source,  -- noqa: RF04
    COALESCE(s.source_id, o.source_key) AS source_id,
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
    ON s.day = o.day AND s.source = o.source AND s.source_key = o.source_key

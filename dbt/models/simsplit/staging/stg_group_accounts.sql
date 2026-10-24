-- Staging: group_accounts — which accounts belong to which group (one row per pair).
SELECT
    g.doc_id AS group_id,
    JSON_VALUE(account_uid) AS uid
FROM {{ source("simsplit", "groups") }} AS g,
    UNNEST(JSON_QUERY_ARRAY(g.member_uids)) AS account_uid

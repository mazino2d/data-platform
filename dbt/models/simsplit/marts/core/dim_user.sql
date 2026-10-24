-- Dimension: user — one row per account that exists today. Rebuilt from the
-- replaced users load, so a deleted account's name and email are gone after
-- the next daily run (sim-split R-4 AC11). Facts keep its uid only.
SELECT
    uid,
    display_name,
    email,
    created_at,
    agreed_at,
    policy_version
FROM {{ ref("stg_users") }}

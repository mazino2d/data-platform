-- Staging: users — one row per account and the privacy policy revision it
-- agreed to by signing in. Never snapshotted: a deleted account leaves the
-- warehouse with the next daily load (sim-split R-4 AC11).
SELECT
    doc_id AS uid,
    display_name,
    email,
    created_at,
    consent__agreed_at AS agreed_at,
    consent__policy_version AS policy_version
FROM {{ source("simsplit", "users") }}

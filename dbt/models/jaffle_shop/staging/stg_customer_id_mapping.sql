-- Staging: customer_id_mapping
-- Maps old_id → new_id when the backend reassigns a customer's source ID.
-- Add rows here to preserve master_sk stability across ID migrations.
SELECT
    CAST(old_id AS INT64) AS old_id,
    CAST(new_id AS INT64) AS new_id
FROM {{ ref("customer_id_mapping") }}

-- Staging: payments — immutable fact rows enriched with FK surrogate keys.
--
-- order_sk:       Order version active when the payment was processed (PIT join).
-- order_master_sk: Stable order entity key — use for GROUP BY in int_order_payments.
WITH
_raw AS (
    SELECT * FROM {{ source("jaffle_shop", "payments") }}
),

{{ fk_sk_enrich(
    '_raw', 'order_id', 'created_at',
    ref('stg_orders'), 'order_id', 'order',
    sk_map_ref=ref('dim_order_sk_map'),
    output_cte='_enriched'
) }}

SELECT
    id AS payment_id,
    order_id,
    order_sk,
    order_master_sk,
    method AS payment_method,
    status AS payment_status,
    amount,
    created_at
FROM _enriched

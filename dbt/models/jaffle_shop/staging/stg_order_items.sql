-- Staging: order_items — immutable fact rows enriched with FK surrogate keys.
--
-- order_sk / order_master_sk:     Order version active at item creation time (PIT join).
-- product_sk / product_master_sk: Product version active at item creation time (PIT join).
--                                 Captures the exact product state (price, name) at purchase.
WITH
_raw AS (
    SELECT * FROM {{ source("jaffle_shop", "order_items") }}
),

{{ fk_sk_enrich(
    '_raw', 'order_id', 'created_at',
    ref('stg_orders'), 'order_id', 'order',
    sk_map_ref=ref('dim_order_sk_map'),
    output_cte='_with_order'
) }},

{{ fk_sk_enrich(
    '_with_order', 'product_id', 'created_at',
    ref('stg_products'), 'product_id', 'product',
    sk_map_ref=ref('dim_product_sk_map'),
    output_cte='_enriched'
) }}

SELECT
    id AS order_item_id,
    order_id,
    order_sk,
    order_master_sk,
    product_id,
    product_sk,
    product_master_sk,
    quantity,
    unit_price,
    CAST(created_at AS TIMESTAMP) AS created_at,
    (quantity * unit_price) AS line_total
FROM _enriched

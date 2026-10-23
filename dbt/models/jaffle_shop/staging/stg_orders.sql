-- Staging: orders — all historical versions with surrogate keys.
--
-- sk:                  Unique per version (= dbt_scd_id from snapshot).
-- master_sk:           Stable per order entity — useful when tracking an order across
--                      status changes (placed → shipped → completed → returned).
-- customer_sk:         Customer version active when the order was placed (PIT join).
-- customer_master_sk:  Stable customer entity key.
--
-- Incremental strategy:
--   Full refresh  → master_sk via FIRST_VALUE window function (bootstrap only).
--   Daily runs    → master_sk via O(1) hash join against dim_order_sk_map.
{{ config(materialized='incremental', unique_key='sk', on_schema_change='fail') }}

WITH
{{ scd_surrogate_keys(
    ref('orders_snapshot'),
    'id',
    sk_map_ref=ref('dim_order_sk_map')
) }},

{{ fk_sk_enrich(
    '_sk_final', 'customer_id', 'placed_at',
    ref('stg_customers'), 'customer_id', 'customer',
    sk_map_ref=ref('dim_customer_sk_map'),
    output_cte='_sk_final_enriched'
) }}

SELECT
    sk,
    master_sk,
    source_id AS order_id,
    canonical_id,
    customer_id,
    customer_sk,
    customer_master_sk,
    status,
    amount,
    placed_at,
    updated_at,
    valid_from,
    valid_to,
    is_current
FROM _sk_final_enriched

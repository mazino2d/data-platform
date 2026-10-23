-- Staging: products — all historical versions with surrogate keys.
--
-- sk:        Unique per version (= dbt_scd_id from snapshot).
-- master_sk: Stable per product entity — useful when tracking price or
--            availability changes over time.
--
-- Incremental strategy:
--   Full refresh  → master_sk via FIRST_VALUE window function (bootstrap only).
--   Daily runs    → master_sk via O(1) hash join against dim_product_sk_map.
{{ config(materialized='incremental', unique_key='sk', on_schema_change='fail') }}

WITH
{{ scd_surrogate_keys(
    ref('products_snapshot'),
    'id',
    sk_map_ref=ref('dim_product_sk_map')
) }}

SELECT
    sk,
    master_sk,
    source_id AS product_id,
    canonical_id,
    name AS product_name,
    category,
    price,
    is_active,
    CAST(created_at AS TIMESTAMP) AS created_at,
    CAST(updated_at AS TIMESTAMP) AS updated_at,
    valid_from,
    valid_to,
    is_current
FROM _sk_final

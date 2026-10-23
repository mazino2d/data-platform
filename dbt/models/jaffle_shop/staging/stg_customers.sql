-- Staging: customers — all historical versions with surrogate keys.
--
-- sk:          Unique per version (= dbt_scd_id from snapshot).
-- master_sk:   Stable per entity forever — assigned on first appearance,
--              inherited by every subsequent version including after ID migrations.
-- canonical_id: Resolves migrated source IDs back to the original ID so that
--              master_sk grouping remains consistent across backend ID changes.
--
-- Incremental strategy:
--   Full refresh  → master_sk via FIRST_VALUE window function (bootstrap only).
--   Daily runs    → master_sk via O(1) hash join against dim_customer_sk_map.
{{ config(materialized='incremental', unique_key='sk', on_schema_change='fail') }}

WITH
{{ scd_surrogate_keys(
    ref('customers_snapshot'),
    'id',
    sk_map_ref=ref('dim_customer_sk_map'),
    mapping_ref=ref('stg_customer_id_mapping')
) }}

SELECT
    sk,
    master_sk,
    source_id AS customer_id,
    canonical_id,
    name,
    email,
    country,
    status,
    CAST(created_at AS TIMESTAMP) AS created_at,
    CAST(updated_at AS TIMESTAMP) AS updated_at,
    valid_from,
    valid_to,
    is_current
FROM _sk_final

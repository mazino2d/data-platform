-- SK map: products
-- One row per product entity (canonical_id → master_sk).
-- Reads from the snapshot directly to avoid circular dependency with stg_products.
-- Append-only incremental: master_sk is assigned once and never changes.
{{ config(materialized='incremental', unique_key='canonical_id') }}

{{ scd_sk_map(ref('products_snapshot'), 'id') }}

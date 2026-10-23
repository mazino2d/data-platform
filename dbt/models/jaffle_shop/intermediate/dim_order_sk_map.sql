-- SK map: orders
-- One row per order entity (canonical_id → master_sk).
-- Reads from the snapshot directly to avoid circular dependency with stg_orders.
-- Append-only incremental: master_sk is assigned once and never changes.
{{ config(materialized='incremental', unique_key='canonical_id') }}

{{ scd_sk_map(ref('orders_snapshot'), 'id') }}

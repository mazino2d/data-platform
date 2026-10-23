-- SK map: customers
-- One row per customer entity (canonical_id → master_sk).
-- Reads from the snapshot directly to avoid circular dependency with stg_customers.
-- Append-only incremental: master_sk is assigned once and never changes.
{{ config(materialized='incremental', unique_key='canonical_id') }}

{{ scd_sk_map(
    ref('customers_snapshot'),
    'id',
    mapping_ref=ref('stg_customer_id_mapping')
) }}

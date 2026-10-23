{% snapshot orders_snapshot %}

{{
    config(
        unique_key="id",
        strategy="timestamp",
        updated_at="updated_at",
    )
}}

-- Capture SCD Type 2 history for orders.
-- Order status transitions (placed → shipped → completed) are tracked here.
    SELECT
        id,
        customer_id,
        status,
        amount,
        CAST(placed_at AS TIMESTAMP) AS placed_at,
        CAST(updated_at AS TIMESTAMP) AS updated_at
    FROM {{ source("jaffle_shop", "orders") }}
    {{ snapshot_incremental_filter(this) }}

{% endsnapshot %}

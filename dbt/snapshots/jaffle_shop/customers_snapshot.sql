{% snapshot customers_snapshot %}

{{
    config(
        unique_key="id",
        strategy="timestamp",
        updated_at="updated_at",
    )
}}

-- Capture SCD Type 2 history for customers.
-- The backend updates records in-place; snapshots preserve each version.
    SELECT
        id,
        name,
        email,
        country,
        status,
        CAST(created_at AS TIMESTAMP) AS created_at,
        CAST(updated_at AS TIMESTAMP) AS updated_at
    FROM {{ source("jaffle_shop", "customers") }}

{% endsnapshot %}

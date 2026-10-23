-- Mart: dim_customers
-- One row per customer (current version) with surrogate keys and lifetime order summary.
--
-- sk:        Join key for fact tables — uniquely identifies this customer version.
-- master_sk: Stable entity key — use for GROUP BY, COUNT DISTINCT, and cross-version analysis.
SELECT
    c.sk,
    c.master_sk,
    c.customer_id,
    c.name,
    c.email,
    c.country,
    c.status,
    c.created_at,
    c.updated_at,
    c.valid_from,

    -- Order history aggregates
    co.first_order_at,
    co.last_order_at,
    COALESCE(co.total_orders, 0) AS total_orders,
    COALESCE(co.total_spent, 0) AS total_spent,
    COALESCE(co.completed_orders, 0) AS completed_orders,
    COALESCE(co.returned_orders, 0) AS returned_orders
FROM {{ ref("stg_customers") }} AS c
LEFT JOIN {{ ref("int_customer_orders") }} AS co
    ON c.master_sk = co.customer_master_sk
WHERE c.is_current = TRUE

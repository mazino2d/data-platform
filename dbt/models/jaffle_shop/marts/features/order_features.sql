-- Feature table: order_features
-- Per-order features for ML models (e.g., return prediction, payment risk).
WITH order_items_summary AS (
    SELECT
        order_id,
        COUNT(*) AS item_count,
        SUM(quantity) AS total_quantity,
        COUNT(DISTINCT product_id) AS unique_products,
        AVG(unit_price) AS avg_unit_price
    FROM {{ ref("stg_order_items") }}
    GROUP BY order_id
)

SELECT
    fo.order_sk,
    fo.order_master_sk,
    fo.order_id,
    fo.customer_id,
    fo.customer_sk,
    fo.customer_master_sk,
    fo.order_status,
    fo.order_amount,
    fo.is_paid,
    fo.is_returned,

    -- Payment behavior features
    fo.payment_attempts,
    fo.failed_payments,
    fo.unpaid_amount,
    cf.lifetime_value AS customer_ltv_at_order,

    -- Customer context features
    cf.order_frequency AS customer_order_frequency,
    cf.return_rate AS customer_return_rate,
    fo.placed_at,
    CASE
        WHEN fo.payment_attempts > 0
            THEN fo.failed_payments * 1.0 / fo.payment_attempts
        ELSE 0
    END AS payment_failure_rate,

    -- Order item features
    COALESCE(oi.item_count, 0) AS item_count,
    COALESCE(oi.total_quantity, 0) AS total_quantity,
    COALESCE(oi.unique_products, 0) AS unique_products,
    COALESCE(oi.avg_unit_price, 0) AS avg_unit_price
FROM {{ ref("fct_orders") }} AS fo
LEFT JOIN order_items_summary AS oi
    ON fo.order_id = oi.order_id
LEFT JOIN {{ ref("customer_features") }} AS cf
    ON fo.customer_id = cf.customer_id

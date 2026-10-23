-- Feature table: customer_features
-- RFM (Recency, Frequency, Monetary) features per customer for ML models.
-- One row per customer, computed from current order and payment history.
SELECT
    dc.sk AS customer_sk,
    dc.master_sk,
    dc.customer_id,
    dc.status AS customer_status,
    dc.country,

    -- Recency: days since last order (lower = more recent = better)
    dc.completed_orders AS order_frequency,

    -- Frequency: total number of completed orders
    dc.total_spent AS lifetime_value,

    -- Monetary: total lifetime spend
    dc.total_orders,

    -- Derived ratios. Day counts are calendar days (DATE_DIFF), not 24-hour periods.
    DATE_DIFF(CURRENT_DATE(), DATE(dc.last_order_at), DAY)
        AS days_since_last_order,
    CASE
        WHEN dc.total_orders > 0
            THEN dc.returned_orders * 1.0 / dc.total_orders
        ELSE 0
    END AS return_rate,

    CASE
        WHEN dc.total_orders > 0
            THEN dc.total_spent / dc.total_orders
        ELSE 0
    END AS avg_order_value,

    -- Tenure: days since first order
    DATE_DIFF(CURRENT_DATE(), DATE(dc.first_order_at), DAY)
        AS customer_tenure_days,

    -- Order cadence: avg days between orders (null if fewer than 2 orders)
    CASE
        WHEN dc.total_orders >= 2
            THEN
                DATE_DIFF(DATE(dc.last_order_at), DATE(dc.first_order_at), DAY)
                * 1.0 / (dc.total_orders - 1)
    END AS avg_days_between_orders
FROM {{ ref("dim_customers") }} AS dc
WHERE dc.last_order_at IS NOT NULL

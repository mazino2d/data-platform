-- Intermediate: payments joined to orders
-- Aggregates payment-level metrics per order entity.
-- Groups by order_master_sk (stable entity key) so results remain correct
-- if an order's natural key is ever reassigned.
SELECT
    p.order_master_sk,
    COUNT(p.payment_id) AS payment_attempts,
    SUM(CASE WHEN p.payment_status = 'success' THEN p.amount ELSE 0 END)
        AS paid_amount,
    COUNT(CASE WHEN p.payment_status = 'success' THEN 1 END)
        AS successful_payments,
    COUNT(CASE WHEN p.payment_status = 'failed' THEN 1 END) AS failed_payments,
    COUNT(CASE WHEN p.payment_status = 'refunded' THEN 1 END)
        AS refunded_payments,
    -- True if the order has at least one successful payment and no refunds
    MAX(CASE WHEN p.payment_status = 'success' THEN 1 ELSE 0 END) = 1
    AND MAX(CASE WHEN p.payment_status = 'refunded' THEN 1 ELSE 0 END) = 0
        AS is_paid
FROM {{ ref("stg_payments") }} AS p
GROUP BY p.order_master_sk

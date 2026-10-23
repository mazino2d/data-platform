-- Mart: fct_orders
-- One row per order (current version) with payment summary and surrogate keys.
--
-- order_sk / order_master_sk:       Identify the order version and entity.
-- customer_sk / customer_master_sk: Point-in-time customer version active when the
--                                   order was placed, and the stable entity key.
--                                   Pre-computed in stg_orders via fk_sk_enrich macro.
SELECT
    o.sk AS order_sk,
    o.master_sk AS order_master_sk,
    o.order_id,
    o.customer_id,
    o.status AS order_status,
    o.amount AS order_amount,
    o.placed_at,
    o.updated_at,
    o.customer_sk,
    o.customer_master_sk,

    -- Payment summary
    COALESCE(p.payment_attempts, 0) AS payment_attempts,
    COALESCE(p.paid_amount, 0) AS paid_amount,
    COALESCE(p.is_paid, FALSE) AS is_paid,
    COALESCE(p.failed_payments, 0) AS failed_payments,
    COALESCE(p.refunded_payments, 0) AS refunded_payments,

    -- Computed flags
    o.status = 'returned' AS is_returned,
    o.amount - COALESCE(p.paid_amount, 0) AS unpaid_amount
FROM {{ ref("stg_orders") }} AS o
LEFT JOIN {{ ref("int_order_payments") }} AS p
    ON o.master_sk = p.order_master_sk
WHERE o.is_current = TRUE

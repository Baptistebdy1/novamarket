BEGIN;

CREATE SCHEMA IF NOT EXISTS reception;

CREATE TABLE IF NOT EXISTS reception.customers (
    customer_id text,
    customer_name text,
    city text
);

CREATE TABLE IF NOT EXISTS reception.orders (
    order_id text,
    customer_id text,
    ordered_on text,
    status text
);

CREATE TABLE IF NOT EXISTS reception.order_items (
    order_item_id text,
    order_id text,
    product_id text,
    quantity text,
    unit_price_cents text
);

CREATE TABLE IF NOT EXISTS reception.payments (
    document jsonb
);

-- Chaque exécution recharge les sources fournies dans la zone de réception.
TRUNCATE reception.customers, reception.orders, reception.order_items, reception.payments;

\copy reception.customers (customer_id, customer_name, city) FROM '/s1/donnees/customers.csv' WITH (FORMAT csv, HEADER true)
\copy reception.orders (order_id, customer_id, ordered_on, status) FROM '/s1/donnees/orders.csv' WITH (FORMAT csv, HEADER true)
\copy reception.order_items (order_item_id, order_id, product_id, quantity, unit_price_cents) FROM '/s1/donnees/order_items.csv' WITH (FORMAT csv, HEADER true)
\copy reception.payments (document) FROM '/s1/donnees/payments.ndjson' WITH (FORMAT csv, QUOTE E'\x01', DELIMITER E'\x02')

SELECT 'customers' AS source, count(*) AS lignes_brutes FROM reception.customers
UNION ALL
SELECT 'orders', count(*) FROM reception.orders
UNION ALL
SELECT 'order_items', count(*) FROM reception.order_items
UNION ALL
SELECT 'payments', count(*) FROM reception.payments
ORDER BY source;

COMMIT;

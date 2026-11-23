-- Charge une première fois les tables métier depuis la réception.
BEGIN ISOLATION LEVEL REPEATABLE READ;

CREATE SCHEMA IF NOT EXISTS qualite;

CREATE TABLE IF NOT EXISTS qualite.rejets (
    source text NOT NULL,
    identifiant text NOT NULL,
    donnees jsonb NOT NULL,
    motif text NOT NULL
);

INSERT INTO public.customers (customer_id, customer_name, city)
SELECT customer_id::integer, customer_name, city
FROM reception.customers;

INSERT INTO public.orders (order_id, customer_id, ordered_on, status)
SELECT order_id::integer, customer_id::integer, ordered_on::date, status
FROM reception.orders;

CREATE TEMP TABLE articles_controles ON COMMIT DROP AS
WITH occurrences AS (
    SELECT a.*,
           row_number() OVER (
               PARTITION BY order_item_id, order_id, product_id, quantity, unit_price_cents
           ) AS occurrence
    FROM reception.order_items AS a
)
SELECT a.order_item_id, a.order_id, a.product_id, a.quantity, a.unit_price_cents,
       CASE
           WHEN o.order_id IS NULL THEN 'commande orpheline'
           WHEN a.occurrence > 1 THEN 'doublon exact'
       END AS motif
FROM occurrences AS a
LEFT JOIN public.orders AS o ON o.order_id = a.order_id::integer;

INSERT INTO qualite.rejets (source, identifiant, donnees, motif)
SELECT 'order_items.csv', a.order_item_id, to_jsonb(a) - 'motif', a.motif
FROM articles_controles AS a
WHERE a.motif IS NOT NULL;

INSERT INTO public.order_items (order_item_id, order_id, product_id, quantity, unit_price_cents)
SELECT order_item_id::integer, order_id::integer, product_id::integer,
       quantity::integer, unit_price_cents::integer
FROM articles_controles
WHERE motif IS NULL;

INSERT INTO public.payments (payment_id, order_id, paid_on, amount_cents, status)
SELECT p.payment_id, p.order_id, p.paid_on, p.amount_cents, p.status
FROM reception.payments AS r
CROSS JOIN LATERAL jsonb_to_record(r.document) AS p (
    payment_id integer, order_id integer, paid_on date, amount_cents integer, status text
);

CREATE TEMP VIEW bilan_integration AS
SELECT 'customers' AS source,
       (SELECT count(*) FROM reception.customers) AS brut,
       (SELECT count(*) FROM public.customers) AS integre,
       0::bigint AS rejete
UNION ALL
SELECT 'orders',
       (SELECT count(*) FROM reception.orders),
       (SELECT count(*) FROM public.orders),
       0
UNION ALL
SELECT 'order_items',
       (SELECT count(*) FROM reception.order_items),
       (SELECT count(*) FROM public.order_items),
       (SELECT count(*) FROM qualite.rejets WHERE source = 'order_items.csv')
UNION ALL
SELECT 'payments',
       (SELECT count(*) FROM reception.payments),
       (SELECT count(*) FROM public.payments),
       0;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM bilan_integration WHERE brut <> integre + rejete) THEN
        RAISE EXCEPTION 'Le volume brut ne correspond pas aux volumes intégrés et rejetés';
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.orders AS o
        WHERE NOT EXISTS (SELECT 1 FROM public.order_items AS a WHERE a.order_id = o.order_id)
    ) THEN
        RAISE EXCEPTION 'Une commande intégrée ne contient aucun article';
    END IF;
END;
$$;

SELECT * FROM bilan_integration ORDER BY source;

SELECT source, identifiant, donnees->>'order_id' AS order_id, motif
FROM qualite.rejets
ORDER BY source, identifiant::integer;

COMMIT;

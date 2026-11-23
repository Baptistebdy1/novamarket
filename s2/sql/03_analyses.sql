-- Rang des produits par catégorie, selon le CA des commandes terminées.
WITH ventes_produits AS (
    SELECT p.category_id, p.product_id, p.product_name,
           COALESCE(SUM(CAST(a.quantity AS bigint) * a.unit_price_cents)
               FILTER (WHERE o.status = 'completed'), 0) AS ca_cents
    FROM public.products AS p
    LEFT JOIN public.order_items AS a ON a.product_id = p.product_id
    LEFT JOIN public.orders AS o ON o.order_id = a.order_id
    GROUP BY p.category_id, p.product_id, p.product_name
)
SELECT c.category_name, v.product_id, v.product_name, v.ca_cents,
       RANK() OVER (PARTITION BY v.category_id ORDER BY v.ca_cents DESC) AS rang
FROM ventes_produits AS v
JOIN public.categories AS c ON c.category_id = v.category_id
ORDER BY v.category_id, rang, v.product_id;

-- Rang global des clients qui ont au moins une commande terminée.
WITH ventes_clients AS (
    SELECT o.customer_id, SUM(CAST(a.quantity AS bigint) * a.unit_price_cents) AS ca_cents
    FROM public.orders AS o
    JOIN public.order_items AS a ON a.order_id = o.order_id
    WHERE o.status = 'completed'
    GROUP BY o.customer_id
)
SELECT customer_id, ca_cents, RANK() OVER (ORDER BY ca_cents DESC) AS rang
FROM ventes_clients
ORDER BY rang, customer_id;

-- Comparer les rangs dans la catégorie du produit dupliqué, avec et sans réception brute.
WITH fiches AS (
    SELECT 'catalogue' AS version, product_id, category_id FROM public.products
    UNION ALL
    SELECT 'reception', product_id, category_id FROM reception.products
),
ventes AS (
    SELECT f.version, f.product_id, SUM(CAST(a.quantity AS bigint) * a.unit_price_cents) AS ca_cents
    FROM fiches AS f
    JOIN public.order_items AS a ON a.product_id = f.product_id
    JOIN public.orders AS o ON o.order_id = a.order_id
    WHERE o.status = 'completed'
      AND f.category_id = (SELECT category_id FROM public.products WHERE product_id = 3)
    GROUP BY f.version, f.product_id
)
SELECT version, product_id, ca_cents,
       RANK() OVER (PARTITION BY version ORDER BY ca_cents DESC) AS rang
FROM ventes
ORDER BY version, rang, product_id;

-- LAG et LEAD comparent les mois voisins dans la période observée.
WITH bornes AS (
    SELECT MIN(ordered_on) AS debut, MAX(ordered_on) AS fin
    FROM public.orders
),
mois AS (
    SELECT m::date AS mois,
           m::date >= b.debut AND (m + INTERVAL '1 month - 1 day')::date <= b.fin AS complet
    FROM bornes AS b
    CROSS JOIN LATERAL generate_series(
        date_trunc('month', b.debut::timestamp),
        date_trunc('month', b.fin::timestamp),
        INTERVAL '1 month'
    ) AS g(m)
),
ventes AS (
    SELECT date_trunc('month', o.ordered_on::timestamp)::date AS mois,
           SUM(CAST(a.quantity AS bigint) * a.unit_price_cents) AS ca_cents
    FROM public.orders AS o
    JOIN public.order_items AS a ON a.order_id = o.order_id
    WHERE o.status = 'completed'
    GROUP BY date_trunc('month', o.ordered_on::timestamp)::date
),
totaux AS (
    SELECT m.mois, m.complet, COALESCE(v.ca_cents, 0) AS ca_cents
    FROM mois AS m
    LEFT JOIN ventes AS v ON v.mois = m.mois
)
SELECT mois, complet, ca_cents,
       LAG(ca_cents) OVER (ORDER BY mois) AS ca_precedent_cents,
       ca_cents - LAG(ca_cents) OVER (ORDER BY mois) AS variation_cents,
       LEAD(ca_cents) OVER (ORDER BY mois) AS ca_suivant_cents
FROM totaux
ORDER BY mois;

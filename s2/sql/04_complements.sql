-- Quartiles des clients avec commande terminée, du CA le plus haut au plus bas.
WITH ventes_clients AS (
    SELECT o.customer_id, SUM(CAST(a.quantity AS bigint) * a.unit_price_cents) AS ca_cents
    FROM public.orders AS o
    JOIN public.order_items AS a ON a.order_id = o.order_id
    WHERE o.status = 'completed'
    GROUP BY o.customer_id
),
quartiles AS (
    SELECT customer_id, ca_cents,
           NTILE(4) OVER (ORDER BY ca_cents DESC, customer_id) AS groupe
    FROM ventes_clients
)
SELECT groupe, COUNT(*) AS clients, MIN(ca_cents) AS min_cents,
       MAX(ca_cents) AS max_cents, SUM(ca_cents) AS total_cents
FROM quartiles
GROUP BY groupe
ORDER BY groupe;

-- Partir de chaque catégorie et remonter vers la racine. La liste chemin arrête les cycles.
WITH RECURSIVE remontee AS (
    SELECT category_id AS depart, category_id, parent_category_id,
           ARRAY[category_id] AS chemin, false AS cycle
    FROM public.categories
    UNION ALL
    SELECT r.depart, c.category_id, c.parent_category_id,
           r.chemin || c.category_id, c.category_id = ANY(r.chemin)
    FROM remontee AS r
    JOIN public.categories AS c ON c.category_id = r.parent_category_id
    WHERE NOT r.cycle
),
racines AS (
    SELECT depart AS category_id, category_id AS racine_id
    FROM remontee
    WHERE parent_category_id IS NULL AND NOT cycle
),
ventes_familles AS (
    SELECT r.racine_id, SUM(CAST(a.quantity AS bigint) * a.unit_price_cents) AS ca_cents
    FROM public.order_items AS a
    JOIN public.orders AS o ON o.order_id = a.order_id
    JOIN public.products AS p ON p.product_id = a.product_id
    JOIN racines AS r ON r.category_id = p.category_id
    WHERE o.status = 'completed'
    GROUP BY r.racine_id
)
SELECT c.category_name AS famille, v.ca_cents,
       (SELECT COUNT(*) FROM remontee WHERE cycle) AS cycles,
       (SELECT COUNT(*) FROM public.categories) - (SELECT COUNT(*) FROM racines) AS categories_sans_racine
FROM ventes_familles AS v
JOIN public.categories AS c ON c.category_id = v.racine_id
ORDER BY v.ca_cents DESC, v.racine_id;

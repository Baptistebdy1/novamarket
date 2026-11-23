-- Doublons exacts dans la réception et nombre d’occurrences.
SELECT order_item_id, order_id, product_id, quantity, unit_price_cents,
       COUNT(*) AS occurrences
FROM reception.order_items
GROUP BY order_item_id, order_id, product_id, quantity, unit_price_cents
HAVING COUNT(*) > 1
ORDER BY order_item_id;

-- Lignes reçues dont la commande est absente des sources.
SELECT a.order_item_id, a.order_id
FROM reception.order_items AS a
LEFT JOIN reception.orders AS o ON o.order_id = a.order_id
WHERE o.order_id IS NULL
ORDER BY a.order_item_id;

-- Jointure volontairement incorrecte pour mesurer la multiplication des montants.
SELECT COUNT(*) AS lignes_jointes,
       SUM(CAST(a.quantity AS bigint) * a.unit_price_cents) AS articles_gonfles_cents,
       SUM(p.amount_cents) AS paiements_gonfles_cents
FROM public.orders AS o
JOIN public.order_items AS a ON a.order_id = o.order_id
JOIN public.payments AS p ON p.order_id = o.order_id
WHERE o.status = 'completed' AND p.status = 'captured';

-- Effet du périmètre choisi sur le montant des articles.
SELECT o.status,
       SUM(CAST(a.quantity AS bigint) * a.unit_price_cents) AS articles_cents
FROM public.orders AS o
JOIN public.order_items AS a ON a.order_id = o.order_id
GROUP BY o.status
ORDER BY o.status;

-- Contrôle de reprise. Résultats attendus : les volumes de M2 et zéro commande sans article.
SELECT (SELECT COUNT(*) FROM public.customers) AS clients,
       (SELECT COUNT(*) FROM public.orders) AS commandes,
       (SELECT COUNT(*) FROM public.order_items) AS articles,
       (SELECT COUNT(*) FROM public.payments) AS paiements,
       (SELECT COUNT(*) FROM qualite.rejets WHERE source = 'order_items.csv') AS rejets,
       (
           SELECT COUNT(*)
           FROM public.orders AS o
           LEFT JOIN public.order_items AS a ON a.order_id = o.order_id
           WHERE a.order_item_id IS NULL
       ) AS commandes_sans_article;

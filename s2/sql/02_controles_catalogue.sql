-- Les fichiers et les tables sont comptés séparément.
SELECT 'categories.csv' AS source,
       (SELECT COUNT(*) FROM reception.categories) AS brut,
       (SELECT COUNT(*) FROM public.categories) AS integre,
       0 AS rejete
UNION ALL
SELECT 'products.csv',
       (SELECT COUNT(*) FROM reception.products),
       (SELECT COUNT(*) FROM public.products),
       (SELECT COUNT(*) FROM qualite.rejets WHERE source = 'products.csv');

SELECT identifiant, donnees->>'sku' AS sku, motif
FROM qualite.rejets
WHERE source = 'products.csv'
ORDER BY identifiant;

SELECT COUNT(*) AS lignes_s1,
       COUNT(DISTINCT a.product_id) AS codes_utilises,
       COUNT(*) FILTER (WHERE p.product_id IS NULL) AS lignes_sans_produit
FROM public.order_items AS a
LEFT JOIN public.products AS p ON p.product_id = a.product_id;

-- Comparer la date déclarée de mise en vente à la première commande observée.
SELECT p.product_id, p.product_name, p.first_listed_on,
       MIN(o.ordered_on) AS premiere_commande,
       COUNT(*) FILTER (WHERE o.ordered_on < p.first_listed_on) AS lignes_avant_mise_en_vente
FROM public.products AS p
JOIN public.order_items AS a ON a.product_id = p.product_id
JOIN public.orders AS o ON o.order_id = a.order_id
GROUP BY p.product_id, p.product_name, p.first_listed_on
HAVING MIN(o.ordered_on) < p.first_listed_on
ORDER BY p.product_id;

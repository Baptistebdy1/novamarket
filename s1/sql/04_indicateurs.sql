-- Nombre de commandes pour chaque état présent dans les données intégrées.
SELECT status, count(*) AS nombre_commandes
FROM public.orders
GROUP BY status
ORDER BY status;

-- Clients sans commande, tous états de commande confondus.
SELECT count(*) AS clients_sans_commande
FROM public.customers AS c
LEFT JOIN public.orders AS o ON o.customer_id = c.customer_id
WHERE o.order_id IS NULL;

-- Chiffre d’affaires en centimes des commandes terminées.
SELECT SUM(CAST(a.quantity AS bigint) * a.unit_price_cents) AS chiffre_affaires_cents
FROM public.order_items AS a
JOIN public.orders AS o ON o.order_id = a.order_id
WHERE o.status = 'completed';

-- Panier moyen en centimes des commandes terminées et dénominateur utilisé.
-- On calcule un total par commande, puis on fait la moyenne de ces totaux.
WITH paniers AS (
    SELECT SUM(CAST(a.quantity AS bigint) * a.unit_price_cents) AS montant_cents
    FROM public.orders AS o
    JOIN public.order_items AS a ON a.order_id = o.order_id
    WHERE o.status = 'completed'
    GROUP BY o.order_id
)
SELECT COUNT(*) AS nombre_commandes_terminees,
       AVG(montant_cents) AS panier_moyen_cents
FROM paniers;

-- Rapprochement des montants des commandes et des paiements.
-- 1. Calculer les deux totaux séparément, une ligne par commande.
WITH articles_par_commande AS (
    SELECT order_id,
           SUM(CAST(quantity AS bigint) * unit_price_cents) AS montant_cents
    FROM public.order_items
    GROUP BY order_id
),
paiements_par_commande AS (
    SELECT order_id, SUM(amount_cents) AS encaisse_cents
    FROM public.payments
    WHERE status = 'captured'
    GROUP BY order_id
),
-- 2. Rassembler les totaux. COALESCE remplace un montant absent par zéro.
totaux_par_commande AS (
    SELECT o.status,
           COALESCE(a.montant_cents, 0) AS montant_cents,
           COALESCE(p.encaisse_cents, 0) AS encaisse_cents
    FROM public.orders AS o
    LEFT JOIN articles_par_commande AS a ON a.order_id = o.order_id
    LEFT JOIN paiements_par_commande AS p ON p.order_id = o.order_id
)
-- 3. Résumer les montants et les écarts par statut de commande.
SELECT status,
       COUNT(*) AS nombre_commandes,
       SUM(montant_cents) AS articles_cents,
       SUM(encaisse_cents) AS encaisse_cents,
       SUM(encaisse_cents - montant_cents) AS ecart_cents,
       COUNT(*) FILTER (WHERE encaisse_cents <> montant_cents) AS commandes_en_ecart
FROM totaux_par_commande
GROUP BY status
ORDER BY status;

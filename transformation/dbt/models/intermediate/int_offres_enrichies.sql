-- M4 · Intermediate : offres enrichies avec le catalogue.
-- Règle réutilisable : n'importe quel futur mart (par fournisseur, par catégorie…)
-- peut partir de ce modèle au lieu de refaire les jointures.
--
-- Grain : INCHANGÉ (1 offre × 1 date). Pourquoi les jointures ne multiplient pas :
--   - produits   : produit_id est unique dans le catalogue -> au plus 1 ligne par offre ;
--   - catégories : categorie_id est unique                 -> au plus 1 ligne par produit.
-- Ces deux unicités sont testées dans _staging.yml.
-- Jointure INNER vers produits : le chargeur garantit déjà la FK, donc aucune perte.
-- Jointure LEFT vers la catégorie parente : une catégorie racine n'a pas de parent.

with offres as (
    select * from {{ ref('stg_fournisseur__offres') }}
),

produits as (
    select * from {{ ref('stg_catalogue__produits') }}
),

categories as (
    select * from {{ ref('stg_catalogue__categories') }}
)

select
    o.fournisseur_id,
    o.offre_id,
    o.date_observation,
    o.produit_id,
    p.sku,
    p.nom_produit,
    c.nom_categorie,
    parent.nom_categorie                                   as nom_categorie_parent,
    o.prix_centimes,
    o.prix_eur,
    o.stock_disponible,
    -- valeur du stock proposé (centimes) : utile pour pondérer un prix moyen
    o.prix_centimes * o.stock_disponible                   as valeur_stock_centimes,
    -- 1 = offre la moins chère pour ce produit ce jour-là (ex aequo départagés par fournisseur)
    row_number() over (
        partition by o.produit_id, o.date_observation
        order by o.prix_centimes, o.fournisseur_id, o.offre_id
    )                                                      as rang_prix
from offres as o
inner join produits as p
    on p.produit_id = o.produit_id
left join categories as c
    on c.categorie_id = p.categorie_id
left join categories as parent
    on parent.categorie_id = c.categorie_parent_id

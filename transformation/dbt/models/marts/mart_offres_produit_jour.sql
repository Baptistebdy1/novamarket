-- M4 · Premier mart : marché fournisseur par produit et par jour.
-- Question métier : « Pour un produit donné, combien de fournisseurs le proposent
-- ce jour-là, à quel prix, et qui est le moins cher ? »
--
-- Grain : 1 ligne = 1 produit × 1 date d'observation.
-- (On agrège les offres : c'est un changement de grain VOULU, du détail vers l'analyse.)
-- Matérialisation : table (voir dbt_project.yml), car lue souvent par la BI en S6.

with offres as (
    select * from {{ ref('int_offres_enrichies') }}
)

select
    date_observation,
    produit_id,
    sku,
    nom_produit,
    nom_categorie,
    nom_categorie_parent,
    count(*)                                               as nb_offres,
    count(distinct fournisseur_id)                         as nb_fournisseurs,
    (min(prix_centimes) / 100.0)::numeric(12, 2)           as prix_min_eur,
    (max(prix_centimes) / 100.0)::numeric(12, 2)           as prix_max_eur,
    (avg(prix_centimes) / 100.0)::numeric(12, 2)           as prix_moyen_eur,
    -- écart entre l'offre la plus chère et la moins chère, en % du prix mini
    -- (NULLIF évite une division par zéro si une offre est à 0 €)
    round(100.0 * (max(prix_centimes) - min(prix_centimes))
          / nullif(min(prix_centimes), 0), 1)              as ecart_prix_pct,
    sum(stock_disponible)                                  as stock_total,
    -- le fournisseur classé rang 1 dans l'intermediate
    max(fournisseur_id) filter (where rang_prix = 1)       as fournisseur_moins_cher
from offres
group by
    date_observation, produit_id, sku, nom_produit, nom_categorie, nom_categorie_parent

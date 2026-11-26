-- M3 · Staging des offres fournisseurs.
-- Rôle : harmoniser noms et types SANS changer le grain.
-- Grain conservé : 1 ligne = 1 offre d'un fournisseur à une date
--                  (fournisseur_id, offre_id, date_observation).
-- Pas de filtre, pas de jointure : même nombre de lignes que la source.

select
    supplier_id                              as fournisseur_id,
    offer_id                                 as offre_id,
    observed_on                              as date_observation,
    product_id                               as produit_id,
    price_cents                              as prix_centimes,
    -- prix en euros pour la lecture ; on garde les centimes pour les calculs exacts
    (price_cents / 100.0)::numeric(12, 2)    as prix_eur,
    -- char(3) en base -> text, plus simple à comparer et à exposer
    currency::text                           as devise,
    available_units                          as stock_disponible,
    lot_insertion                            as lot_id
from {{ source('fournisseur', 'offres_observations') }}

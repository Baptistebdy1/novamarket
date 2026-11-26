-- Test singulier (M5) : aucune ligne perdue ni multipliée entre source, staging et mart.
-- On compare :
--   - le nombre d'offres  : source = staging = somme(nb_offres) du mart ;
--   - le stock total      : staging = somme(stock_total) du mart.
-- Si une jointure dupliquait des lignes, ces totaux augmenteraient : le test échouerait.
with source as (
    select count(*) as nb, sum(available_units) as stock
    from {{ source('fournisseur', 'offres_observations') }}
),
staging as (
    select count(*) as nb, sum(stock_disponible) as stock
    from {{ ref('stg_fournisseur__offres') }}
),
mart as (
    select sum(nb_offres) as nb, sum(stock_total) as stock
    from {{ ref('mart_offres_produit_jour') }}
)
select source.nb as nb_source, staging.nb as nb_staging, mart.nb as nb_mart,
       source.stock as stock_source, staging.stock as stock_staging, mart.stock as stock_mart
from source, staging, mart
where not (source.nb = staging.nb and staging.nb = mart.nb
           and source.stock = staging.stock and staging.stock = mart.stock)

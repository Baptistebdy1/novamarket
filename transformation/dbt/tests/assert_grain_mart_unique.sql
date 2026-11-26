-- Test singulier : une seule ligne par produit et par jour dans le mart.
select produit_id, date_observation, count(*) as n
from {{ ref('mart_offres_produit_jour') }}
group by produit_id, date_observation
having count(*) > 1

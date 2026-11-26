-- Test singulier : le staging garde le grain du chargeur.
-- Un test dbt RÉUSSIT quand la requête ne renvoie AUCUNE ligne.
select fournisseur_id, offre_id, date_observation, count(*) as n
from {{ ref('stg_fournisseur__offres') }}
group by fournisseur_id, offre_id, date_observation
having count(*) > 1

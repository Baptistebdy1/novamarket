-- M3 · Staging des catégories (S2).
-- Grain : 1 ligne = 1 catégorie. parent_category_id est NULL pour une catégorie racine.

select
    category_id          as categorie_id,
    category_name        as nom_categorie,
    parent_category_id   as categorie_parent_id
from {{ source('catalogue', 'categories') }}

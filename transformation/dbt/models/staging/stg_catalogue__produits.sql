-- M3 · Staging du catalogue produit (S2).
-- Grain : 1 ligne = 1 produit (product_id unique en source).

select
    product_id        as produit_id,
    sku,
    product_name      as nom_produit,
    category_id       as categorie_id,
    first_listed_on   as date_referencement
from {{ source('catalogue', 'products') }}

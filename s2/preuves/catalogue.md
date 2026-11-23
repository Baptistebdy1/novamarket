# S2 M1 · Catalogue

J’ai repris les codes produit déjà présents dans les lignes de commande. Une ligne de `categories.csv` décrit une catégorie. Une catégorie peut avoir un parent ou être une racine. Une ligne de `products.csv` décrit une fiche produit, avec une catégorie et un SKU. Une catégorie peut donc regrouper plusieurs produits. Chaque ligne d’article S1 doit retrouver une seule fiche produit.

J’ai importé les catégories avant les produits. La clé primaire de chaque table garantit l’unicité de son code, et le SKU est unique dans le catalogue. La clé étrangère sur `order_items.product_id` vérifie aussi les anciennes lignes de S1 avant la validation de l’import.

| Source | Brut | Intégré | Rejeté |
| --- | ---: | ---: | ---: |
| Catégories | 10 | 10 | 0 |
| Produits | 25 | 24 | 1 |

| Anomalie ou contrôle | Résultat | Décision |
| --- | --- | --- |
| Doublon exact de la fiche produit `3`, SKU `NM-003` | Deux fiches identiques en réception. | Garder une fiche et consigner l’autre dans `qualite.rejets`. |
| Catégories et produits référencés | Les clés étrangères ont validé les liens de parenté et les catégories des produits. | Conserver les contraintes dans les tables métier. |
| Couverture de S1 | 800 lignes d’articles, 24 codes utilisés, 0 ligne sans produit. | Ajouter la clé étrangère produit à la table S1. |
| Dates de l’article `6` | Première commande le 1er septembre 2026. Mise en vente déclarée le 15 septembre. Six lignes précèdent cette date, tous statuts confondus. | Signaler l’écart et conserver les valeurs sources. Les fichiers ne permettent pas de choisir quelle date corriger. |

Le contrôle de reprise retrouve les **2 rejets S1**. Le journal contient aussi le rejet de la fiche produit S2, soit **3 rejets au total**.

[Import](../sql/01_catalogue.sql) · [Contrôles](../sql/02_controles_catalogue.sql)

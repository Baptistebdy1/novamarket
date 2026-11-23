# Bilan du chargement PostgreSQL S1

La connexion à la base `novamarket` avec l’utilisateur `atelier` a été vérifiée. Les scripts de création, de réception et d’intégration se sont tous terminés par `COMMIT`.

## Volumes constatés

| Source | Brut | Intégré | Rejeté |
| --- | ---: | ---: | ---: |
| `customers.csv` | 180 | 180 | 0 |
| `orders.csv` | 400 | 400 | 0 |
| `order_items.csv` | 802 | 800 | 2 |
| `payments.ndjson` | 480 | 480 | 0 |

## Journal des rejets

| Source | Identifiant | Commande référencée | Motif |
| --- | ---: | ---: | --- |
| `order_items.csv` | 7 | 4 | Doublon exact. Une occurrence est intégrée. |
| `order_items.csv` | 801 | 9999 | Commande orpheline. |

Les contrôles avant validation ont confirmé que, pour chaque source, le total brut est égal à la somme des volumes intégrés et rejetés et que chaque commande intégrée contient au moins une ligne d’article.

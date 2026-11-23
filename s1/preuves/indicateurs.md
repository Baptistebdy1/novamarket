# Indicateurs commerciaux NovaMarket S1

Résultats vérifiés dans PostgreSQL sur les données intégrées lors de M2. Les requêtes figurent dans [04_indicateurs.sql](../sql/04_indicateurs.sql).

| Indicateur | Résultat |
| --- | ---: |
| Commandes terminées (`completed`) | 320 |
| Commandes en attente (`pending`) | 40 |
| Commandes annulées (`cancelled`) | 40 |
| Clients sans commande, tous statuts confondus | 30 |
| Chiffre d’affaires des commandes terminées | 2 621 000 centimes (26 210 €) |
| Panier moyen des commandes terminées | 8 190,625 centimes (81,91 € arrondis) |

Le montant d’une ligne est sa quantité multipliée par le prix unitaire de la transaction. Le chiffre d’affaires additionne les lignes des commandes terminées. Le panier moyen utilise une ligne par commande terminée et un dénominateur de 320 commandes. La vérification donne 2 621 000 ÷ 320 = 8 190,625 centimes.

## Rapprochement par commande

Les lignes d’articles et les paiements `captured` sont agrégés séparément par commande. Une commande sans paiement encaissé a un montant encaissé de zéro. L’écart correspond au montant encaissé moins le montant des articles.

| Statut de commande | Montant des articles (centimes) | Encaissé (centimes) | Écart (centimes) | Commandes en écart |
| --- | ---: | ---: | ---: | ---: |
| `cancelled` | 328 375 | 328 375 | 0 | 0 |
| `completed` | 2 621 000 | 2 621 000 | 0 | 0 |
| `pending` | 322 375 | 0 | −322 375 | 40 |

Le rapprochement confirme l’égalité pour chacune des commandes terminées. Les paiements encaissés des commandes annulées sont conservés dans le rapprochement. Les sources ne renseignent aucun remboursement.

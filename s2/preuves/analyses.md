# S2 M2 · Analyses des ventes

Le périmètre reste celui de S1 : commandes terminées, montants en centimes et prix de la transaction. Les ventes simulées du benchmark sont dans une autre table. Les chiffres ci-dessous ont été obtenus en exécutant les requêtes dans PostgreSQL embarqué.

## Classer avec RANK

Pour les produits, la CTE calcule d’abord une ligne par produit. Le rang recommence dans chaque catégorie avec `PARTITION BY category_id`. Le rang dépend uniquement du chiffre d’affaires. L’identifiant sert à stabiliser l’affichage. Un montant égal donne le même rang, puis `RANK` laisse un trou.

| Catégorie | Produit au rang 1 | CA en centimes |
| --- | --- | ---: |
| Rangement | 2 | 58 500 |
| Outillage | 8 | 117 000 |
| Cuisine | 11 | 151 875 |
| Jardin | 14 | 182 250 |
| Randonnée | 20 | 243 000 |
| Jeux de table | 23 | 273 375 |

Le classement client porte sur les **120 clients avec au moins une commande terminée**. Il est global. Les clients `9`, `33` et `57` sont premiers ex æquo à **36 375 centimes** chacun. Les clients suivants ont le rang 4.

### Effet du doublon du catalogue

| Produit | CA et rang avec le catalogue | CA et rang avec la réception brute |
| --- | --- | --- |
| 3 | 23 625 centimes, rang 4 | 47 250 centimes, rang 3 |
| 1 | 32 500 centimes, rang 3 | 32 500 centimes, rang 4 |

La fiche `3` est présente deux fois dans la réception. Chaque ligne de vente de ce produit est donc jointe avec deux fiches. Cela double son montant et modifie aussi le rang du produit `1`, dont le montant reste identique.

## Comparer les mois avec LAG et LEAD

La CTE `mois` construit le calendrier entre les dates extrêmes de la source. La CTE `totaux` donne **une ligne par mois**, y compris pour un mois dont le CA serait nul. `LAG` lit le mois précédent et `LEAD` le suivant. Au début et à la fin de la série, le voisin absent vaut `NULL`.

| Mois de 2026 | Couverture | CA en centimes | Précédent | Variation | Suivant |
| --- | --- | ---: | ---: | ---: | ---: |
| Septembre | Mois entier | 971 750 | — | — | 1 026 125 |
| Octobre | Mois entier | 1 026 125 | 971 750 | +54 375 | 623 125 |
| Novembre | Du 1er au 19 | 623 125 | 1 026 125 | −403 000 | — |

Octobre dépasse septembre de **543,75 €**. La baisse de novembre compare 19 jours à un mois entier. Elle ne suffit pas à conclure à une baisse mensuelle. La couverture se base sur les bornes observées dans le fichier, et ne garantit pas l’exhaustivité de la source. La somme des trois mois retrouve le CA S1 de **2 621 000 centimes**.

## Approfondissements

`NTILE(4)` découpe les 120 clients classés en quatre groupes de 30. L’identifiant départage les montants identiques pour donner un résultat stable. Deux clients à égalité peuvent donc être dans deux groupes différents, notamment à 20 625 et 16 750 centimes.

| Groupe | Clients | CA du groupe en centimes |
| ---: | ---: | ---: |
| 1 | 30 | 927 750 |
| 2 | 30 | 711 000 |
| 3 | 30 | 569 125 |
| 4 | 30 | 413 125 |

La CTE récursive suit les parents de chaque catégorie jusqu’à la racine. La liste des catégories déjà visitées permet d’arrêter la remontée si un cycle se répète. Les contrôles donnent **0 cycle et 0 catégorie sans racine**. Le CA est de **1 796 625 centimes** pour Loisirs et **824 375 centimes** pour Maison. Une ligne article est comptée une fois, dans sa famille racine. Les deux familles retrouvent le CA S1.

[Analyses](../sql/03_analyses.sql) · [Compléments](../sql/04_complements.sql)

# S4 · Chargement PostgreSQL et chaîne dbt — preuves

Toutes les mesures ont été faites le 25/11/2026 sur le PostgreSQL 17 du Compose (port 15432), avec dbt-core 1.9.4 et dbt-postgres 1.9.0 dans le service `dbt`.

## M1 · Chargeur Python

### Schéma et clé retenus

Les données de l'API sont externes. On les range dans un schéma séparé `fournisseur` pour ne pas les mélanger avec les tables commerciales de `public`.

| Table | Rôle | Clé |
| --- | --- | --- |
| `fournisseur.offres_observations` | Une offre d'un fournisseur observée à une date | `(supplier_id, offer_id, observed_on)` |
| `fournisseur.fournisseurs` | Référentiel F01, F02 et F03 (contrat S3) | `supplier_id` |
| `fournisseur.lots` | Bilan de chaque exécution, y compris les échecs | `lot_id` |
| `fournisseur.rejets_chargement` | Ligne refusée, avec son motif et le texte brut | `(lot_id, ligne)` |

**Pourquoi ce grain ?** En S3, la clé `(supplier_id, offer_id)` servait à détecter les doublons dans une seule collecte. En base, une même offre sera observée plusieurs jours avec des prix différents. En ajoutant `observed_on` à la clé, on garde l'historique sans créer de doublon. Rejouer le même fichier retombe sur les mêmes clés.

**Contrôles avant l'écriture :** JSON lisible, 7 champs présents, identifiants non vides, fournisseur connu, produit présent dans `public.products`, prix et stock entiers ≥ 0 (`"625"` est converti en entier, `-5`, `6.5` et `"inconnu"` sont refusés), devise `EUR`, date ISO stricte et pas dans le futur, et pas deux fois la même clé dans le lot. La base vérifie aussi des contraintes `CHECK` et `FOREIGN KEY` en deuxième filet de sécurité.

**Écriture :** une seule transaction par lot. La requête `INSERT … ON CONFLICT DO UPDATE … WHERE … IS DISTINCT FROM` reprend le principe de `exemple.py`. Une ligne identique n'est pas réécrite. `RETURNING (xmax = 0)` permet de distinguer une insertion d'une mise à jour.

### Exécutions sur `ingestion/data/valid/offres.jsonl` (sha256 `8dfc690a85ff…`)

| # | Commande | Statut | Lues | Insérées | Mises à jour | Réutilisées | Rejetées | Offres en base après |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | `--panne-apres 5` sur une base vierge | annulé (code 1) | 5 | 0 | 0 | 0 | 0 | **0** |
| 2 | premier chargement | validé | 20 | 20 | 0 | 0 | 0 | 20 |
| 3 | rejeu du même fichier | validé | 20 | 0 | 0 | **20** | 0 | **20** |
| 4 | fichier `secours/offres.jsonl` | validé | 20 | 0 | 0 | 20 | 0 | 20 |
| 5 | sans `NOVAMARKET_DSN` | refus immédiat (code 1) | — | — | — | — | — | 20 |

- **Atomicité (1)** : la panne survient après 5 upserts. Le `ROLLBACK` annule tout, y compris la création des tables. Le lot reste tracé avec le statut `annule` et le message d'erreur, dans une petite transaction séparée qui ne contient aucune offre.
- **Idempotence (3)** : le deuxième passage ne crée et ne modifie rien. L'empreinte sha256 prouve qu'il s'agit du même fichier.
- **(4)** : le fichier de secours a une autre empreinte (ordre des clés JSON différent) mais contient les mêmes 20 observations, donc 20 réutilisées.

### Essai des rejets et des mises à jour ([essais/anomalies.jsonl](essais/anomalies.jsonl))

L'essai est fait sur une copie temporaire `novamarket_essai` (`CREATE DATABASE … TEMPLATE novamarket`), supprimée ensuite, pour ne pas mettre de fausses offres dans la vraie base.

Bilan : **12 lues = 2 insérées + 1 mise à jour + 1 réutilisée + 8 rejetées**.

| Ligne | Cas | Résultat |
| ---: | --- | --- |
| 1 | `O001` du 24/11 avec un nouveau prix (599) | mise à jour (`lot_maj` renseigné) |
| 2 | `O001` du 25/11 | insérée : deuxième observation de la même offre |
| 3 | `O002` identique | réutilisée |
| 4 | produit 9999 | `produit_inconnu` |
| 5 | fournisseur F09 | `fournisseur_inconnu` |
| 6 | USD | `devise_invalide` |
| 7 | prix -5 | `prix_invalide` |
| 8 | date `24/11/2026` | `date_invalide` |
| 9 | date 2099-01-01 | `date_future` |
| 10 | `"product_id": "7"`, `"price_cents": "1500"` | insérée après conversion |
| 11 | même clé que la ligne 10 | `doublon_dans_le_lot` |
| 12 | JSON tronqué | `json_invalide` |

Limite : la règle `date_future` dépend du jour du chargement. Le même fichier rejoué plus tard pourrait donc accepter la ligne 9.

## M2 à M4 · Projet dbt

```
source fournisseur.offres_observations ─► stg_fournisseur__offres   (view) ─┐
source public.products                 ─► stg_catalogue__produits   (view) ─┼─► int_offres_enrichies (ephemeral) ─► mart_offres_produit_jour (table)
source public.categories               ─► stg_catalogue__categories (view) ─┘
```

| Couche | Modèle | Grain | Matérialisation et justification |
| --- | --- | --- | --- |
| staging | `stg_fournisseur__offres` | 1 offre × 1 date (inchangé) | vue : renommage et typage seulement, toujours à jour |
| staging | `stg_catalogue__produits`, `stg_catalogue__categories` | 1 produit, 1 catégorie | vue |
| intermediate | `int_offres_enrichies` | 1 offre × 1 date (inchangé) | éphémère : règle réutilisable (jointure catalogue et rang de prix), sans objet de plus en base |
| marts | `mart_offres_produit_jour` | 1 produit × 1 date | table : résultat publié pour l'analyse et la BI en S6 |

**Jointures sans multiplication :** `produit_id` et `categorie_id` sont uniques (tests `unique`). Chaque offre trouve donc au plus un produit et une catégorie. L'`INNER JOIN` vers les produits ne perd aucune ligne, car le chargeur impose déjà la clé étrangère.

Les schémas créés s'appellent `dbt_dev_staging` et `dbt_dev_marts`. Par défaut, dbt ajoute le schéma du profil (`dbt_dev`) devant le schéma personnalisé.

## M5 · Vérification de la chaîne

Sorties complètes : [dbt-compile](preuves/dbt-compile.txt), [dbt-run](preuves/dbt-run.txt) et [dbt-build](preuves/dbt-build.txt).

- `dbt compile` : 5 modèles, 25 tests, 5 sources.
- `dbt run` : `PASS=4` (3 vues et 1 table ; le modèle éphémère ne crée rien en base).
- `dbt build` : `PASS=29` (4 modèles et 25 tests).

| Étape | Lignes | Stock total |
| --- | ---: | ---: |
| `fournisseur.offres_observations` (source) | 20 | 488 |
| `dbt_dev_staging.stg_fournisseur__offres` | 20 | 488 |
| `dbt_dev_marts.mart_offres_produit_jour` | 20 lignes, `sum(nb_offres)` = 20 | 488 |

Le test singulier `assert_pas_de_multiplication` fait cette comparaison automatiquement à chaque `dbt build`.

**Écart attendu :** le mart agrège par produit et par jour, mais il a autant de lignes que la source. En effet, dans le lot S3, chaque produit n'est proposé que par un seul fournisseur, le 24/11. Sur la base d'essai (`O001` et `O096` sur deux jours, 22 observations), le mart compte aussi 22 lignes et distingue bien le produit 1 au 24/11 (5,99 €) et au 25/11 (6,10 €). `dbt build` passe aussi à 29/29.

**SQL compilé inspecté** (`target/compiled/.../mart_offres_produit_jour.sql`) : `ref('int_offres_enrichies')` devient une CTE `__dbt__cte__int_offres_enrichies` injectée en tête de la requête du mart. Les `ref()` du staging deviennent `"novamarket"."dbt_dev_staging"."stg_…"`. C'est la différence concrète entre un modèle éphémère et une vue.

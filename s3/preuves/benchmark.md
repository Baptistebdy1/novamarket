# S2 M3 · Benchmark PostgreSQL

Le générateur fourni a produit **10 000 000 ventes simulées** dans `benchmark.benchmark_sales`. La table occupe **498 MB** selon PostgreSQL. Elle reste indépendante de la base commerciale.

## Comment j’ai fait la comparaison

J’ai mesuré le même `SELECT SUM(amount_cents)` pour deux magasins. Le magasin `42` retient **100 lignes (0,001 %)**, alors que le magasin `1` en retient **9 500 000 (95 %)**. J’ai ajouté un index B-tree sur `store_id`, la colonne utilisée dans les deux filtres.

Les mesures ont été faites sur **PostgreSQL 18.6 embarqué (PGlite 0.5.10, WebAssembly)**, sur macOS ARM64, avec `shared_buffers = 128MB`, des blocs de 8192 octets et le parallélisme désactivé. Le script effectue un premier passage, puis trois répétitions. La médiane utilise seulement les trois répétitions. Le comptage initial et les essais précédents peuvent réchauffer les caches. Le premier passage représente donc le premier essai de la phase, sans garantie de cache froid.

## Mesures avant et après l’index

Les durées proviennent de la ligne `Execution Time` des plans. Elles sont en millisecondes.

| Magasin | Phase | Accès choisi | Premier essai | Répétitions | Médiane |
| ---: | --- | --- | ---: | --- | ---: |
| 42 | Avant | Seq Scan | 435,233 | 420,786 / 420,008 / 429,939 | **420,786** |
| 42 | Après | Index Scan | 0,393 | 0,098 / 0,091 / 0,094 | **0,094** |
| 1 | Avant | Seq Scan | 1 917,121 | 1 898,531 / 1 908,083 / 1 890,139 | **1 898,531** |
| 1 | Après | Seq Scan | 1 939,387 | 1 900,230 / 1 907,545 / 1 900,733 | **1 900,733** |

La création de l’index a pris **2 924 ms**, mesurés à part. Il occupe **69 279 744 octets (66 MB)**. Le script annule la création à la fin pour permettre de refaire les mesures depuis le même jeu sans index.

### Ce que je retiens

- Pour le magasin 42, l’index donne accès à une petite fraction de la table. Sur la répétition 2, le parcours séquentiel a touché 63 744 blocs (490 `hit`, 63 254 `read`). Le parcours par index en a trouvé 103 dans les tampons (`shared hit`). Le résultat de la requête reste le même.
- Pour le magasin 1, PostgreSQL garde le parcours séquentiel après la création de l’index. Il doit récupérer presque toute la table. Chercher les lignes une par une par l’index coûterait plus de travail selon le planificateur. La petite différence de durée entre les médianes ne permet pas de conclure à un ralentissement dû à l’index.
- Pour le magasin 42, le plan estime 371 lignes, alors que 100 correspondent. Cela donne une surestimation de 3,71 fois. Le volume reste faible à l’échelle de la table et l’index est quand même choisi. Les valeurs `cost` sont des estimations du planificateur et `Execution Time` est un temps mesuré.
- Un bloc `read` a été chargé dans les tampons de PostgreSQL. Le système peut déjà l’avoir en cache. Les temps et les plans peuvent varier dans Docker en PostgreSQL 17 selon la machine, le cache et les statistiques.

[16 plans complets](plans-postgresql.txt) · [Script de mesure et index](../sql/01_benchmark.sql)

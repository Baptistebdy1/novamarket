# NovaMarket

Projet PostgreSQL du TP d’ingénierie des données.

## Séance 1

- [Sources brutes](s1/donnees/) et [dictionnaire](s1/SOURCES.md).
- [Exemple d’import](s1/exemple/import.sql) fourni avec le TP.
- [Scripts SQL du groupe](s1/sql/) pour le schéma, l’import, les contrôles et les indicateurs.
- [Schéma relationnel annoté](s1/preuves/schema-relationnel.md) et [preuves du TP](s1/preuves/).

Le périmètre obligatoire couvre les clients, les commandes, les lignes d’articles et les paiements. Les fichiers sources restent intacts. L’import distingue la réception, les rejets et l’intégration métier.

## Démarrage

Depuis ce dossier, démarrer PostgreSQL. Voir le [guide de démarrage](s1/DEMARRAGE.md) et la [référence SQL](REFERENCE_SQL.md).

```bash
docker compose up -d --wait postgres
```

Sur une base neuve, créer les tables, charger les sources en réception et intégrer les lignes valides.

```bash
docker compose exec -T postgres psql -X -v ON_ERROR_STOP=1 -U atelier -d novamarket \
  -f /s1/sql/01_schema.sql -f /s1/sql/02_reception.sql -f /s1/sql/03_integration.sql
```

Pour reprendre le travail avec le volume existant, relancer les indicateurs et les contrôles en lecture seule.

```bash
docker compose exec -T postgres psql -X -v ON_ERROR_STOP=1 -U atelier -d novamarket \
  -f /s1/sql/04_indicateurs.sql -f /s1/sql/05_anomalies.sql
```

## État de la S1

- **M1** · [Schéma relationnel annoté](s1/preuves/schema-relationnel.md).
- **M2** · [Bilan d’import](s1/preuves/bilan-import.md) validé dans PostgreSQL. Le contrôle de reprise doit afficher 180 clients, 400 commandes, 800 articles, 480 paiements, 2 rejets et 0 commande sans article.
- **M3** · [Indicateurs et rapprochement](s1/preuves/indicateurs.md) confirmés par l’exécution du script dans PostgreSQL.
- **M4** · [Tableau des anomalies](s1/preuves/anomalies.md) confirmé par l’exécution du script dans PostgreSQL.
- **M5** · Les scripts de reprise ont été exécutés sur le volume PostgreSQL. Les contrôles ont confirmé les indicateurs, les volumes et l’absence de commande sans article.

Les scripts de création et d’intégration S1 servent au premier chargement. Les contrôles d’import couvrent les anomalies observées. Les remboursements ne sont pas renseignés par les sources.

## Séance 2

| Mission | Preuves |
| --- | --- |
| M1 · Intégrer le catalogue | [Scripts d’import et contrôles](s2/sql/) · [Bilan du catalogue](s2/preuves/catalogue.md) |
| M2 · Écrire les analyses avancées | [Requêtes](s2/sql/03_analyses.sql) · [Résultats et limites](s2/preuves/analyses.md) |
| M3 · Mesurer le benchmark | [Script de mesure et index](s3/sql/01_benchmark.sql) · [Mesures et interprétation](s3/preuves/benchmark.md) · [Plans complets](s3/preuves/plans-postgresql.txt) |
| M4 · Préparer le rendu | Scripts S1 et S2, preuves et commandes de reprise dans ce dépôt |

### Charger le catalogue

Depuis la racine, sur la même base après l’import S1, exécuter ce chargement une seule fois.

```bash
docker compose exec -T postgres mkdir -p /tmp/novamarket-s2
docker compose cp s2/donnees/. postgres:/tmp/novamarket-s2/
docker compose exec -T postgres psql -X -v ON_ERROR_STOP=1 -U atelier -d novamarket < s2/sql/01_catalogue.sql
```

Les contrôles et analyses peuvent être relancés. Le bilan attendu est de 10 catégories, 24 produits, 1 rejet de catalogue et 0 article S1 sans produit.

```bash
docker compose exec -T postgres psql -X -v ON_ERROR_STOP=1 -U atelier -d novamarket < s2/sql/02_controles_catalogue.sql
docker compose exec -T postgres psql -X -v ON_ERROR_STOP=1 -U atelier -d novamarket < s2/sql/03_analyses.sql
docker compose exec -T postgres psql -X -v ON_ERROR_STOP=1 -U atelier -d novamarket < s2/sql/04_complements.sql
```

### Refaire le benchmark

Générer les 10 millions de lignes une seule fois si le schéma `benchmark` est absent. Cette opération ajoute un jeu de ventes simulées séparé.

```bash
docker compose exec -T postgres psql -X -v ON_ERROR_STOP=1 -U atelier -d novamarket < s3/generer.sql
```

Relancer ensuite les mesures avec ce script. Il vérifie le volume et exige un départ sans index sur la table de benchmark. Il annule son index à la fin. La sortie est enregistrée dans `plans-docker.txt` dans le dossier temporaire.

```bash
docker compose exec -T postgres psql -X -v ON_ERROR_STOP=1 -U atelier -d novamarket \
  < s3/sql/01_benchmark.sql > /tmp/plans-docker.txt
```

Deux pièges à retenir. Un index peut être ignoré si le filtre sélectionne presque toute la table. Une jointure directe des articles et des paiements peut répéter les montants. On agrège les deux tables séparément avant de les joindre par commande.

Les scripts commerciaux et les 10 millions de lignes du benchmark ont été vérifiés sur PostgreSQL 18.6 embarqué. Les plans fournis correspondent à ce moteur. La reprise dans Docker utilise PostgreSQL 17 et peut donner d’autres temps ou plans. Voir le [guide de sauvegarde](SAUVEGARDE_SQL.md).

Pour le rendu, communiquer l’URL du dépôt privé et le SHA du commit publié. `git log -1 --oneline` permet de retrouver le dernier commit du dossier.

## Séance 3 · Ingestion asynchrone

Le TP S3 ajoute une API locale `fournisseur` et un collecteur Python dans [ingestion/](ingestion/README.md). Le benchmark du rendu S2 reste rangé dans `s3/`.

- [Contrat HTTP, essais et bilan](ingestion/preuves.md).
- [Offres valides à reprendre en S4](ingestion/data/valid/offres.jsonl).

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

## État du projet

- **M1** · [Schéma relationnel annoté](s1/preuves/schema-relationnel.md).
- **M2** · [Bilan d’import](s1/preuves/bilan-import.md) validé dans PostgreSQL. Le contrôle de reprise doit afficher 180 clients, 400 commandes, 800 articles, 480 paiements, 2 rejets et 0 commande sans article.
- **M3** · [Indicateurs et rapprochement](s1/preuves/indicateurs.md) confirmés par l’exécution du script dans PostgreSQL.
- **M4** · [Tableau des anomalies](s1/preuves/anomalies.md) confirmé par l’exécution du script dans PostgreSQL.
- **M5** · Les scripts de reprise ont été exécutés sur le volume PostgreSQL. Les contrôles ont confirmé les indicateurs, les volumes et l’absence de commande sans article.

Les scripts de création et d’intégration servent au premier chargement. Les contrôles d’import couvrent les anomalies observées dans le périmètre S1. Le catalogue et les remboursements sont hors du périmètre traité. Le dépôt GitHub privé et l’identification du commit sont à effectuer avant le rendu collectif de fin de S2.

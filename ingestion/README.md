# S3 · Ingestion asynchrone

## Préparer

Depuis `novamarket/`, avec Python **3.12** disponible :

```bash
python3.12 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements-v3.txt
docker compose up -d --build --wait fournisseur
python ingestion/tests/disponibilite.py
python ingestion/exemple.py
```

Avec `uv`, on peut utiliser `uv venv --python 3.12 --seed .venv` en l'absence de cette version locale. Ne pas distribuer le venv. L'exemple sur des cuves illustre session, semaphore, timeout, retry, logger et gather. Développer le collecteur fournisseur dans `ingestion/src/`.

## Contrat HTTP

`GET /health` retourne `{"status":"ok"}`. `GET /offers?page=1&scenario=atelier&run=groupe01-essai01` retourne `page`, `total_pages`, `next_page` (nul à la fin) et une liste `items`. Exemple de sondage indépendant du collecteur :

```bash
curl -fsS 'http://127.0.0.1:18080/offers?page=1&scenario=clean&run=sonde'
```

| Champ | Contrat |
| --- | --- |
| `offer_id`, `supplier_id` | Identifiants texte stables. Les fournisseurs de simulation sont F01, F02 et F03. |
| `product_id` | Entier parmi les produits du catalogue S2. |
| `price_cents`, `available_units` | Entiers non négatifs, centimes et unités; `currency` vaut EUR. |
| `observed_on` | Jour ISO AAAA-MM-JJ. |

Six pages de quatre enregistrements. Choisir un `run` neuf pour rejouer les premières tentatives. `clean` fournit le contrôle sans fautes. `atelier` injecte réponses transitoires (429 avec `Retry-After`, JSON invalide, délai) et anomalies métier. `panne` produit une erreur permanente. La latence de base se règle par `NOVAMARKET_API_LATENCY`. Comparer les collectes avec le même scénario et la même latence. Borner le nombre d'essais et la concurrence. Compter les essais HTTP et les lignes séparément.

## Sorties et reprise

Une exécution complète produit des fichiers UTF-8 JSONL à raison d'un objet par ligne. `data/raw/` garde les pages reçues; `data/valid/offres.jsonl` conserve les champs du contrat; `data/rejected/` conserve page, position, motif et objet brut. Le bilan distingue pages reçues, lignes examinées, valides et rejetées, reprises et durée. Prévoir un nouveau répertoire par essai ou un archivage explicite. Un lot incomplet ne doit pas être publié comme valide. En cas de besoin, la séance S4 fournit une entrée de secours sous `transformation/secours/offres.jsonl`.

Si le port est pris, ajuster `NOVAMARKET_API_PORT` à la fois pour Compose et le shell. Examiner `docker compose logs fournisseur`. L'API fonctionne seule si les travaux SQL S2 sont incomplets. Le formateur peut préparer le catalogue canonique pour la validation et le chargement suivants.

## Exécuter notre collecteur

Depuis la racine, après le démarrage de l’API et l’activation du venv, rejouer les scénarios dans un dossier temporaire. Cela permet de vérifier le TP tout en gardant le fichier destiné à S4.

```bash
essais=$(mktemp -d)
python -m ingestion.src.collecteur --scenario clean --concurrence 1 --data "$essais"
python -m ingestion.src.collecteur --scenario clean --concurrence 3 --data "$essais"
python -m ingestion.src.collecteur --scenario atelier --data "$essais"
python -m ingestion.src.collecteur --scenario panne --data "$essais"
```

Le dernier appel doit terminer avec le code **1** et afficher `"publie": false`. Le dossier temporaire doit alors contenir le fichier des **20 offres de l’atelier**.

Par défaut, le programme génère un nouvel identifiant d’essai à chaque lancement. On peut fixer `--run` soi-même pour retrouver les traces, avec un identifiant inédit à chaque exécution. La limite est de **3 appels HTTP en cours** par défaut, avec **0,8 s par tentative** et **3 tentatives au maximum par page**. Les options `--concurrence`, `--timeout`, `--tentatives` et `--data` permettent de reproduire les essais dans un dossier de travail distinct.

Chaque essai produit `raw/<run>.jsonl`, `rejected/<run>.jsonl` et `logs/<run>.jsonl` sous `ingestion/data/`. Le fichier brut garde le statut et le corps des réponses reçues, y compris le JSON illisible. Un timeout sans réponse apparaît dans le journal. Le bilan sépare les appels tentés, les reprises et les offres examinées.

Un lot complet remplace `valid/offres.jsonl` en une seule opération dans le répertoire de données choisi. Pour régénérer le fichier à l’emplacement prévu pour S4, lancer `python -m ingestion.src.collecteur --scenario atelier` sans l’option `--data`.

## Lire le code

- [collecteur.py](src/collecteur.py) découvre la pagination, lance les appels et décide quand réessayer.
- [validation.py](src/validation.py) applique les règles métier et donne un motif pour chaque rejet.
- [journalisation.py](src/journalisation.py) écrit les traces et publie le fichier valide.

Tests unitaires :

```bash
python -m unittest discover -s ingestion/tests -p 'test_*.py'
```

[Contrat appliqué et preuves des essais](preuves.md)

# S3 · Contrat et bilan de collecte

## M1 · Contrat appliqué

L’API locale répond à `GET /health` avec `{"status":"ok"}`. On interroge ensuite `GET /offers` avec le numéro de page, le scénario et le nom de l’essai. La première réponse donne le nombre de pages. Le contrat annonce six pages de quatre offres et `next_page` vaut `null` à la fin. Le collecteur vérifie le numéro, le nombre total et le lien vers la page suivante à chaque réponse.

Extrait de la page 1 en mode `clean`, avec une seule des quatre offres fictives :

```json
{
  "page": 1,
  "total_pages": 6,
  "next_page": 2,
  "items": [
    {
      "offer_id": "O001", "supplier_id": "F01", "product_id": 1,
      "price_cents": 625, "currency": "EUR", "available_units": 2,
      "observed_on": "2026-11-24"
    }
  ]
}
```

Une ligne représente une offre fournisseur. J’ai choisi le couple `supplier_id` + `offer_id` comme clé métier pour distinguer deux fournisseurs qui utiliseraient le même numéro d’offre. Les identifiants fournisseur et offre sont des chaînes non vides. Le produit doit exister dans le catalogue S2. Le prix en centimes et le stock doivent être des entiers positifs ou nuls. La devise est `EUR` et la date doit respecter le format `AAAA-MM-JJ`. Après la collecte, on contrôle les offres par numéro de page. Ainsi, la première occurrence conforme est toujours la même, quel que soit l’ordre d’arrivée des réponses.

## M2 · Collecte séquentielle et concurrente

J’ai utilisé la même API simulée et la même latence de base de 0,12 s pour les deux essais `clean`. Les deux produisent le même fichier. Le premier appel découvre la pagination. Ensuite, le sémaphore autorise jusqu’à trois requêtes en cours. Quand une tâche attend une réponse HTTP, `await` permet aux autres d’avancer. C’est ce chevauchement des attentes qui explique le gain de temps.

| Essai | Pages reçues | Offres vues | Conformes | Rejets | Appels | Reprises | Pic d’appels en cours | Durée | Publié |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `clean`, limite 1 | 6 | 24 | 24 | 0 | 6 | 0 | 1 | 0,749 s | Oui |
| `clean`, limite 3 | 6 | 24 | 24 | 0 | 6 | 0 | 3 | 0,374 s | Oui |
| `atelier`, limite 3 | 6 | 24 | 20 | 4 | 9 | 3 | 3 | 1,374 s | Oui |
| `panne`, limite 3 | 5 | 20 | 20 | 0 | 8 | 2 | 3 | 0,922 s | Non |

Ces mesures correspondent à un passage par essai. Les échanges ont utilisé le client `aiohttp` 3.13.5 et le serveur HTTP fourni, reliés par des sockets locaux avec Python 3.12.13. Les valeurs peuvent varier dans Docker, dont le démarrage reste à vérifier sur cette machine.

## M3 · Incidents et reprise

Ces lignes résument les incidents enregistrés dans le journal d’`atelier`.

| Page | Premier incident | Attente avant le nouvel appel | Résultat |
| ---: | --- | ---: | --- |
| 2 | HTTP 429 avec `Retry-After` | 1 s | Réussite au deuxième essai |
| 3 | HTTP 200 avec un JSON illisible | 0,1 s | Réussite au deuxième essai |
| 4 | Délai de 0,8 s dépassé | 0,1 s | Réussite au deuxième essai |

Le sémaphore est libéré avant l’attente entre deux tentatives, ce qui laisse les autres pages avancer. Une réponse HTTP 200 peut contenir un JSON illisible. Même si le JSON est lisible, les offres passent encore par les contrôles métier de M4.

Dans `panne`, la page 6 renvoie **503** sur les trois tentatives. Le bilan indique qu’elle manque et qu’aucun lot n’a été publié. J’ai vérifié que le contenu du fichier valide est resté exactement celui de l’essai `atelier`.

## M4 · Rejets et sortie S4

| Page et position | Motif |
| --- | --- |
| 2, offre 1 | `supplier_id` absent |
| 3, offre 2 | Prix fourni sous forme de texte |
| 5, offre 1 | Produit `9999` absent du catalogue |
| 6, offre 4 | Offre `O001` du fournisseur `F01` déjà retenue en page 1 |

Le bilan vérifie **24 vues = 20 conformes + 4 rejetées** pour `atelier`. Les corps reçus, les rejets et les événements sont enregistrés séparément en JSONL. Le [fichier valide pour S4](data/valid/offres.jsonl) contient les 20 offres conformes. Les journaux par essai se régénèrent avec les commandes du [README](README.md).

# Analyse des anomalies NovaMarket S1

Les requêtes de détection et de vérification figurent dans [05_anomalies.sql](../sql/05_anomalies.sql). L’exécution dans PostgreSQL a confirmé les anomalies et les montants du tableau, ainsi que 180 clients, 400 commandes, 800 lignes d’articles, 480 paiements, 2 rejets et 0 commande sans article. Les totaux de référence de M3 ont été reproduits sur les sources après application des rejets.

| Anomalie | Détection | Effet | Décision |
| --- | --- | --- | --- |
| Doublon exact de la ligne d’article `7`, commande `4` | Regrouper les lignes reçues sur toutes leurs colonnes et garder les groupes comptés plus d’une fois. Deux occurrences identiques pour la ligne `7`. | Intégrer les deux occurrences compterait deux fois la quantité et le montant de la ligne. | Intégrer une occurrence et journaliser l’autre comme doublon exact. |
| Ligne d’article `801`, commande `9999` absente | Faire un `LEFT JOIN` vers les commandes reçues et garder les lignes sans correspondance avec `o.order_id IS NULL`. | La ligne ne peut être rattachée à aucune commande métier. | Rejeter la ligne et conserver l’identifiant de la commande dans le journal. |
| Multiplication lors d’une jointure articles–paiements | Joindre directement les articles et les paiements encaissés par commande terminée, puis comparer aux totaux de M3. | La jointure produit 720 lignes. Elle affiche 2 947 250 centimes d’articles et 5 242 000 centimes de paiements, contre 2 621 000 centimes de chaque côté après agrégation correcte. | Agréger chaque source par commande avant de joindre les totaux. |
| Périmètre du chiffre d’affaires selon le statut | Calculer les montants d’articles par statut. On obtient 2 621 000 centimes terminés, 322 375 en attente et 328 375 annulés. | Inclure tous les statuts porte la somme à 3 271 750 centimes, soit 650 750 centimes de plus. | Définir le chiffre d’affaires du TP sur les commandes terminées et présenter le rapprochement des paiements par statut. |

Pour une commande ayant deux lignes d’articles et deux paiements, une jointure directe produit quatre paires. Chaque montant d’article et de paiement est alors répété deux fois.

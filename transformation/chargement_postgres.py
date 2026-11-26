"""S4 · M1 — Chargement des offres fournisseurs valides (S3) dans PostgreSQL.

Ce que fait le programme, dans l'ordre :
1. lire le JSONL validé par le collecteur S3 (une offre par ligne) ;
2. recontrôler chaque ligne (types, date, devise, produit, fournisseur) :
   le chargeur ne fait pas confiance aveuglément à l'étape précédente ;
3. écrire TOUT le lot dans UNE transaction (upsert idempotent) ;
4. produire un bilan : lues / insérées / mises à jour / réutilisées / rejetées.

Choix du grain (décision du groupe) :
    une ligne = une offre d'un fournisseur observée à une date donnée.
    Clé : (supplier_id, offer_id, observed_on).
    -> on peut recevoir la même offre plusieurs jours sans écraser l'historique,
    -> rejouer le même fichier ne crée aucun doublon (même clé = même ligne).

Utilisation (depuis novamarket/, venv S3 activé) :
    export NOVAMARKET_DSN='host=127.0.0.1 port=15432 dbname=novamarket user=atelier'
    # mot de passe via PGPASSFILE ou PGPASSWORD dans le shell, jamais dans le code
    python transformation/chargement_postgres.py
    python transformation/chargement_postgres.py --entree transformation/secours/offres.jsonl
    python transformation/chargement_postgres.py --panne-apres 5   # preuve d'atomicité
"""

import argparse
import hashlib
import json
import os
import sys
from datetime import date, datetime, timezone
from pathlib import Path
from uuid import uuid4

import psycopg

RACINE = Path(__file__).resolve().parents[1]  # dossier novamarket/
ENTREE_PAR_DEFAUT = RACINE / "ingestion/data/valid/offres.jsonl"

# Les 7 champs du contrat HTTP S3 : on refuse toute ligne où il en manque un.
CHAMPS = ("offer_id", "supplier_id", "product_id", "price_cents",
          "currency", "available_units", "observed_on")

# ---------------------------------------------------------------------------
# Schéma cible. On a choisi un schéma séparé "fournisseur" pour ne pas mélanger
# les données externes (API) avec les tables commerciales de S1/S2 (public).
# Tout est en IF NOT EXISTS : le script peut être relancé sans erreur.
# ---------------------------------------------------------------------------
DDL = """
CREATE SCHEMA IF NOT EXISTS fournisseur;

-- Référentiel des fournisseurs connus (contrat API S3 : F01, F02, F03).
-- Sans ce référentiel on ne pourrait pas "contrôler la référence fournisseur".
CREATE TABLE IF NOT EXISTS fournisseur.fournisseurs (
    supplier_id text PRIMARY KEY
);
INSERT INTO fournisseur.fournisseurs (supplier_id)
VALUES ('F01'), ('F02'), ('F03')
ON CONFLICT (supplier_id) DO NOTHING;

-- Journal des lots : une ligne par exécution, y compris les échecs.
CREATE TABLE IF NOT EXISTS fournisseur.lots (
    lot_id         text PRIMARY KEY,
    fichier        text NOT NULL,
    sha256         text NOT NULL,          -- empreinte : prouve que c'est le même fichier au rejeu
    demarre_le     timestamptz NOT NULL,
    termine_le     timestamptz NOT NULL,
    statut         text NOT NULL CHECK (statut IN ('valide', 'annule')),
    lues           integer NOT NULL,
    inserees       integer NOT NULL,
    mises_a_jour   integer NOT NULL,
    reutilisees    integer NOT NULL,       -- déjà présentes et identiques : rien écrit
    rejetees       integer NOT NULL,
    erreur         text
);

-- Table des observations (le grain décrit en tête de fichier).
-- Les contraintes CHECK/FK sont un 2e filet de sécurité après le contrôle Python.
CREATE TABLE IF NOT EXISTS fournisseur.offres_observations (
    supplier_id      text    NOT NULL REFERENCES fournisseur.fournisseurs (supplier_id),
    offer_id         text    NOT NULL,
    observed_on      date    NOT NULL,
    product_id       integer NOT NULL REFERENCES public.products (product_id),
    price_cents      integer NOT NULL CHECK (price_cents >= 0),
    currency         char(3) NOT NULL CHECK (currency = 'EUR'),
    available_units  integer NOT NULL CHECK (available_units >= 0),
    lot_insertion    text    NOT NULL REFERENCES fournisseur.lots (lot_id) DEFERRABLE INITIALLY DEFERRED,
    lot_maj          text    REFERENCES fournisseur.lots (lot_id) DEFERRABLE INITIALLY DEFERRED,
    PRIMARY KEY (supplier_id, offer_id, observed_on)
);

-- Lignes refusées par le chargeur, avec la cause (jamais de rejet silencieux).
CREATE TABLE IF NOT EXISTS fournisseur.rejets_chargement (
    lot_id     text    NOT NULL REFERENCES fournisseur.lots (lot_id) DEFERRABLE INITIALLY DEFERRED,
    ligne      integer NOT NULL,
    motif      text    NOT NULL,
    brut       text    NOT NULL,
    PRIMARY KEY (lot_id, ligne)
);
"""
# Remarque : les FK vers lots sont DEFERRABLE car on écrit la ligne du lot
# à la FIN (quand on connaît les compteurs), mais dans la même transaction.

# Upsert idempotent, même principe que l'exemple des cuves :
# - nouvelle clé           -> INSERT, RETURNING renvoie insere = true
# - clé connue, valeurs ≠  -> UPDATE, RETURNING renvoie insere = false
# - clé connue, identique  -> le WHERE bloque l'UPDATE, RETURNING ne renvoie rien
# (xmax = 0 signifie "ligne créée par cette instruction", astuce PostgreSQL.)
UPSERT = """
INSERT INTO fournisseur.offres_observations AS o
    (supplier_id, offer_id, observed_on, product_id, price_cents,
     currency, available_units, lot_insertion)
VALUES (%(supplier_id)s, %(offer_id)s, %(observed_on)s, %(product_id)s,
        %(price_cents)s, %(currency)s, %(available_units)s, %(lot)s)
ON CONFLICT (supplier_id, offer_id, observed_on) DO UPDATE
SET product_id = excluded.product_id,
    price_cents = excluded.price_cents,
    currency = excluded.currency,
    available_units = excluded.available_units,
    lot_maj = %(lot)s
WHERE (o.product_id, o.price_cents, o.currency, o.available_units)
      IS DISTINCT FROM
      (excluded.product_id, excluded.price_cents, excluded.currency, excluded.available_units)
RETURNING (xmax = 0) AS insere
"""


class PanneSimulee(RuntimeError):
    """Erreur volontaire pour prouver qu'aucune écriture partielle ne reste."""


# ---------------------------------------------------------------------------
# Contrôles d'une ligne
# ---------------------------------------------------------------------------
def entier_positif(valeur):
    """Accepte 625 ou "625" (conversion de type), refuse 6.5, -1, True, "inconnu"."""
    if isinstance(valeur, bool):  # en Python, True est un int : on l'exclut
        return None
    if isinstance(valeur, str) and valeur.strip().isdecimal():
        valeur = int(valeur)
    if isinstance(valeur, int) and valeur >= 0:
        return valeur
    return None


def controler(texte, produits, fournisseurs, aujourd_hui):
    """Retourne (offre_convertie, None) si la ligne est valide, sinon (None, motif)."""
    try:
        brut = json.loads(texte)
    except json.JSONDecodeError:
        return None, "json_invalide"
    if not isinstance(brut, dict):
        return None, "ligne_non_objet"
    manquants = [c for c in CHAMPS if c not in brut]
    if manquants:
        return None, f"champ_manquant:{manquants[0]}"

    # Identifiants texte non vides, nettoyés des espaces.
    ids = {}
    for champ in ("supplier_id", "offer_id"):
        v = brut[champ]
        if not isinstance(v, str) or not v.strip():
            return None, f"identifiant_invalide:{champ}"
        ids[champ] = v.strip()
    if ids["supplier_id"] not in fournisseurs:
        return None, "fournisseur_inconnu"

    produit = entier_positif(brut["product_id"])
    if produit is None or produit not in produits:
        return None, "produit_inconnu"

    prix = entier_positif(brut["price_cents"])
    if prix is None:
        return None, "prix_invalide"
    stock = entier_positif(brut["available_units"])
    if stock is None:
        return None, "stock_invalide"

    # Unité monétaire : le prix est en centimes d'euro, toute autre devise
    # rendrait les comparaisons de prix fausses dans le mart.
    if brut["currency"] != "EUR":
        return None, "devise_invalide"

    # Date ISO stricte (AAAA-MM-JJ) et pas dans le futur.
    try:
        jour = date.fromisoformat(brut["observed_on"])
        if jour.isoformat() != brut["observed_on"]:
            raise ValueError
    except (TypeError, ValueError):
        return None, "date_invalide"
    if jour > aujourd_hui:
        return None, "date_future"

    return {**ids, "product_id": produit, "price_cents": prix, "currency": "EUR",
            "available_units": stock, "observed_on": jour}, None


# ---------------------------------------------------------------------------
# Chargement
# ---------------------------------------------------------------------------
def charger(dsn, entree, panne_apres=None):
    contenu = entree.read_bytes()
    lot = {
        "lot_id": f"lot-{datetime.now(timezone.utc):%Y%m%dT%H%M%S}-{uuid4().hex[:6]}",
        "fichier": str(entree.relative_to(RACINE) if entree.is_relative_to(RACINE) else entree),
        "sha256": hashlib.sha256(contenu).hexdigest(),
        "demarre_le": datetime.now(timezone.utc),
    }
    lignes = contenu.decode("utf-8").splitlines()
    compteurs = dict(lues=0, inserees=0, mises_a_jour=0, reutilisees=0, rejetees=0)

    with psycopg.connect(dsn, connect_timeout=5) as db:
        try:
            # ---- UNE seule transaction pour tout le lot -------------------
            # Si une exception sort de ce bloc, psycopg fait un ROLLBACK :
            # aucune ligne du lot ne reste en base (atomicité).
            with db.transaction():
                db.execute(DDL)
                produits = {r[0] for r in db.execute("SELECT product_id FROM public.products")}
                fournisseurs = {r[0] for r in db.execute("SELECT supplier_id FROM fournisseur.fournisseurs")}
                aujourd_hui = date.today()
                deja_vues = set()  # pour détecter un doublon de clé DANS le même fichier
                rejets = []

                for numero, texte in enumerate(lignes, start=1):
                    if not texte.strip():
                        continue  # ligne vide en fin de fichier : on l'ignore
                    compteurs["lues"] += 1
                    offre, motif = controler(texte, produits, fournisseurs, aujourd_hui)
                    if offre:
                        cle = (offre["supplier_id"], offre["offer_id"], offre["observed_on"])
                        if cle in deja_vues:
                            offre, motif = None, "doublon_dans_le_lot"
                        deja_vues.add(cle)
                    if motif:
                        rejets.append((lot["lot_id"], numero, motif, texte))
                        continue

                    resultat = db.execute(UPSERT, {**offre, "lot": lot["lot_id"]}).fetchone()
                    if resultat is None:
                        compteurs["reutilisees"] += 1
                    elif resultat[0]:
                        compteurs["inserees"] += 1
                    else:
                        compteurs["mises_a_jour"] += 1

                    # Panne volontaire au milieu du lot (option --panne-apres).
                    ecrites = compteurs["inserees"] + compteurs["mises_a_jour"] + compteurs["reutilisees"]
                    if panne_apres is not None and ecrites >= panne_apres:
                        raise PanneSimulee(f"panne simulée après {ecrites} lignes écrites")

                compteurs["rejetees"] = len(rejets)
                enregistrer_lot(db, lot, compteurs, "valide")
                with db.cursor() as cur:
                    cur.executemany(
                        "INSERT INTO fournisseur.rejets_chargement VALUES (%s, %s, %s, %s)", rejets)
            # ---- COMMIT ici (sortie normale du bloc) ----------------------
        except (psycopg.Error, PanneSimulee) as exc:
            # Le ROLLBACK a déjà eu lieu. On garde quand même une trace du lot
            # annulé, dans une NOUVELLE petite transaction, sans aucune offre.
            vide = dict.fromkeys(compteurs, 0) | {"lues": compteurs["lues"]}
            with db.transaction():
                db.execute(DDL)
                enregistrer_lot(db, lot, vide, "annule", erreur=str(exc))
            return {**lot_public(lot), "statut": "annule", "erreur": str(exc), **vide}

    return {**lot_public(lot), "statut": "valide", **compteurs}


def enregistrer_lot(db, lot, compteurs, statut, erreur=None):
    db.execute(
        """INSERT INTO fournisseur.lots VALUES
           (%(lot_id)s, %(fichier)s, %(sha256)s, %(demarre_le)s, now(), %(statut)s,
            %(lues)s, %(inserees)s, %(mises_a_jour)s, %(reutilisees)s, %(rejetees)s, %(erreur)s)""",
        {**lot, **compteurs, "statut": statut, "erreur": erreur},
    )


def lot_public(lot):
    """Champs du lot affichés dans le bilan (la date en texte pour le JSON)."""
    return {**lot, "demarre_le": lot["demarre_le"].isoformat(timespec="seconds"),
            "sha256": lot["sha256"][:12]}


def lire_arguments(argv=None):
    parser = argparse.ArgumentParser(description="Charge les offres valides S3 dans PostgreSQL.")
    parser.add_argument("--entree", type=Path, default=ENTREE_PAR_DEFAUT,
                        help="JSONL valide (défaut : ingestion/data/valid/offres.jsonl)")
    parser.add_argument("--panne-apres", type=int, default=None, metavar="N",
                        help="lève une erreur après N lignes écrites (test d'atomicité)")
    return parser.parse_args(argv)


def main():
    args = lire_arguments()
    dsn = os.environ.get("NOVAMARKET_DSN")
    if not dsn:  # consigne : échouer si aucune connexion n'est définie
        raise SystemExit("NOVAMARKET_DSN n'est pas défini (voir l'en-tête du fichier).")
    entree = args.entree.resolve()
    if not entree.is_file():
        raise SystemExit(f"Fichier introuvable : {entree}")
    try:
        bilan = charger(dsn, entree, args.panne_apres)
    except psycopg.OperationalError as exc:
        raise SystemExit(f"Connexion PostgreSQL impossible : {exc}") from exc
    print(json.dumps(bilan, ensure_ascii=False, indent=2))
    return 0 if bilan["statut"] == "valide" else 1


if __name__ == "__main__":
    sys.exit(main())

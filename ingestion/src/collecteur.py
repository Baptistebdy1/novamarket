"""Collecte des six pages du fournisseur, avec reprise des erreurs transitoires."""

import argparse
import asyncio
import csv
import json
import os
import re
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from pathlib import Path
from time import perf_counter
from uuid import uuid4

import aiohttp

from ingestion.src.journalisation import Journal
from ingestion.src.validation import valider_pages

RACINE = Path(__file__).resolve().parents[2]
PAGES_ATTENDUES = 6
STATUTS_A_REESSAYER = {429, 500, 502, 503, 504}


class ErreurPage(Exception):
    """La page n'a pas pu être récupérée dans les limites prévues."""


def verifier_page(document, page):
    if not isinstance(document, dict):
        raise ValueError("page_non_objet")
    total = document.get("total_pages")
    if type(total) is not int or total != PAGES_ATTENDUES:
        raise ValueError("total_pages_incoherent")
    numero = document.get("page")
    suivant = page + 1 if page < total else None
    lignes = document.get("items")
    if (type(numero) is not int or numero != page
            or "next_page" not in document or document["next_page"] != suivant
            or not isinstance(lignes, list) or len(lignes) != 4):
        raise ValueError("pagination_incoherente")
    return document


def delai_retry(entete, tentative):
    if entete:
        if entete.isascii() and entete.isdecimal():
            return int(entete)
        try:
            date_reprise = parsedate_to_datetime(entete)
            if date_reprise.tzinfo is None:
                date_reprise = date_reprise.replace(tzinfo=timezone.utc)
            return max(0, (date_reprise - datetime.now(timezone.utc)).total_seconds())
        except (TypeError, ValueError, OverflowError):
            pass
    return min(0.1 * 2 ** (tentative - 1), 1.0)


class ClientFournisseur:
    def __init__(self, session, args, journal):
        self.session = session
        self.args = args
        self.journal = journal
        self.limite = asyncio.Semaphore(args.concurrence)
        self.tentatives = self.retries = self.en_cours = self.pic = 0

    async def requete(self, page, tentative):
        async with self.limite:
            self.tentatives += 1
            self.retries += tentative > 1
            self.en_cours += 1
            self.pic = max(self.pic, self.en_cours)
            try:
                async with self.session.get(
                    self.args.url.rstrip("/") + "/offers",
                    params=dict(page=page, scenario=self.args.scenario, run=self.args.run),
                    allow_redirects=False,
                ) as reponse:
                    return reponse.status, reponse.headers.get("Retry-After"), await reponse.text(errors="replace")
            finally:
                self.en_cours -= 1

    async def lire_page(self, page):
        for tentative in range(1, self.args.tentatives + 1):
            statut, entete, erreur = None, None, None
            reprendre = True
            try:
                statut, entete, corps = await self.requete(page, tentative)
                self.journal.ajouter(self.journal.brut, dict(
                    page=page, tentative=tentative, statut=statut, retry_after=entete, corps=corps,
                ))
                if statut == 200:
                    resultat = verifier_page(json.loads(corps), page)
                else:
                    erreur = f"http_{statut}"
                    reprendre = statut in STATUTS_A_REESSAYER
            except asyncio.TimeoutError:
                erreur = "timeout"
            except aiohttp.ClientError:
                erreur = "erreur_reseau"
            except json.JSONDecodeError:
                erreur = "json_invalide"
            except ValueError as exc:
                erreur = str(exc)

            retry = erreur is not None and reprendre and tentative < self.args.tentatives
            attente = delai_retry(entete, tentative) if retry else None
            self.journal.evenement("tentative", page=page, tentative=tentative,
                                   statut=statut, erreur=erreur, attente_s=attente)
            if erreur is None:
                return resultat
            if not retry:
                raise ErreurPage(erreur)
            await asyncio.sleep(attente)


async def collecter(args):
    with args.catalogue.open(encoding="utf-8", newline="") as catalogue:
        produits = {int(ligne["product_id"]) for ligne in csv.DictReader(catalogue)}

    journal = Journal(args.data, args.run)
    journal.evenement("debut", run=args.run, scenario=args.scenario,
                     concurrence=args.concurrence, timeout_s=args.timeout, max_tentatives=args.tentatives)
    debut = perf_counter()
    pages, erreurs = {}, {}
    timeout = aiohttp.ClientTimeout(total=args.timeout)
    async with aiohttp.ClientSession(timeout=timeout) as session:
        client = ClientFournisseur(session, args, journal)
        try:
            premiere = await client.lire_page(1)
        except ErreurPage as exc:
            erreurs[1] = str(exc)
        else:
            total = premiere["total_pages"]
            pages[1] = premiere["items"]
            numeros = range(2, total + 1)
            resultats = await asyncio.gather(
                *(client.lire_page(page) for page in numeros), return_exceptions=True,
            )
            for page, resultat in zip(numeros, resultats):
                if isinstance(resultat, ErreurPage):
                    erreurs[page] = str(resultat)
                elif isinstance(resultat, BaseException):
                    raise resultat
                else:
                    pages[page] = resultat["items"]

    valides, rejets = valider_pages(pages, produits)
    for rejet in rejets:
        journal.ajouter(journal.rejets, rejet)
    complet = len(pages) == PAGES_ATTENDUES and not erreurs
    if complet:
        journal.publier(valides)
    bilan = dict(
        run=args.run, scenario=args.scenario, pages_attendues=PAGES_ATTENDUES,
        pages_recues=sorted(pages), pages_en_echec=sorted(erreurs), erreurs_pages=erreurs,
        lignes_vues=sum(map(len, pages.values())), valides=len(valides), rejets=len(rejets),
        requetes_http=client.tentatives, retries=client.retries, pic_concurrence=client.pic,
        duree_s=round(perf_counter() - debut, 3), publie=complet,
    )
    journal.evenement("bilan", **bilan)
    return bilan


def lire_arguments(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    port = os.environ.get("NOVAMARKET_API_PORT", "18080")
    parser.add_argument("--url", default=f"http://127.0.0.1:{port}")
    parser.add_argument("--scenario", choices=("clean", "atelier", "panne"), default="atelier")
    parser.add_argument("--run", default=f"essai-{uuid4().hex[:8]}")
    parser.add_argument("--concurrence", type=int, default=3)
    parser.add_argument("--timeout", type=float, default=0.8)
    parser.add_argument("--tentatives", type=int, default=3)
    parser.add_argument("--data", type=Path, default=RACINE / "ingestion/data")
    parser.add_argument("--catalogue", type=Path, default=RACINE / "s2/donnees/products.csv")
    args = parser.parse_args(argv)
    if not re.fullmatch(r"[a-zA-Z0-9_-]{1,64}", args.run):
        parser.error("--run doit contenir de 1 à 64 lettres, chiffres, tirets ou underscores")
    if args.concurrence < 1 or args.tentatives < 1 or not 0 < args.timeout < float("inf"):
        parser.error("concurrence, tentatives et timeout doivent être strictement positifs")
    return args


def main():
    args = lire_arguments()
    try:
        bilan = asyncio.run(collecter(args))
    except (OSError, ValueError) as exc:
        raise SystemExit(f"Collecte interrompue pour {args.run} : {exc}") from exc
    print(json.dumps(bilan, ensure_ascii=False, indent=2))
    return 0 if bilan["publie"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

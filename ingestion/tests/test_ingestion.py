"""Contrôles de validation et de non-publication d'un lot incomplet."""

import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from ingestion.src.collecteur import collecter, lire_arguments, verifier_page
from ingestion.src.validation import valider_pages


class ValidationTest(unittest.TestCase):
    def test_pagination_refuse_un_total_incomplet(self):
        page = dict(page=1, total_pages=1, next_page=None, items=[{}] * 4)
        with self.assertRaisesRegex(ValueError, "total_pages_incoherent"):
            verifier_page(page, 1)

    def test_types_stricts_and_first_valid_occurrence(self):
        offre = dict(offer_id="O001", supplier_id="F01", product_id=1,
                     price_cents=0, currency="EUR", available_units=0,
                     observed_on="2026-11-24")
        pages = {
            2: [offre, {**offre, "product_id": 9999}],
            1: [{**offre, "price_cents": False}, offre],
        }
        valides, rejets = valider_pages(pages, {1})
        self.assertEqual(valides, [offre])
        self.assertEqual([(r["page"], r["position"], r["motif"]) for r in rejets], [
            (1, 1, "prix_invalide"), (2, 1, "doublon"), (2, 2, "produit_inconnu"),
        ])


class CollecteTest(unittest.IsolatedAsyncioTestCase):
    async def test_failed_page_preserves_previous_publication(self):
        class Reponse:
            def __init__(self, page):
                self.page = page
                self.status = 503 if page == 6 else 200
                self.headers = {}

            async def __aenter__(self):
                return self

            async def __aexit__(self, *_):
                pass

            async def text(self, **_):
                if self.status == 503:
                    return "{}"
                offres = [
                    dict(offer_id=f"O{i:03}", supplier_id="F01", product_id=i,
                         price_cents=500, currency="EUR", available_units=1,
                         observed_on="2026-11-24")
                    for i in range(4 * self.page - 3, 4 * self.page + 1)
                ]
                return json.dumps(dict(page=self.page, total_pages=6,
                                       next_page=self.page+1, items=offres))

        class Session:
            def __init__(self, **_):
                pass

            async def __aenter__(self):
                return self

            async def __aexit__(self, *_):
                pass

            def get(self, _, *, params, **__):
                return Reponse(params["page"])

        with tempfile.TemporaryDirectory() as dossier:
            racine = Path(dossier)
            valide = racine / "valid/offres.jsonl"
            valide.parent.mkdir()
            valide.write_text('{"lot":"precedent"}\n', encoding="utf-8")
            args = lire_arguments(["--scenario", "panne", "--run", "test",
                                    "--data", dossier, "--tentatives", "2"])
            with patch("ingestion.src.collecteur.aiohttp.ClientSession", Session):
                bilan = await collecter(args)
            self.assertFalse(bilan["publie"])
            self.assertEqual(bilan["pages_en_echec"], [6])
            self.assertEqual(bilan["retries"], 1)
            self.assertEqual(valide.read_text(encoding="utf-8"), '{"lot":"precedent"}\n')

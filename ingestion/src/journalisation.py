"""Traces JSONL par essai et publication atomique du lot complet."""

import json
from datetime import datetime, timezone
from pathlib import Path
from tempfile import NamedTemporaryFile


def ecrire_ligne(fichier, objet):
    fichier.write(json.dumps(objet, ensure_ascii=False) + "\n")


class Journal:
    def __init__(self, racine, run):
        self.brut = racine / "raw" / f"{run}.jsonl"
        self.rejets = racine / "rejected" / f"{run}.jsonl"
        self.logs = racine / "logs" / f"{run}.jsonl"
        self.valide = racine / "valid" / "offres.jsonl"
        for fichier in (self.logs, self.brut, self.rejets):
            fichier.parent.mkdir(parents=True, exist_ok=True)
            fichier.touch(exist_ok=False)

    @staticmethod
    def ajouter(fichier, objet):
        with fichier.open("a", encoding="utf-8") as sortie:
            ecrire_ligne(sortie, objet)

    def evenement(self, nom, **champs):
        self.ajouter(self.logs, dict(
            horaire=datetime.now(timezone.utc).isoformat(), evenement=nom, **champs,
        ))

    def publier(self, offres):
        self.valide.parent.mkdir(parents=True, exist_ok=True)
        with NamedTemporaryFile(mode="w", encoding="utf-8", dir=self.valide.parent,
                                prefix=".offres-", suffix=".tmp", delete=False) as sortie:
            provisoire = Path(sortie.name)
            try:
                for offre in offres:
                    ecrire_ligne(sortie, offre)
                sortie.close()
                provisoire.replace(self.valide)
            finally:
                provisoire.unlink(missing_ok=True)

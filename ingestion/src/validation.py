"""Règles métier du catalogue d'offres."""

from datetime import date

CHAMPS = (
    "offer_id", "supplier_id", "product_id", "price_cents",
    "currency", "available_units", "observed_on",
)


def motif_rejet(offre, produits):
    if not isinstance(offre, dict):
        return "offre_non_objet"
    for champ in CHAMPS:
        if champ not in offre:
            return f"champ_manquant:{champ}"
    for champ in ("offer_id", "supplier_id"):
        valeur = offre[champ]
        if not isinstance(valeur, str) or not valeur.strip():
            return f"identifiant_invalide:{champ}"
    produit = offre["product_id"]
    if type(produit) is not int or produit not in produits:
        return "produit_inconnu"
    for champ, motif in (("price_cents", "prix_invalide"), ("available_units", "stock_invalide")):
        if type(offre[champ]) is not int or offre[champ] < 0:
            return motif
    if offre["currency"] != "EUR":
        return "devise_invalide"
    try:
        if date.fromisoformat(offre["observed_on"]).isoformat() != offre["observed_on"]:
            return "date_invalide"
    except (TypeError, ValueError):
        return "date_invalide"
    return None


def valider_pages(pages, produits):
    """Renvoyer les offres valides et les rejets, dans l'ordre des pages."""
    valides, rejets = [], []
    deja_vues = set()
    for page, offres in sorted(pages.items()):
        for position, offre in enumerate(offres, start=1):
            motif = motif_rejet(offre, produits)
            if motif is None:
                cle = (offre["supplier_id"], offre["offer_id"])
                if cle in deja_vues:
                    motif = "doublon"
                else:
                    deja_vues.add(cle)
                    valides.append({champ: offre[champ] for champ in CHAMPS})
            if motif:
                rejets.append(dict(page=page, position=position, motif=motif, offre=offre))
    return valides, rejets

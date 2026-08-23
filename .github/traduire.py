# -*- coding: utf-8 -*-
"""Traduit automatiquement tout texte nouvellement ajouté à l'application.

Tourne sur la CI après l'extraction des clés : repère ce qui manque dans
chaque langue, le fait traduire, vérifie, et écrit le catalogue.

Trois garde-fous, parce qu'une traduction fausse ne se voit qu'à
l'exécution, chez l'utilisateur :

1. Les emplacements de format (%lld, %@, %%) doivent être IDENTIQUES à
   ceux de la clé. Une traduction qui en perd un fait planter l'affichage.
2. L'alphabet doit correspondre à la langue : pas de cyrillique dans du
   japonais, pas de hangul dans du chinois.
3. Une traduction refusée n'est pas écrite : mieux vaut un texte français
   visible qu'une chaîne cassée.

Clé attendue dans la variable d'environnement GEMINI_API_KEY.
"""
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# HONYA_CATALOGUE permet de viser une copie pour les essais.
CATALOGUE = os.environ.get(
    "HONYA_CATALOGUE", os.path.join(RACINE, "Honya", "Localizable.xcstrings")
)

LANGUES = {
    "en": "anglais",
    "es": "espagnol (Espagne)",
    "es-419": "espagnol d'Amérique latine",
    "pt-BR": "portugais du Brésil",
    "de": "allemand",
    "it": "italien",
    "nl": "néerlandais",
    "pl": "polonais",
    "sv": "suédois",
    "tr": "turc",
    "ru": "russe",
    "ja": "japonais",
    "ko": "coréen",
    "zh-Hans": "chinois simplifié",
}

# Google retire les anciens modèles sans prévenir (2.5-flash l'a été).
# On essaie dans l'ordre, et « -latest » sert de filet de sécurité.
MODELES = ["gemini-3.7-flash", "gemini-flash-latest"]

SPECIFICATEUR = re.compile(r"%(?:\d+\$)?(?:%|[@a-zA-Z]+)")

ALPHABETS = {
    "ru": re.compile(r"[Ѐ-ӿ]"),
    "ja": re.compile(r"[぀-ヿ㐀-鿿]"),
    "ko": re.compile(r"[가-힣]"),
    "zh-Hans": re.compile(r"[㐀-鿿]"),
}
MARQUES = {"Honya", "Apple", "iPhone", "iCloud", "CloudKit", "Google", "Books",
           "Open", "Library", "AniList", "ISBN", "OK", "lld"}

CONSIGNE = """Tu traduis l'interface d'une application iPhone de suivi de lecture
appelée Honya : on y range ses livres et ses mangas, tome par tome.

Ton : chaleureux, direct, jamais bavard ni commercial. Vocabulaire du livre
(rayon, tome, étagère), pas celui du logiciel.

Règles absolues :
- Garde EXACTEMENT les emplacements de format : %lld, %@, %% et les retours
  à la ligne \\n. Ni ajout, ni suppression, ni changement d'ordre.
- Ne traduis jamais « Honya », ni les noms de marques.
- N'ajoute ni guillemets ni ponctuation qui ne soient pas dans l'original.
- Une interface : reste court. Un bouton doit tenir sur un bouton.

Réponds UNIQUEMENT par un objet JSON {"index": "traduction", …}, où index est
celui donné, sans aucun texte autour."""


def charger():
    with open(CATALOGUE, encoding="utf-8") as f:
        return json.load(f)


def enregistrer(catalogue):
    with open(CATALOGUE, "w", encoding="utf-8") as f:
        json.dump(catalogue, f, ensure_ascii=False, indent=2)
        f.write("\n")


def acceptable(cle, traduction, langue):
    """Une traduction n'est écrite que si elle passe tous les contrôles."""
    if not traduction or not traduction.strip():
        return False, "vide"

    attendus = sorted(SPECIFICATEUR.findall(cle))
    trouves = sorted(SPECIFICATEUR.findall(traduction))
    if attendus != trouves:
        return False, f"emplacements {trouves} au lieu de {attendus}"

    if cle.count("\n") != traduction.count("\n"):
        return False, "retours à la ligne différents"

    for autre, motif in ALPHABETS.items():
        if autre == langue:
            continue
        if langue == "zh-Hans" and autre == "ja":
            continue          # les idéogrammes sont communs
        if langue == "ja" and autre == "zh-Hans":
            continue
        if motif.search(traduction):
            return False, f"alphabet {autre} inattendu"

    if langue in ("ru", "ja", "ko", "zh-Hans"):
        for mot in re.findall(r"\b[A-Za-z]{3,}\b", traduction):
            if mot not in MARQUES:
                return False, f"mot latin « {mot} » inattendu"

    return True, ""


def extraire(donnees, numerotees):
    """Retrouve le texte des traductions dans la réponse du service."""
    texte = donnees["candidates"][0]["content"]["parts"][0]["text"]
    brut = json.loads(texte)
    return {numerotees[i]: v for i, v in brut.items() if i in numerotees}


def demander(cles, langue, cle_api):
    """Un seul appel pour un paquet de clés : moins d'aller-retours."""
    numerotees = {str(i): cle for i, cle in enumerate(cles)}
    corps = {
        "systemInstruction": {"parts": [{"text": CONSIGNE}]},
        "contents": [{"parts": [{
            "text": f"Traduis en {LANGUES[langue]} :\n"
                    + json.dumps(numerotees, ensure_ascii=False, indent=1)
        }]}],
        "generationConfig": {"responseMimeType": "application/json", "temperature": 0.3},
    }
    dernier = None
    for modele in MODELES:
        requete = urllib.request.Request(
            "https://generativelanguage.googleapis.com/v1beta/models/"
            f"{modele}:generateContent",
            data=json.dumps(corps).encode(),
            headers={"Content-Type": "application/json", "x-goog-api-key": cle_api},
            method="POST",
        )
        # 503 (saturé) et 429 (trop de demandes) sont passagers : on patiente.
        for tentative in range(5):
            try:
                with urllib.request.urlopen(requete, timeout=180) as reponse:
                    donnees = json.load(reponse)
                return extraire(donnees, numerotees)
            except urllib.error.HTTPError as souci:
                dernier = f"{modele} : {souci.code}"
                if souci.code == 404:
                    break                       # modèle retiré : au suivant
                if souci.code in (429, 500, 503):
                    attente = 5 * 2 ** tentative
                    print(f"    {modele} saturé, nouvelle tentative dans {attente} s")
                    time.sleep(attente)
                    continue
                raise
            except (urllib.error.URLError, TimeoutError) as souci:
                dernier = f"{modele} : {souci}"
                time.sleep(5 * 2 ** tentative)

    raise urllib.error.URLError(dernier or "aucun modèle disponible")




def main():
    cle_api = os.environ.get("GEMINI_API_KEY", "").strip()
    catalogue = charger()
    chaines = catalogue.get("strings", {})

    manquantes = {}
    for langue in LANGUES:
        absentes = [
            cle for cle, entree in chaines.items()
            if langue not in (entree.get("localizations") or {})
        ]
        if absentes:
            manquantes[langue] = absentes

    if not manquantes:
        print("Toutes les langues sont à jour : rien à traduire.")
        return 0

    total = sum(len(v) for v in manquantes.values())
    print(f"{total} traduction(s) manquante(s) :")
    for langue, absentes in manquantes.items():
        print(f"  {langue:<8} {len(absentes)}")

    if not cle_api:
        print("\nGEMINI_API_KEY absente : impossible de traduire.")
        print("Ajoutez-la dans les secrets du dépôt (Settings > Secrets > Actions).")
        return 1

    ecrites = refusees = echecs = 0
    for langue, absentes in manquantes.items():
        for depart in range(0, len(absentes), 40):
            paquet = absentes[depart:depart + 40]
            try:
                resultat = demander(paquet, langue, cle_api)
            except (urllib.error.URLError, KeyError, json.JSONDecodeError) as souci:
                print(f"  ÉCHEC {langue} ({souci}) : {len(paquet)} non traduits")
                echecs += len(paquet)
                continue

            for cle, traduction in resultat.items():
                bon, raison = acceptable(cle, traduction, langue)
                if not bon:
                    print(f"  REFUSÉ {langue} {cle[:40]!r} : {raison}")
                    refusees += 1
                    continue
                chaines[cle].setdefault("localizations", {})[langue] = {
                    "stringUnit": {"state": "translated", "value": traduction}
                }
                ecrites += 1
            time.sleep(2)

    enregistrer(catalogue)
    print()
    print(f"{ecrites} écrite(s), {refusees} refusée(s), {echecs} en échec.")
    if refusees or echecs:
        # Sortie en erreur volontaire : une langue à moitié traduite se voit
        # chez l'utilisateur sous forme de français au milieu de sa langue.
        print("Des textes restent non traduits — relancez le travail, ou")
        print("complétez à la main dans Design/traductions_*.py.")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

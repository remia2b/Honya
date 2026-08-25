# -*- coding: utf-8 -*-
"""Les textes qui atteignent l'écran sans passer par le catalogue.

`cles_manquantes.py` ramasse tous les littéraux d'un fichier : adresses,
en-têtes HTTP, motifs d'expression régulière. Celui-ci ne regarde que les
positions où SwiftUI attend un `LocalizedStringKey` — donc uniquement ce
qu'un lecteur peut lire.

Usage : python Design/fuites_francaises.py
"""
import json
import os
import re
import sys

RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOGUE = os.path.join(RACINE, "Honya", "Localizable.xcstrings")

GUILLEMET = '"([^"' + chr(92) + chr(10) + ']{2,})"'

# Les positions où SwiftUI localise tout seul, plus String(localized:).
POSITIONS = [
    re.compile(r"\bText\(\s*" + GUILLEMET),
    re.compile(r"\bButton\(\s*" + GUILLEMET),
    re.compile(r"\bLabel\(\s*" + GUILLEMET),
    re.compile(r"\bSection\(\s*" + GUILLEMET),
    re.compile(r"\bLabelPlus\(titre:\s*" + GUILLEMET),
    re.compile(r"\bString\(localized:\s*" + GUILLEMET),
    re.compile(r"\.navigationTitle\(\s*" + GUILLEMET),
    re.compile(r"\.alert\(\s*" + GUILLEMET),
    re.compile(r"\.confirmationDialog\(\s*" + GUILLEMET),
    re.compile(r"\.accessibilityLabel\(\s*" + GUILLEMET),
    re.compile(r"\bContentUnavailableView\(\s*" + GUILLEMET),
    # Uniquement l'en-tête de section : « titre: » tout court attrape les
    # titres de livres du mur d'accueil, qui sont des données, pas du texte.
    re.compile(r"TitreSection\(\s*titre:\s*" + GUILLEMET),
    re.compile(r"\bsousTitre:\s*" + GUILLEMET),
    re.compile(r"\binvite:\s*" + GUILLEMET),
]

# Ce qui n'est pas du texte : symboles SF, identifiants, interpolations.
SYMBOLE = re.compile(r"^[a-z0-9.]+$")
TECHNIQUE = re.compile(r"^[a-zA-Z]+[A-Z][a-zA-Z]*$")


def main():
    with open(CATALOGUE, encoding="utf-8") as fichier:
        connues = set(json.load(fichier).get("strings", {}))

    trouves = {}
    for dossier, _, fichiers in os.walk(os.path.join(RACINE, "Honya")):
        for nom in fichiers:
            if not nom.endswith(".swift"):
                continue
            chemin = os.path.join(dossier, nom)
            with open(chemin, encoding="utf-8") as fichier:
                source = fichier.read()
            # `Text(verbatim:)` dit explicitement « ne traduis pas ».
            source = re.sub(r"verbatim:\s*" + GUILLEMET, "", source)
            for motif in POSITIONS:
                for texte in motif.findall(source):
                    if SYMBOLE.match(texte) or TECHNIQUE.match(texte):
                        continue
                    if chr(92) + "(" in texte:
                        continue
                    # Le catalogue garde un vrai saut de ligne là où la
                    # source porte la séquence d'échappement.
                    if chr(92) + "n" in texte:
                        continue
                    if texte not in connues:
                        trouves.setdefault(texte, set()).add(
                            os.path.relpath(chemin, RACINE).replace(os.sep, "/")
                        )

    print(f"{len(trouves)} texte(s) affiché(s) hors catalogue :")
    for texte in sorted(trouves):
        print(f"    {texte!r}: {{}},   # {' '.join(sorted(trouves[texte]))}")
    return 1 if trouves else 0


if __name__ == "__main__":
    sys.exit(main())

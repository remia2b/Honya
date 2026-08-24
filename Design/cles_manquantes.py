# -*- coding: utf-8 -*-
"""Liste les textes d'un fichier Swift qui ne sont pas encore au catalogue.

Complète le travail de la CI : celle-ci ne voit les clés qu'après une
compilation Xcode, alors qu'on veut savoir AVANT de pousser ce qu'il reste
à traduire.

Usage : python Design/cles_manquantes.py Honya/Vues/Compte/Verrou.swift …
"""
import json
import os
import re
import sys

RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOGUE = os.path.join(RACINE, "Honya", "Localizable.xcstrings")

# Le motif s'arrête au retour à la ligne : sans ça il avale des blocs de
# code entiers entre deux guillemets éloignés.
TEXTE = re.compile('"([^"' + chr(92) + chr(10) + ']{6,})"')
VERBATIM = re.compile(r'Text\(verbatim: "[^"]*"\)')
SYMBOLE = re.compile(r"^[a-z0-9.]+$")
# Clés d'UserDefaults et autres identifiants techniques.
TECHNIQUE = re.compile(r"^[a-zA-Z]+[A-Z][a-zA-Z]*$")


def main(fichiers):
    with open(CATALOGUE, encoding="utf-8") as f:
        connues = set(json.load(f).get("strings", {}))

    cles = set()
    for chemin in fichiers:
        with open(os.path.join(RACINE, chemin), encoding="utf-8") as f:
            source = VERBATIM.sub("", f.read())
        for trouve in TEXTE.findall(source):
            # Les noms de SF Symbols ressemblent à du texte : on les écarte.
            if SYMBOLE.match(trouve) or TECHNIQUE.match(trouve):
                continue
            cles.add(trouve)

    manque = sorted(c for c in cles if c not in connues)
    print(f"{len(manque)} clé(s) absente(s) du catalogue :")
    for cle in manque:
        print(f"    {cle!r}: {{}},")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

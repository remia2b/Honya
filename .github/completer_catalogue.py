# -*- coding: utf-8 -*-
"""Inscrit au catalogue les textes que Xcode vient de repérer dans le code.

Entre l'extraction (rassembler_cles.py) et la traduction (traduire.py), il
faut que les nouveaux textes existent dans le catalogue, sans quoi personne
ne s'apercevrait qu'ils manquent.

Les clés qui ne sont plus utilisées sont seulement signalées, jamais
effacées : un texte peut disparaître d'une compilation parce qu'un écran est
temporairement mis de côté, et retrouver sa traduction ensuite évite de la
refaire.
"""
import json
import os

RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOGUE = os.environ.get(
    "HONYA_CATALOGUE", os.path.join(RACINE, "Honya", "Localizable.xcstrings")
)
EXTRACTION = os.environ.get(
    "HONYA_EXTRACTION", os.path.join(RACINE, "Design", "cles-extraites.json")
)


def main():
    with open(EXTRACTION, encoding="utf-8") as fichier:
        extraites = json.load(fichier)
    with open(CATALOGUE, encoding="utf-8") as fichier:
        catalogue = json.load(fichier)

    chaines = catalogue.setdefault("strings", {})
    nouvelles = [cle for cle in extraites if cle not in chaines]

    for cle in nouvelles:
        chaines[cle] = {"localizations": {}}

    orphelines = [cle for cle in chaines if cle not in extraites]

    if nouvelles:
        print(f"{len(nouvelles)} texte(s) nouveau(x) à traduire :")
        for cle in nouvelles:
            print(f"   {cle!r}")
        catalogue["strings"] = {cle: chaines[cle] for cle in sorted(chaines)}
        with open(CATALOGUE, "w", encoding="utf-8") as fichier:
            json.dump(catalogue, fichier, ensure_ascii=False, indent=2)
            fichier.write("\n")
    else:
        print("Aucun texte nouveau dans le code.")

    if orphelines:
        print(f"\n{len(orphelines)} texte(s) plus utilisé(s) — gardés au cas où :")
        for cle in orphelines[:20]:
            print(f"   {cle!r}")


if __name__ == "__main__":
    main()

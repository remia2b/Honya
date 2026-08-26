# -*- coding: utf-8 -*-
"""Refuse de laisser passer un texte qui manquerait dans une langue.

La traduction automatique tourne à chaque poussée, mais rien n'empêche de
poser une étiquette de version dans la foulée, avant qu'elle ait fini. Ce
contrôle-ci ferme la porte : tant qu'un texte manque quelque part, la
vérification de compilation reste rouge.

Il vérifie aussi ce que la traduction automatique ne peut pas voir, faute
de comparer les langues entre elles : qu'aucune traduction n'est restée
identique au français alors qu'elle devrait différer.
"""
import json
import os
import re
import sys

RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOGUE = os.path.join(RACINE, "Honya", "Localizable.xcstrings")

LANGUES = ["en", "es", "es-419", "pt-BR", "de", "it", "nl", "pl", "sv",
           "tr", "ru", "ja", "ko", "zh-Hans"]

SPECIFICATEUR = re.compile(r"%(?:\d+\$)?(?:%|[@a-zA-Z]+)")

def suspect(cle):
    """Une traduction recopiée mot pour mot mérite-t-elle un coup d'œil ?

    Beaucoup de textes sont normalement identiques d'une langue à l'autre :
    « Honya », « Manga », « %lld min · %lld p. » où seuls « min » et « p. »
    portent du sens. On ne s'inquiète que des vraies phrases : ce qui reste
    une fois retirés les emplacements de format et la ponctuation.
    """
    mots = SPECIFICATEUR.sub(" ", cle)
    lettres = re.sub(r"[^A-Za-zÀ-ÿ]", "", mots)
    return len(lettres) > 12


def textes(unite):
    """Les textes d'une localisation — un seul, ou un par forme de pluriel.

    « 1 livres reconnus » se lisait dans toutes les langues : le catalogue
    ne portait qu'une forme. Une entrée pluralisée en porte plusieurs, sous
    `variations.plural`, et n'est complète que si toutes le sont.
    """
    if "stringUnit" in unite:
        return [unite["stringUnit"].get("value", "")]
    formes = unite.get("variations", {}).get("plural", {})
    return [f.get("stringUnit", {}).get("value", "") for f in formes.values()]


def main():
    with open(CATALOGUE, encoding="utf-8") as fichier:
        catalogue = json.load(fichier)
    chaines = catalogue["strings"]

    trous = []
    formats = []
    recopiees = {}

    for cle, entree in chaines.items():
        localisations = entree.get("localizations") or {}
        for langue in LANGUES:
            unite = localisations.get(langue)
            if not unite:
                trous.append((langue, cle))
                continue
            valeurs = textes(unite)
            if not valeurs or any(not v.strip() for v in valeurs):
                trous.append((langue, cle))
                continue
            for valeur in valeurs:
                if sorted(SPECIFICATEUR.findall(cle)) != sorted(SPECIFICATEUR.findall(valeur)):
                    formats.append((langue, cle, valeur))
                if valeur == cle and suspect(cle) and cle not in recopiees.get(langue, []):
                    recopiees.setdefault(langue, []).append(cle)

    print(f"{len(chaines)} textes × {len(LANGUES)} langues")

    if trous:
        print(f"\n{len(trous)} TEXTE(S) NON TRADUIT(S) :")
        for langue, cle in trous[:40]:
            print(f"   {langue:<8} {cle!r}")
        if len(trous) > 40:
            print(f"   … et {len(trous) - 40} autres")

    if formats:
        print(f"\n{len(formats)} TRADUCTION(S) AUX EMPLACEMENTS CASSÉS :")
        for langue, cle, valeur in formats[:20]:
            print(f"   {langue:<8} {cle!r}")
            print(f"   {'':<8} → {valeur!r}")

    # Une traduction recopiée telle quelle est suspecte, mais pas fautive en
    # soi : on le signale sans bloquer, sauf si toute une langue est concernée.
    for langue, cles in recopiees.items():
        part = len(cles) / len(chaines)
        if part > 0.15:
            print(f"\n{langue} : {len(cles)} textes identiques au français "
                  f"({part:.0%}) — cette langue semble ne pas être traduite.")
            trous.append((langue, "(langue entière suspecte)"))
        elif cles:
            print(f"\n{langue} : {len(cles)} texte(s) identique(s) au français "
                  f"(à vérifier) — {cles[0]!r}…")

    if trous or formats:
        print("\nLa version ne peut pas partir dans cet état : un écran qui")
        print("mélange deux langues se voit tout de suite chez l'utilisateur.")
        print("Lancez la traduction : gh workflow run traductions.yml")
        return 1

    print("\nToutes les langues sont complètes.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

# -*- coding: utf-8 -*-
"""Écrit les traductions dans Honya/Localizable.xcstrings.

Le catalogue d'Xcode est un simple fichier JSON : on peut donc le remplir
depuis Windows, sans Mac. Les clés, elles, sont extraites par Xcode sur la
CI (workflow « traductions.yml ») pour que les spécificateurs de format
(%lld, %@) soient exacts.

Usage : from catalogue import ecrire ; ecrire({"Bibliothèque": {"en": "Library", …}})
"""
import json
import os
import re

CHEMIN = os.path.join(os.path.dirname(__file__), "..", "Honya", "Localizable.xcstrings")

SPECIFICATEUR = re.compile(r"%(?:\d+\$)?[@a-zA-Z]+")


def charger():
    with open(CHEMIN, encoding="utf-8") as f:
        return json.load(f)


def verifier(cle: str, traduction: str) -> list[str]:
    """Une traduction doit porter exactement les mêmes emplacements que sa clé,
    sinon l'application affiche du charabia — ou plante à l'exécution."""
    attendus = sorted(SPECIFICATEUR.findall(cle))
    trouves = sorted(SPECIFICATEUR.findall(traduction))
    if attendus != trouves:
        return [f"{cle!r} → {traduction!r} : attendu {attendus}, trouvé {trouves}"]
    return []


def ecrire(traductions: dict[str, dict[str, str]], strict: bool = True):
    catalogue = charger()
    chaines = catalogue.setdefault("strings", {})

    soucis: list[str] = []
    inconnues: list[str] = []
    ajoutees = 0

    for cle, par_langue in traductions.items():
        if cle not in chaines:
            inconnues.append(cle)
            chaines[cle] = {}
        entree = chaines[cle]
        localisations = entree.setdefault("localizations", {})

        for langue, texte in par_langue.items():
            soucis += verifier(cle, texte)
            localisations[langue] = {
                "stringUnit": {"state": "translated", "value": texte}
            }
            ajoutees += 1

    if soucis:
        print(f"\n{len(soucis)} incohérence(s) d'emplacement :")
        for s in soucis[:20]:
            print("  ", s)
        if strict:
            raise SystemExit("catalogue non écrit : corrigez les emplacements")

    if inconnues:
        print(f"\n{len(inconnues)} clé(s) absente(s) du catalogue (créées) :")
        for c in inconnues[:15]:
            print("  ", repr(c))

    with open(CHEMIN, "w", encoding="utf-8") as f:
        json.dump(catalogue, f, ensure_ascii=False, indent=2)
        f.write("\n")

    langues = set()
    for entree in chaines.values():
        langues.update((entree.get("localizations") or {}).keys())
    print(f"\n{ajoutees} traductions écrites")
    print(f"{len(chaines)} clés · {len(langues)} langues : {' '.join(sorted(langues))}")


def etat():
    """Combien de clés traduites, langue par langue ?"""
    catalogue = charger()
    chaines = catalogue.get("strings", {})
    compte: dict[str, int] = {}
    for entree in chaines.values():
        for langue in (entree.get("localizations") or {}):
            compte[langue] = compte.get(langue, 0) + 1
    total = len(chaines)
    print(f"{total} clés au catalogue")
    for langue in sorted(compte):
        n = compte[langue]
        print(f"  {langue:<8} {n:4d}/{total}  {'complet' if n == total else 'incomplet'}")
    return chaines


if __name__ == "__main__":
    etat()

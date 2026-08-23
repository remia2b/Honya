# -*- coding: utf-8 -*-
"""Rassemble les clés traduisibles extraites par Xcode pendant la compilation.

Chaque .stringsdata contient : {"tables": {"Localizable": [{"key": …}, …]}}.
On en tire la liste complète, spécificateurs de format compris.
"""
import glob
import json
import os

cles = set()

for chemin in glob.glob("/tmp/cles/*.json"):
    with open(chemin, encoding="utf-8") as fichier:
        donnees = json.load(fichier)
    for entrees in (donnees.get("tables") or {}).values():
        if not isinstance(entrees, list):
            continue
        for entree in entrees:
            cle = (entree or {}).get("key")
            if cle:
                cles.add(cle)

os.makedirs("Design", exist_ok=True)
with open("Design/cles-extraites.json", "w", encoding="utf-8") as fichier:
    json.dump(sorted(cles), fichier, ensure_ascii=False, indent=1)
    fichier.write("\n")

print(len(cles), "clés extraites")
for cle in sorted(k for k in cles if "%" in k):
    print("  avec emplacement :", repr(cle))

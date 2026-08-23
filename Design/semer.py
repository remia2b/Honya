# -*- coding: utf-8 -*-
"""Inscrit au catalogue toutes les clés extraites par Xcode.

Sans cette étape, une clé absente du catalogue passe inaperçue : elle
s'affiche en français quelle que soit la langue, sans qu'aucun outil ne
signale l'oubli.
"""
import json
import os

RACINE = os.path.dirname(__file__)
CATALOGUE = os.path.join(RACINE, "..", "Honya", "Localizable.xcstrings")
EXTRAITES = os.path.join(RACINE, "cles-extraites.json")

with open(EXTRAITES, encoding="utf-8") as f:
    cles = json.load(f)

with open(CATALOGUE, encoding="utf-8") as f:
    catalogue = json.load(f)

chaines = catalogue.setdefault("strings", {})
ajoutees = 0
for cle in cles:
    if cle not in chaines:
        chaines[cle] = {}
        ajoutees += 1

# Les clés que le code n'utilise plus encombrent le catalogue et faussent
# le décompte de ce qui reste à traduire.
obsoletes = [c for c in chaines if c not in cles]

with open(CATALOGUE, "w", encoding="utf-8") as f:
    json.dump(catalogue, f, ensure_ascii=False, indent=2)
    f.write("\n")

print(f"{ajoutees} clés ajoutées · {len(chaines)} au total")
if obsoletes:
    print(f"\n{len(obsoletes)} clé(s) au catalogue mais absente(s) du code :")
    for c in obsoletes:
        print("   ", repr(c))

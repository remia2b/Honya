# -*- coding: utf-8 -*-
"""Agrandit le livre dans l'icône retenue, sans rien changer d'autre.

Le livre doit occuper davantage le carré : une fois rogné en squircle par
iOS, l'icône paraît plus pleine. Trois tailles pour comparer.

Usage : python Design/agrandir_livre.py <image_source> <dossier_sortie>
"""
import base64
import json
import os
import sys
import urllib.request

SOURCE = sys.argv[1]
DOSSIER = sys.argv[2] if len(sys.argv) > 2 else "."

CHEMIN_CLE = os.path.join(os.path.expanduser("~"), ".gemini_key")
with open(CHEMIN_CLE, encoding="utf-8") as f:
    CLE = f.read().strip()
assert CLE, "clé vide"

with open(SOURCE, "rb") as f:
    IMAGE = base64.b64encode(f.read()).decode()

COMMUN = (
    "Keep EVERYTHING else identical to the attached image: the exact same "
    "open book (same shape, same fanning cream pages, same warm glow between "
    "the pages, same terracotta cover, same coral ribbon bookmark, same "
    "materials and lighting), and the exact same orange gradient background "
    "colors. Do not restyle, do not redraw, do not change the palette. "
    "The book stays centered and seen straight from the front, with its soft "
    "contact shadow. "
    "The image remains a plain FULL-BLEED SQUARE: background reaching all "
    "four corners, no rounded corners, no frame, no border, no margin band, "
    "no icon plate behind the book. No text, no logo."
)

VARIANTES = [
    ("G1_plus_15",
     "Scale the book up by about 15% so it occupies more of the frame, "
     "keeping comfortable empty margins all around. " + COMMUN),
    ("G2_plus_30",
     "Scale the book up by about 30% so it fills a large part of the frame "
     "— the kind of generous sizing Apple uses, where the subject nearly "
     "reaches the safe area but is never cropped. " + COMMUN),
    ("G3_plus_45",
     "Scale the book up by about 45% so it dominates the frame and fills it "
     "boldly, still entirely visible with only a small margin on each side. "
     + COMMUN),
]

MODELES = ["gemini-3-pro-image-preview", "gemini-2.5-flash-image"]


def retoucher(modele, prompt):
    corps = {
        "contents": [{"parts": [
            {"inline_data": {"mime_type": "image/png", "data": IMAGE}},
            {"text": prompt},
        ]}],
        "generationConfig": {
            "responseModalities": ["IMAGE"],
            "imageConfig": {"aspectRatio": "1:1", "imageSize": "2K"},
        },
    }
    requete = urllib.request.Request(
        f"https://generativelanguage.googleapis.com/v1beta/models/{modele}:generateContent",
        data=json.dumps(corps).encode(),
        headers={"Content-Type": "application/json", "x-goog-api-key": CLE},
        method="POST",
    )
    with urllib.request.urlopen(requete, timeout=180) as reponse:
        donnees = json.load(reponse)
    for part in donnees["candidates"][0]["content"]["parts"]:
        blob = part.get("inlineData") or part.get("inline_data")
        if blob and blob.get("data"):
            return base64.b64decode(blob["data"])
    raise RuntimeError("pas d'image dans la réponse")


modele_utilise = None
for nom, prompt in VARIANTES:
    donnees = None
    for modele in ([modele_utilise] if modele_utilise else MODELES):
        try:
            donnees = retoucher(modele, prompt)
            modele_utilise = modele
            break
        except Exception as erreur:
            print(f"  {modele} : {type(erreur).__name__} {erreur}")
    if donnees is None:
        print(f"ECHEC {nom}")
        continue
    chemin = os.path.join(DOSSIER, f"agrandi_{nom}.png")
    with open(chemin, "wb") as f:
        f.write(donnees)
    print(f"OK {nom} ({modele_utilise}, {len(donnees) // 1024} Ko)")

print("termine")

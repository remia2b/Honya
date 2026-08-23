# -*- coding: utf-8 -*-
"""Retouche d'une icône existante via l'API Gemini (Nano Banana Pro) :
le LIVRE est conservé à l'identique, seul le fond change — la plaque
carrée arrondie d'icône est retirée, remplacée par un dégradé orange
lumineux qui remplit tout le carré.

La clé est lue dans C:/Users/<vous>/.gemini_key — jamais affichée.

Usage : python Design/retoucher_icone.py <image_source> <dossier_sortie>
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

PRESERVER = (
    "PRESERVE THE BOOK EXACTLY AS IT IS. The open book — its shape, its "
    "fanning cream pages, the warm glow between the pages, the orange cover, "
    "the coral ribbon bookmark, its lighting, materials and proportions — "
    "must stay pixel-identical. Do not redraw it, do not restyle it, do not "
    "move it. "
    "CHANGE ONLY THE BACKGROUND: completely remove the rounded-square icon "
    "plate / tile / squircle panel that sits behind the book, and remove any "
    "border, frame, outline or drop shadow belonging to that plate. "
    "The result must be a plain FULL-BLEED SQUARE image whose background "
    "reaches all four corners: no rounded corners, no frame, no margin, no "
    "sticker edge, no device mockup. Keep the book's own soft contact shadow "
    "on the new background. No text, no letters, no logo."
)

VARIANTES = [
    ("V1_fond_lumineux",
     "Replace the background with a smooth luminous orange gradient, bright "
     "and sunny: #FFA424 at the top fading to #FF7A18 at the bottom. Clean "
     "and even, no texture, no grain, no vignette. " + PRESERVER),
    ("V2_fond_mandarine",
     "Replace the background with a smooth vivid mandarin gradient: #FFB13C "
     "at the top fading to #F97316 at the bottom, slightly warmer and "
     "brighter than the original. Perfectly clean and smooth. " + PRESERVER),
    ("V3_fond_soleil",
     "Replace the background with a soft radial glow: a warm bright "
     "#FFC15A light centered behind the book, fading outward to #F5761A at "
     "the edges, so the book seems lit from behind. Very smooth, no banding, "
     "no texture. " + PRESERVER),
    ("V4_livre_plus_grand",
     "Replace the background with a smooth luminous orange gradient (#FFA424 "
     "top to #FF7A18 bottom) and scale the book up slightly so it occupies "
     "more of the frame, still fully visible and centered with comfortable "
     "margins. " + PRESERVER),
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
    chemin = os.path.join(DOSSIER, f"retouche_{nom}.png")
    with open(chemin, "wb") as f:
        f.write(donnees)
    print(f"OK {nom} ({modele_utilise}, {len(donnees) // 1024} Ko)")

print("termine")

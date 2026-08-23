# -*- coding: utf-8 -*-
"""Propositions d'icône Honya via l'API Gemini (Nano Banana Pro).

La clé est lue dans C:/Users/<vous>/.gemini_key — jamais dans le code,
jamais dans le dépôt, jamais affichée.

Direction retenue (D) : livre ouvert VU DE FACE dont les pages s'éventent
en arc symétrique, marque-page corail, rendu 3D lisse, fond orange
LUMINEUX en dégradé. L'image est un carré plein : surtout pas de coins
arrondis ni de cadre d'icône dessinés dedans.

Usage : python Design/generer_icones.py <dossier_sortie> [suffixe]
"""
import base64
import json
import os
import sys
import urllib.request

DOSSIER = sys.argv[1] if len(sys.argv) > 1 else "."
SUFFIXE = sys.argv[2] if len(sys.argv) > 2 else ""

CHEMIN_CLE = os.path.join(os.path.expanduser("~"), ".gemini_key")
with open(CHEMIN_CLE, encoding="utf-8") as f:
    CLE = f.read().strip()
assert CLE, "clé vide"

# L'interdit le plus important : ne jamais dessiner la forme de l'icône.
CADRE = (
    "CRITICAL FRAMING RULE: the output is a plain FULL-BLEED SQUARE image. "
    "The orange gradient background must reach and fill all four corners "
    "completely, right to the pixel edge. Do NOT draw an app icon shape "
    "inside the image: no rounded corners, no squircle, no rounded-rectangle "
    "plate or tile behind the book, no border, no frame, no outline, no "
    "white or light margin anywhere, no drop shadow around the image edges, "
    "no device mockup, no sticker look."
)

BASE = (
    "iOS app icon artwork: a single open book seen straight from the FRONT, "
    "perfectly symmetrical and centered, facing the viewer — NOT a "
    "three-quarter view, no perspective tilt. Its many pages fan dramatically "
    "upward and outward on both sides in a symmetrical arc, like a butterfly "
    "of paper, with soft curved page edges catching the light. A coral red "
    "ribbon bookmark falls straight down from the center of the spine. "
    "Rendering: clean modern 3D, perfectly SMOOTH matte surfaces, soft studio "
    "lighting, gentle soft shadows, subtle rounded bevels, premium Apple-style "
    "icon craft. "
    "STRICTLY AVOID: fluffy or furry or felt or plush or fabric textures, "
    "visible fibers, film grain, noise, sparkles, stars, dashes or tick marks, "
    "text, letters, numbers, logos. " + CADRE
)

FOND_CLAIR = (
    "Background: a luminous vivid orange gradient, bright and sunny "
    "(#FFA424 at the top fading to #FF7A18 at the bottom), clean and smooth, "
    "no texture, no vignette. "
)

PROPOSITIONS = [
    ("D1_eventail_clair",
     FOND_CLAIR + "Cream ivory pages, warm orange book cover visible as a "
     "slim base under the pages, coral ribbon. " + BASE),
    ("D2_eventail_serre",
     FOND_CLAIR + "The book is generously sized and fills most of the frame, "
     "cropped slightly by the left and right edges. Cream pages, deep orange "
     "cover, coral ribbon. " + BASE),
    ("D3_eventail_dense",
     FOND_CLAIR + "Very many thin pages in the fan — a dense, richly layered "
     "arc of cream paper on each side, glowing warm orange in the depths "
     "between the pages, slim orange cover at the base, coral ribbon. " + BASE),
    ("D4_eventail_blanc",
     FOND_CLAIR + "Bright white and pale ivory pages for maximum contrast "
     "against the orange, a thin amber-orange cover, and a vivid coral "
     "ribbon. Crisp, airy, high contrast, very readable at small size. "
     + BASE),
]

MODELES = ["gemini-3-pro-image-preview", "gemini-2.5-flash-image"]


def generer(modele, prompt):
    corps = {
        "contents": [{"parts": [{"text": prompt}]}],
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
for nom, prompt in PROPOSITIONS:
    donnees = None
    for modele in ([modele_utilise] if modele_utilise else MODELES):
        try:
            donnees = generer(modele, prompt)
            modele_utilise = modele
            break
        except Exception as erreur:
            print(f"  {modele} : {type(erreur).__name__} {erreur}")
    if donnees is None:
        print(f"ECHEC {nom}")
        continue
    chemin = os.path.join(DOSSIER, f"proposition{SUFFIXE}_{nom}.png")
    with open(chemin, "wb") as f:
        f.write(donnees)
    print(f"OK {nom} ({modele_utilise}, {len(donnees) // 1024} Ko)")

print("termine")

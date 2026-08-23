# -*- coding: utf-8 -*-
"""Agrandit UNIQUEMENT le livre dans l'icône, sans toucher au fond.

Zoomer l'image entière décalerait le dégradé et changerait sa couleur. Ici
le livre est détouré, agrandi seul, puis reposé sur le fond d'origine
reconstruit — mêmes couleurs au pixel près.

Aucune perte de qualité : on travaille en 2048 alors que l'icône finale
fait 1024, donc l'agrandissement reste du suréchantillonnage.

Usage : python Design/agrandir_sujet.py <source.png> <sortie.png> [facteur] [descente]
La descente est un pourcentage de la hauteur : positif = le livre descend.
"""
import sys

import numpy as np
from PIL import Image, ImageFilter

SOURCE = sys.argv[1]
SORTIE = sys.argv[2]
FACTEUR = float(sys.argv[3]) if len(sys.argv) > 3 else 1.38
DESCENTE = float(sys.argv[4]) if len(sys.argv) > 4 else 0.0

original = Image.open(SOURCE).convert("RGB")
T = original.size[0]
im = np.asarray(original).astype(np.float32)

# --- 1) Détourer le livre : écart au fond, estimé ligne par ligne aux bords
bords = np.concatenate([im[:, :150], im[:, T - 150:]], axis=1)
modele = np.median(bords, axis=1)
ecart = np.abs(im - modele[:, None, :]).max(axis=2)
sujet = ecart > 38.0            # le halo du fond plafonne à 33

boite = np.where(sujet)
y0, y1 = boite[0].min(), boite[0].max()
x0, x1 = boite[1].min(), boite[1].max()
print(f"livre : x[{x0}-{x1}] y[{y0}-{y1}]")

# Élargir le masque pour englober l'ombre portée et la pénombre.
masque = Image.fromarray((sujet * 255).astype(np.uint8))
masque = masque.filter(ImageFilter.MaxFilter(9))
for _ in range(9):
    masque = masque.filter(ImageFilter.MaxFilter(9))
masque = masque.filter(ImageFilter.GaussianBlur(6))
connu = np.asarray(masque).astype(np.float32) / 255.0 < 0.5   # fond sûr

# --- 2) Reconstruire le fond derrière le livre (diffusion)
petit = 384
reduc = lambda a: np.asarray(
    Image.fromarray(a.astype(np.uint8)).resize((petit, petit), Image.BILINEAR)
).astype(np.float32)
fond_p = reduc(im.reshape(T, T, 3))
connu_p = reduc((connu * 255).astype(np.uint8)[:, :, None].repeat(3, axis=2))[:, :, 0] > 127

# Amorce : la valeur du fond de la même ligne.
modele_p = np.asarray(
    Image.fromarray(modele[:, None, :].repeat(8, axis=1).astype(np.uint8))
    .resize((8, petit), Image.BILINEAR)
).astype(np.float32)[:, 0, :]
travail = np.where(connu_p[:, :, None], fond_p, modele_p[:, None, :])

for _ in range(260):
    flou = np.asarray(
        Image.fromarray(travail.clip(0, 255).astype(np.uint8))
        .filter(ImageFilter.GaussianBlur(2.2))
    ).astype(np.float32)
    travail = np.where(connu_p[:, :, None], fond_p, flou)

fond = np.asarray(
    Image.fromarray(travail.clip(0, 255).astype(np.uint8)).resize((T, T), Image.BICUBIC)
).astype(np.float32)
# Loin du livre, le fond reste celui d'origine, au pixel près.
fond = np.where(connu[:, :, None], im, fond)

# --- 3) Le calque du livre : opaque sur le livre, translucide sur l'ombre
ecart_fond = np.abs(im - fond).max(axis=2)
alpha = np.clip((ecart_fond - 2.0) / 26.0, 0.0, 1.0)
alpha = np.asarray(
    Image.fromarray((alpha * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8))
).astype(np.float32) / 255.0

calque = np.dstack([im, alpha * 255]).astype(np.uint8)
calque = Image.fromarray(calque, "RGBA")

# --- 4) Agrandir le calque seul, puis le recentrer
grand = calque.resize((int(T * FACTEUR), int(T * FACTEUR)), Image.LANCZOS)
cx = (x0 + x1) / 2 * FACTEUR
cy = (y0 + y1) / 2 * FACTEUR
dx = int(round(T / 2 - cx))
dy = int(round(T / 2 - cy + T * DESCENTE / 100))

resultat = Image.fromarray(fond.clip(0, 255).astype(np.uint8), "RGB")
resultat.paste(grand, (dx, dy), grand)
resultat.save(SORTIE, "PNG")

nx0, nx1 = x0 * FACTEUR + dx, x1 * FACTEUR + dx
ny0, ny1 = y0 * FACTEUR + dy, y1 * FACTEUR + dy
print(f"facteur {FACTEUR} -> marges g/d {nx0:.0f}/{T - nx1:.0f}, h/b {ny0:.0f}/{T - ny1:.0f}")
print("ecrit :", SORTIE)

# -*- coding: utf-8 -*-
"""Aperçu d'une icône telle qu'iOS la montrera : masque squircle (superellipse
à la Apple, pas un simple arrondi), grande vignette, tailles réelles
d'écran d'accueil / réglages / notification, et une planche de comparaison
entre plusieurs candidates posées sur un fond d'écran.

Usage : python Design/mockup_icone.py <sortie.png> <icone1.png> [icone2.png ...]
"""
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont


def squircle(taille, n=5.0, sur=4):
    """Masque en superellipse |x|^n + |y|^n = 1 — la vraie forme des icônes."""
    grand = taille * sur
    masque = Image.new("L", (grand, grand), 0)
    dessin = ImageDraw.Draw(masque)
    points = []
    pas = 720
    for i in range(pas + 1):
        t = i / pas * 2 * 3.14159265358979
        import math
        c, s = math.cos(t), math.sin(t)
        x = math.copysign(abs(c) ** (2 / n), c)
        y = math.copysign(abs(s) ** (2 / n), s)
        points.append((grand / 2 + x * grand / 2, grand / 2 + y * grand / 2))
    dessin.polygon(points, fill=255)
    return masque.resize((taille, taille), Image.LANCZOS)


def icone(source, taille, ombre=True):
    """L'icône masquée en squircle, avec son ombre portée, sur fond transparent."""
    image = Image.open(source).convert("RGB").resize((taille, taille), Image.LANCZOS)
    masque = squircle(taille)
    vignette = Image.new("RGBA", (taille, taille), (0, 0, 0, 0))
    vignette.paste(image, (0, 0), masque)
    if not ombre:
        return vignette
    marge = max(6, taille // 12)
    toile = Image.new("RGBA", (taille + marge * 2, taille + marge * 2), (0, 0, 0, 0))
    ombre_img = Image.new("RGBA", toile.size, (0, 0, 0, 0))
    ombre_img.paste((0, 0, 0, 110), (marge, marge + marge // 3), masque)
    ombre_img = ombre_img.filter(ImageFilter.GaussianBlur(marge / 2.2))
    toile.alpha_composite(ombre_img)
    toile.alpha_composite(vignette, (marge, marge))
    return toile


def police(taille, gras=False):
    for nom in (["seguisb.ttf", "segoeuib.ttf"] if gras else ["segoeui.ttf"]):
        try:
            return ImageFont.truetype(nom, taille)
        except OSError:
            continue
    return ImageFont.load_default()


SORTIE = sys.argv[1]
SOURCES = sys.argv[2:]
assert SOURCES, "aucune icône fournie"

L, H = 1600, 1000 + 220 * ((len(SOURCES) + 2) // 3)
planche = Image.new("RGB", (L, H), (18, 18, 20))

# Fond d'écran de l'aperçu : un dégradé sombre chaud.
for y in range(1000):
    t = y / 1000
    planche.paste(
        (int(28 + 22 * t), int(24 + 16 * t), int(34 + 10 * t)),
        (0, y, L, y + 1),
    )

titre = police(34, gras=True)
libelle = police(22)
petit = police(17)
dessin = ImageDraw.Draw(planche)

# --- Colonne de gauche : la grande vignette de la première icône
grande = icone(SOURCES[0], 460)
planche.paste(grande, (70, 120), grande)
dessin.text((70, 60), "Écran d'accueil (grande)", font=titre, fill=(240, 240, 245))

# Le nom sous l'icône, comme sur l'écran d'accueil.
nom = police(30)
largeur_nom = dessin.textlength("Honya", font=nom)
dessin.text((70 + 230 - largeur_nom / 2, 640), "Honya", font=nom, fill=(255, 255, 255))

# --- Colonne de droite : les tailles réelles du système
x0 = 640
dessin.text((x0, 60), "Tailles réelles à l'écran", font=titre, fill=(240, 240, 245))
tailles = [
    (180, "180 px — écran d'accueil"),
    (120, "120 px — Spotlight"),
    (87, "87 px — Réglages"),
    (60, "60 px — notifications"),
]
y = 130
for taille, texte in tailles:
    vignette = icone(SOURCES[0], taille)
    planche.paste(vignette, (x0, y), vignette)
    dessin.text((x0 + 200, y + taille // 2 - 12), texte, font=libelle, fill=(200, 200, 210))
    y += taille + 40

# --- Une rangée façon écran d'accueil, avec des voisines grises
dessin.text((x0, y + 10), "Parmi d'autres apps", font=titre, fill=(240, 240, 245))
y += 70
voisine_masque = squircle(120)
for i in range(5):
    x = x0 + i * 150
    if i == 2:
        vignette = icone(SOURCES[0], 120)
        planche.paste(vignette, (x, y), vignette)
    else:
        grise = Image.new("RGB", (120, 120), (58 + i * 6, 58 + i * 5, 66 + i * 4))
        planche.paste(grise, (x + 10, y + 10), voisine_masque)

# --- Bandeau du bas : la comparaison des candidates
if len(SOURCES) > 1:
    yb = 1010
    dessin.text((70, yb - 60), "Comparaison des candidates", font=titre, fill=(240, 240, 245))
    for index, source in enumerate(SOURCES):
        colonne = index % 3
        rangee = index // 3
        x = 70 + colonne * 500
        yy = yb + rangee * 220
        vignette = icone(source, 160)
        planche.paste(vignette, (x, yy), vignette)
        etiquette = source.replace("\\", "/").split("/")[-1].replace(".png", "")
        dessin.text((x + 200, yy + 60), etiquette, font=libelle, fill=(225, 225, 232))
        mini = icone(source, 60)
        planche.paste(mini, (x + 200, yy + 95), mini)

planche.save(SORTIE, "PNG")
print("ecrit :", SORTIE)

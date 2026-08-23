# -*- coding: utf-8 -*-
"""L'icône de Honya, style « peluche 3D » d'Icon Composer :
fond orange franc, un grand livre ouvert doux et rebondi qui déborde du
cadre, lumière studio, marque-page, petits accents blancs. Rendu en 2048
puis réduit en 1024 RGB (sans alpha — Apple refuse la transparence).

Usage : python Design/icone_plush.py <sortie.png>
"""
import math
import sys
from PIL import Image, ImageDraw, ImageFilter

S = 2048  # espace de travail (supersampling x2)


def bezier(points, n=90):
    """Échantillonne une bézier (2 à 4 points de contrôle) en n sommets."""
    def interp(a, b, t):
        return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)

    sortie = []
    for i in range(n + 1):
        t = i / n
        pts = list(points)
        while len(pts) > 1:
            pts = [interp(pts[j], pts[j + 1], t) for j in range(len(pts) - 1)]
        sortie.append(pts[0])
    return sortie


def masque(polygones, flou=0):
    m = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(m)
    for poly in polygones:
        d.polygon(poly, fill=255)
    if flou:
        m = m.filter(ImageFilter.GaussianBlur(flou))
    return m


def masque_rrect(boite, rayon, flou=0):
    m = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(m)
    d.rounded_rectangle(boite, radius=rayon, fill=255)
    if flou:
        m = m.filter(ImageFilter.GaussianBlur(flou))
    return m


def masque_ellipse(boite, flou=0):
    m = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(m)
    d.ellipse(boite, fill=255)
    if flou:
        m = m.filter(ImageFilter.GaussianBlur(flou))
    return m


def masque_trait(chemin, largeur, flou=0):
    m = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(m)
    d.line(chemin, fill=255, width=int(largeur), joint="curve")
    if flou:
        m = m.filter(ImageFilter.GaussianBlur(flou))
    return m


def poser(fond, couleur, m):
    fond.paste(Image.new("RGB", (S, S), couleur), (0, 0), m)


def degrade_vertical(y0, y1, alpha_haut, alpha_bas, dans=None, flou=0):
    m = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(m)
    if alpha_haut > 0:
        d.rectangle([0, 0, S, int(y0)], fill=alpha_haut)
    if alpha_bas > 0:
        d.rectangle([0, int(y1), S, S], fill=alpha_bas)
    hauteur = max(1, int(y1) - int(y0))
    for y in range(int(y0), int(y1)):
        t = (y - y0) / hauteur
        a = int(alpha_haut + (alpha_bas - alpha_haut) * t)
        d.line([(0, y), (S, y)], fill=max(0, min(255, a)))
    if flou:
        m = m.filter(ImageFilter.GaussianBlur(flou))
    if dans is not None:
        m = Image.composite(m, Image.new("L", (S, S), 0), dans)
    return m


def intersection(m1, m2):
    return Image.composite(m1, Image.new("L", (S, S), 0), m2)


def attenuer(m, facteur):
    return m.point(lambda p: int(p * facteur))


# ---------------------------------------------------------------- le fond
img = Image.new("RGB", (S, S), (240, 115, 42))
img.paste(Image.new("RGB", (S, S), (248, 136, 60)),
          (0, 0), attenuer(degrade_vertical(0, int(S * 0.7), 130, 0, flou=60), 1))
img.paste(Image.new("RGB", (S, S), (219, 95, 30)),
          (0, 0), degrade_vertical(int(S * 0.62), S, 0, 110, flou=80))

# ------------------------------------------------------- l'ombre au sol
poser(img, (146, 52, 12),
      attenuer(masque_ellipse((150, 1560, 1898, 1830), flou=85), 0.5))

# ------------------------------------------------------------ la couverture
# Un grand coussin qui déborde du cadre à gauche et à droite.
COUV = masque_rrect((-60, 700, 2108, 1640), 270)
poser(img, (176, 60, 16), COUV)
poser(img, (212, 82, 26), intersection(degrade_vertical(660, 1000, 190, 0, flou=40), COUV))
poser(img, (128, 42, 12), intersection(degrade_vertical(1300, 1660, 0, 200, flou=40), COUV))

# ---------------------------------------------------------------- les pages
GOUT = 1024

def cote_pages(gauche=True):
    """Le contour d'une page : gouttière -> gonflé -> bord -> ventre -> gouttière."""
    pts = (
        bezier([(GOUT, 876), (880, 812), (540, 768), (172, 844)], 70)
        + bezier([(172, 844), (140, 1080), (168, 1320)], 40)
        + bezier([(168, 1320), (620, 1452), (GOUT, 1492)], 70)
    )
    if not gauche:
        pts = [(2 * GOUT - x, y) for (x, y) in pts]
    return pts

PAGES = masque([cote_pages(True), cote_pages(False)])

# L'ombre portée des pages sur la couverture (les décolle, plush).
poser(img, (110, 36, 10),
      attenuer(masque([cote_pages(True), cote_pages(False)], flou=34), 0.5))
poser(img, (250, 240, 222), PAGES)

# Modelé : crème lumineux en haut, ambre chaud vers le ventre.
poser(img, (255, 250, 238), intersection(degrade_vertical(700, 1020, 220, 0, flou=30), PAGES))
poser(img, (228, 206, 172), intersection(degrade_vertical(1180, 1500, 0, 160, flou=30), PAGES))

# La tranche : trois fins feuillets qui suivent le ventre des pages.
for i, (decal, teinte) in enumerate([(46, (222, 198, 162)), (88, (214, 188, 150)), (128, (206, 178, 140))]):
    chemin = (bezier([(240, 1320 - decal + 46), (620, 1452 - decal), (GOUT, 1492 - decal)], 50)
              + bezier([(GOUT, 1492 - decal), (2 * GOUT - 620, 1452 - decal), (2 * GOUT - 240, 1320 - decal + 46)], 50))
    poser(img, teinte, intersection(attenuer(masque_trait(chemin, 7, flou=2), 0.75), PAGES))

# La gouttière : un pli net dans un creux doux.
poser(img, (204, 168, 126),
      intersection(attenuer(masque_rrect((GOUT - 130, 820, GOUT + 130, 1500), 130, flou=60), 0.7), PAGES))
poser(img, (168, 128, 88),
      intersection(attenuer(masque_rrect((GOUT - 52, 840, GOUT + 52, 1490), 52, flou=24), 0.8), PAGES))
poser(img, (122, 86, 56),
      intersection(attenuer(masque_rrect((GOUT - 14, 856, GOUT + 14, 1488), 14, flou=8), 0.85), PAGES))

# Reflet studio en travers du haut des pages.
reflet = masque([bezier([(260, 800), (640, 680), (1408, 680), (1788, 800)], 60)
                 + bezier([(1788, 800), (1408, 930), (640, 930), (260, 800)], 60)], flou=55)
poser(img, (255, 253, 244), intersection(attenuer(reflet, 0.45), PAGES))

# ----------------------------------------------------------- le marque-page
ruban = [(GOUT - 64, 1430), (GOUT + 64, 1430), (GOUT + 64, 1790),
         (GOUT, 1706), (GOUT - 64, 1790)]
poser(img, (110, 36, 10), attenuer(masque([ruban], flou=30), 0.5))
RUB = masque([ruban])
poser(img, (228, 76, 76), RUB)
poser(img, (255, 134, 124), intersection(degrade_vertical(1420, 1540, 150, 0, flou=16), RUB))
poser(img, (166, 44, 48), intersection(degrade_vertical(1640, 1800, 0, 150, flou=16), RUB))

# ---------------------------------------------- les petits accents blancs
def capsule(centre, angle_deg, longueur, largeur):
    a = math.radians(angle_deg)
    dx, dy = math.cos(a) * longueur / 2, -math.sin(a) * longueur / 2
    x0, y0 = centre[0] - dx, centre[1] - dy
    x1, y1 = centre[0] + dx, centre[1] + dy
    m = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(m)
    d.line([(x0, y0), (x1, y1)], fill=255, width=int(largeur))
    for (px, py) in [(x0, y0), (x1, y1)]:
        d.ellipse((px - largeur / 2, py - largeur / 2, px + largeur / 2, py + largeur / 2), fill=255)
    return m

for centre, angle, longueur in [((1408, 424), 64, 150), ((1556, 528), 38, 122), ((1636, 678), 12, 96)]:
    poser(img, (168, 68, 20), attenuer(capsule((centre[0] + 10, centre[1] + 16), angle, longueur, 54), 0.35))
    poser(img, (255, 250, 242), capsule(centre, angle, longueur, 54))

# ------------------------------------------------------------------ export
final = img.resize((1024, 1024), Image.LANCZOS)
sortie = sys.argv[1] if len(sys.argv) > 1 else "icone.png"
final.save(sortie, "PNG")
print("ecrit :", sortie)

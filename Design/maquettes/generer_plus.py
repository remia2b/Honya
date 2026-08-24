# -*- coding: utf-8 -*-
"""Trois maquettes de l'écran Honya+, à 393 × 852 points.

Chaque valeur écrite ici se reporte telle quelle dans SwiftUI.
Les couvertures sont embarquées en base64 : une maquette avec des
rectangles gris ne se juge pas.
"""
import json
import os

DOSSIER = os.path.dirname(os.path.abspath(__file__))
COUV = json.load(open(os.path.join(DOSSIER, "couvertures.json"), encoding="utf-8"))
ORDRE = ["la-femme-de-m-nage", "one-piece", "jamais-plus", "demon-slayer",
         "verity", "dune", "chainsaw-man", "le-petit-prince", "1984"]


def img(cle, style=""):
    return f'<img class="couv" src="{COUV[cle]["data"]}" alt="" style="{style}">'


ETAT = ('<div class="etat"><span>9:41</span><div class="signaux">'
        '<span style="height:5px"></span><span style="height:8px"></span>'
        '<span style="height:11px"></span><span style="height:13px"></span>'
        '<div class="jauge"></div></div></div>')


def ligne(symbole, titre, detail):
    return (f'<div class="avantage"><div class="pic">{symbole}</div>'
            f'<div><b>{titre}</b><span>{detail}</span></div></div>')


AVANTAGES = [
    ("⌘", "Séries automatiques sans limite",
     "un tome ajouté, tout le rayon apparaît"),
    ("⌁", "Alertes à chaque nouveau tome",
     "sur toutes vos séries, pas une seule"),
    ("⊞", "Scan illimité, étagères entières",
     "une rangée de codes-barres à la volée"),
    ("◷", "Tout votre historique de lecture",
     "records, heatmap de l'année, humeurs"),
    ("♥", "Prêts, citations et étagères",
     "sans compteur qui vous arrête"),
]


# ══════════════════════════════════════════════════════════════════
# A — LA LISTE  ·  sobre, verticale, la plus proche d'Apple
# ══════════════════════════════════════════════════════════════════

def a_liste():
    # Un rayon discret en tête : l'écran de vente doit ressembler à l'app.
    bandeau = "".join(img(cle, f"--i:{i};") for i, cle in enumerate(ORDRE[:6]))
    return f'''
    <div class="ecran">
      {ETAT}
      <div class="corps" style="overflow:hidden;">
        <div class="fermer">✕</div>
        <div class="bandeau">{bandeau}</div>
        <div style="padding:14px 28px 0;">
          <div class="marque">Honya<span>+</span></div>
          <p class="promesse">Le libraire qui range<br>à votre place.</p>
        </div>
        <div class="liste">{"".join(ligne(*a) for a in AVANTAGES[:4])}</div>
        <div style="flex:1"></div>
        <div class="offres">
          <div class="offre">
            <div><b>Mensuel</b><span>sans engagement</span></div>
            <div class="tarif">4,99 €</div>
          </div>
          <div class="offre choisie">
            <div class="ruban">7 jours offerts</div>
            <div><b>Annuel</b><span>2,50 € par mois</span></div>
            <div class="tarif">29,99 €</div>
          </div>
          <div class="offre">
            <div><b>À vie</b><span>une seule fois</span></div>
            <div class="tarif">69,99 €</div>
          </div>
        </div>
        <div class="bas">
          <div class="bouton">Essayer 7 jours gratuitement</div>
          <div class="mentions">Puis 29,99 €/an. Résiliable à tout moment.</div>
        </div>
      </div>
      <div class="barre"></div>
    </div>'''


# ══════════════════════════════════════════════════════════════════
# B — LE RAYON  ·  les couvertures en tête, comme l'écran d'ouverture
# ══════════════════════════════════════════════════════════════════

def b_rayon():
    bandeau = "".join(
        img(cle, f"--i:{i};") for i, cle in enumerate(ORDRE[:7])
    )
    return f'''
    <div class="ecran">
      <div class="rayon">{bandeau}</div>
      <div class="fondu"></div>
      {ETAT}
      <div class="corps">
        <div class="fermer clair">✕</div>
        <div style="flex:1"></div>
        <div style="padding:0 28px;">
          <div class="marque grand">Honya<span>+</span></div>
          <p class="promesse grand">Votre bibliothèque<br>se range toute seule.</p>
        </div>
        <div class="liste serree">{"".join(ligne(*a) for a in AVANTAGES[:3])}</div>
        <div class="offres rangee">
          <div class="offre bloc">
            <b>Mensuel</b><div class="tarif">4,99 €</div><span>par mois</span>
          </div>
          <div class="offre bloc choisie">
            <div class="ruban">−50 %</div>
            <b>Annuel</b><div class="tarif">29,99 €</div><span>2,50 €/mois</span>
          </div>
          <div class="offre bloc">
            <b>À vie</b><div class="tarif">69,99 €</div><span>une fois</span>
          </div>
        </div>
        <div class="bas">
          <div class="bouton">Commencer l'essai gratuit</div>
          <div class="mentions">7 jours, puis 29,99 €/an · Restaurer un achat</div>
        </div>
      </div>
      <div class="barre"></div>
    </div>'''


# ══════════════════════════════════════════════════════════════════
# C — LE CONTEXTE  ·  ouvert depuis un verrou précis
# ══════════════════════════════════════════════════════════════════

def c_contexte():
    return f'''
    <div class="ecran">
      {ETAT}
      <div class="corps">
        <div class="fermer">✕</div>
        <div class="scene">
          <div class="pile">
            {img(ORDRE[1], "--r:-7deg; --x:-58px; --s:.88;")}
            {img(ORDRE[3], "--r:0deg; --x:0px; --s:1;")}
            {img(ORDRE[6], "--r:7deg; --x:58px; --s:.88;")}
            <div class="cadenas">◍</div>
          </div>
        </div>
        <div style="padding:0 30px; text-align:center;">
          <p class="titre-contexte">Votre 4<sup>e</sup> série</p>
          <p class="detail-contexte">Honya peut poser les 27 tomes de
            <b>Chainsaw&nbsp;Man</b> à votre place, dates de sortie comprises.
            Comme il l'a fait pour les trois précédentes.</p>
        </div>
        <div style="flex:1"></div>
        <div class="offres">
          <div class="offre choisie plate">
            <div><b>Honya+ annuel</b><span>7 jours offerts, puis 2,50 €/mois</span></div>
            <div class="tarif">29,99 €</div>
          </div>
        </div>
        <div class="bas">
          <div class="bouton">Essayer 7 jours gratuitement</div>
          <div class="lien">Voir toutes les offres</div>
          <div class="mentions">Résiliable à tout moment.</div>
        </div>
      </div>
      <div class="barre"></div>
    </div>'''


# ══════════════════════════════════════════════════════════════════
# D — LA ROUE  ·  au refus du premier écran de prix
# ══════════════════════════════════════════════════════════════════

SEGMENTS = [("−40 %", True), ("Rien", False), ("−15 %", True), ("Rien", False),
            ("−25 %", True), ("Rien", False), ("−10 %", True), ("Rien", False)]


def secteurs(rotation=0):
    """Huit parts égales, dessinées à l'arc. Portable en SwiftUI Path."""
    import math
    parts = []
    n = len(SEGMENTS)
    for i, (texte, gagnant) in enumerate(SEGMENTS):
        a0 = math.radians(i * 360 / n - 90 + rotation)
        a1 = math.radians((i + 1) * 360 / n - 90 + rotation)
        x0, y0 = 130 + 122 * math.cos(a0), 130 + 122 * math.sin(a0)
        x1, y1 = 130 + 122 * math.cos(a1), 130 + 122 * math.sin(a1)
        teinte = "#F6D9BC" if gagnant else "#FBF3E9"
        parts.append(f'<path d="M130 130 L{x0:.1f} {y0:.1f} A122 122 0 0 1 {x1:.1f} {y1:.1f} Z" '
                     f'fill="{teinte}" stroke="#E6D3BC" stroke-width="1"/>')
        am = math.radians((i + 0.5) * 360 / n - 90 + rotation)
        tx, ty = 130 + 84 * math.cos(am), 130 + 84 * math.sin(am)
        couleur = "#C25E0D" if gagnant else "#A79A88"
        parts.append(f'<text x="{tx:.1f}" y="{ty:.1f}" fill="{couleur}" font-size="15" '
                     f'font-weight="700" text-anchor="middle" dominant-baseline="middle">{texte}</text>')
    return "".join(parts)


def d_roue():
    return f'''
    <div class="ecran">
      {ETAT}
      <div class="corps">
        <div class="fermer">✕</div>
        <div style="padding:14px 30px 0; text-align:center;">
          <p class="titre-contexte">Tout le monde a droit<br>à une deuxième chance</p>
          <p class="detail-contexte">Votre premier tour n'a rien donné. Celui-ci
            est le bon — une seule fois, pour vous.</p>
        </div>
        <div class="scene-roue">
          <svg viewBox="0 0 260 260" class="roue">
            <circle cx="130" cy="130" r="124" fill="#FBF3E9" stroke="#E0CDB4" stroke-width="3"/>
            {secteurs(11)}
            <circle cx="130" cy="130" r="30" fill="#D96A12"/>
            <text x="130" y="130" fill="#FFF" font-size="13" font-weight="700"
                  text-anchor="middle" dominant-baseline="middle">TOURNER</text>
          </svg>
          <div class="fleche">▼</div>
        </div>
        <div style="flex:1"></div>
        <div class="bas">
          <div class="bouton">Faire tourner la roue</div>
          <div class="mentions">Sans obligation d'achat.</div>
        </div>
      </div>
      <div class="barre"></div>
    </div>'''


# ══════════════════════════════════════════════════════════════════
# E — LE GAIN  ·  le tarif réduit, révélé
# ══════════════════════════════════════════════════════════════════

def e_gain():
    return f'''
    <div class="ecran gagnant">
      {ETAT}
      <div class="corps">
        <div class="fermer clair">✕</div>
        <div style="flex:0.7"></div>
        <div style="padding:0 30px; text-align:center;">
          <div class="gros-gain">−40 %</div>
          <p class="titre-gain">La première année<br>à 17,99 €</p>
          <p class="detail-gain">Au lieu de 29,99 €. Se renouvelle ensuite au
            tarif normal, résiliable à tout moment.</p>
        </div>
        <div style="flex:0.5"></div>
        <div class="liste serree clair">{"".join(ligne(*a) for a in AVANTAGES[:3])}</div>
        <div style="flex:1"></div>
        <div class="bas">
          <div class="bouton blanc">Profiter des 17,99 €</div>
          <div class="mentions pale">Cette offre n'est proposée qu'une fois.</div>
        </div>
      </div>
      <div class="barre"></div>
    </div>'''


MAQUETTES = [
    ("A", "La liste", a_liste(),
     "<b>L'écran principal, depuis les réglages.</b> Un rayon en tête pour que la "
     "caisse ressemble à l'app, quatre avantages, trois offres empilées, l'annuel "
     "encadré. C'est la forme qu'Apple recommande et que tout le monde sait lire.",
     "SwiftUI : ScrollView + VStack + bandeau d'images"),
    ("C", "Le contexte", c_contexte(),
     "<b>Celle qui convertit le mieux.</b> Ouverte depuis un verrou précis, elle ne "
     "vend pas « Honya+ » mais la chose exacte qui manque à cette seconde. Une "
     "seule offre, une seule décision.",
     "SwiftUI : la même vue, paramétrée par le verrou déclencheur"),
    ("D", "La roue", d_roue(),
     "<b>Au refus, pas à l'ouverture.</b> Quand quelqu'un ferme A ou C sans "
     "acheter. Premier tour perdant, puis « tout le monde a droit à une deuxième "
     "chance ». C'est le mécanisme exact de Yazio, qui l'affiche jusqu'à 75 %.",
     "SwiftUI : Path en arcs + rotationEffect + spring"),
    ("E", "Le gain", e_gain(),
     "<b>Le tarif réduit, révélé.</b> −40 % sur la première année : 17,99 € au "
     "lieu de 29,99 €, puis renouvellement normal. C'est une offre "
     "d'introduction StoreKit, déclarée dans App Store Connect — la roue n'est "
     "que la mise en scène.",
     "SwiftUI : le même écran, produit d'introduction"),
]

PAGE = """<title>Honya+ en trois écrans</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500&display=swap">

<style>
  :root {
    --atelier:#E9E4DB; --trait:#CBC3B6; --encre:#211D18;
    --texte:#56504A; --discret:#8C8479; --accent:#D96A12;
    --s:0.74; --creme:#FCFAF6;
    --serif:'Iowan Old Style','Palatino Linotype',Palatino,'Times New Roman',serif;
    --sf:-apple-system,BlinkMacSystemFont,'SF Pro Text','Segoe UI Variable Text','Segoe UI',Roboto,sans-serif;
    --mono:'IBM Plex Mono',ui-monospace,Consolas,monospace;
  }
  @media (prefers-color-scheme: dark) {
    :root:not([data-theme="light"]) {
      --atelier:#16130E; --trait:#373127; --encre:#F3EEE4;
      --texte:#B6ADA0; --discret:#8B8276; --accent:#F09344;
    }
  }
  :root[data-theme="dark"] {
    --atelier:#16130E; --trait:#373127; --encre:#F3EEE4;
    --texte:#B6ADA0; --discret:#8B8276; --accent:#F09344;
  }

  * { box-sizing:border-box; }
  body { margin:0; background:var(--atelier); color:var(--texte);
         font-family:var(--sf); -webkit-font-smoothing:antialiased; }
  .page { max-width:1320px; margin:0 auto; padding:56px 28px 90px; }
  header { max-width:640px; }
  .surtitre { font-family:var(--mono); font-size:12px; letter-spacing:.14em;
              text-transform:uppercase; color:var(--discret); margin:0 0 14px; }
  h1 { font-family:var(--serif); font-size:clamp(32px,5vw,46px); line-height:1.1;
       font-weight:600; color:var(--encre); margin:0 0 16px; }
  header p { font-size:16.5px; line-height:1.62; margin:0 0 10px; max-width:60ch; }

  .grille { display:grid; grid-template-columns:repeat(auto-fit,minmax(292px,1fr));
            gap:54px 34px; margin-top:52px; }
  .bloc-maquette { display:flex; flex-direction:column; gap:15px; }
  .etiquette { display:flex; align-items:baseline; gap:10px; }
  .lettre { font-family:var(--mono); font-size:12px; font-weight:500; color:#FFF;
            background:var(--encre); border-radius:5px; padding:3px 7px; }
  .nom { font-family:var(--serif); font-size:21px; font-weight:600; color:var(--encre); }
  .note { font-size:14px; line-height:1.6; margin:0; }
  .note b { color:var(--encre); font-weight:600; }
  .cout { font-family:var(--mono); font-size:11.5px; color:var(--discret); margin:0;
          padding-top:3px; border-top:1px solid var(--trait); }

  .cadre { width:calc(393px * var(--s)); height:calc(852px * var(--s));
           border-radius:calc(56px * var(--s)); padding:calc(3px * var(--s));
           background:linear-gradient(150deg,#736C64,#2A2622 45%,#57514A);
           box-shadow:0 24px 48px -18px rgba(26,20,12,.5);
           overflow:hidden; }
  .ecran { width:393px; height:852px; transform:scale(var(--s)); transform-origin:top left;
           border-radius:53px; overflow:hidden; position:relative; background:var(--creme);
           color:#17130F; display:flex; flex-direction:column; }

  .etat { height:54px; padding:18px 34px 0; display:flex; justify-content:space-between;
          align-items:center; font-size:15px; font-weight:600; color:#17130F;
          flex:none; position:relative; z-index:6; }
  .signaux { display:flex; align-items:center; gap:6px; }
  .signaux span { display:block; background:#17130F; width:4px; border-radius:1px; }
  .jauge { width:25px; height:12px; border:1.4px solid #17130F; border-radius:3.5px;
           margin-left:5px; position:relative; opacity:.9; }
  .jauge::after { content:""; position:absolute; inset:2px; right:8px;
                  background:#17130F; border-radius:1.5px; }
  .corps { flex:1; display:flex; flex-direction:column; position:relative; z-index:5; }
  .barre { position:absolute; bottom:9px; left:50%; transform:translateX(-50%);
           width:140px; height:5px; border-radius:3px; background:rgba(23,19,15,.3); z-index:7; }

  .fermer { position:absolute; top:2px; right:22px; width:30px; height:30px;
            border-radius:99px; background:rgba(23,19,15,.07); color:#6C645A;
            display:grid; place-items:center; font-size:13px; z-index:8; }
  .fermer.clair { background:rgba(255,255,255,.22); color:#FFF; }

  .marque { font-family:var(--serif); font-size:34px; font-weight:600; color:#15110D;
            letter-spacing:-.5px; }
  .marque span { color:var(--accent); }
  .marque.grand { font-size:40px; }
  .promesse { font-family:var(--serif); font-size:23px; line-height:29px;
              color:#3E3830; margin:8px 0 0; }
  .promesse.grand { font-size:25px; line-height:31px; }

  .liste { display:flex; flex-direction:column; gap:15px; padding:24px 28px 0; }
  .liste.serree { gap:12px; padding-top:18px; }
  .avantage { display:flex; gap:13px; align-items:flex-start; }
  .pic { width:26px; height:26px; border-radius:8px; background:rgba(217,106,18,.13);
         color:var(--accent); display:grid; place-items:center; font-size:14px; flex:none; }
  .avantage b { display:block; font-size:15.5px; color:#17130F; line-height:20px; }
  .avantage span { font-size:13.5px; color:#7A7168; }

  .offres { display:flex; flex-direction:column; gap:9px; padding:20px 24px 0; }
  .offres.rangee { flex-direction:row; gap:8px; }
  .offre { border:1.5px solid rgba(23,19,15,.13); border-radius:14px;
           padding:13px 16px; display:flex; justify-content:space-between;
           align-items:center; position:relative; }
  .offre b { font-size:15.5px; color:#17130F; display:block; }
  .offre span { font-size:12.5px; color:#7A7168; }
  .tarif { font-family:var(--serif); font-size:19px; color:#17130F; font-weight:600; }
  .offre.choisie { border-color:var(--accent); border-width:2px;
                   background:rgba(217,106,18,.05); }
  .ruban { position:absolute; top:-9px; left:14px; background:var(--accent); color:#FFF;
           font-size:10.5px; font-weight:700; letter-spacing:.03em;
           padding:2px 8px; border-radius:99px; }
  .offre.bloc { flex-direction:column; align-items:flex-start; gap:1px; flex:1;
                padding:14px 10px; text-align:left; }
  .offre.bloc .tarif { font-size:17px; margin-top:3px; }
  .offre.plate { padding:15px 16px; }

  .bas { padding:18px 24px 30px; }
  .bouton { height:52px; border-radius:15px; background:var(--accent); color:#FFF;
            display:grid; place-items:center; font-size:17px; font-weight:600; }
  .lien { text-align:center; font-size:14.5px; color:var(--accent); font-weight:600;
          padding-top:13px; }
  .mentions { text-align:center; font-size:11.5px; color:#948B80; padding-top:11px; }

  /* B — le rayon */
  .rayon { position:absolute; top:-26px; left:-30px; display:flex; gap:9px;
           z-index:1; transform:rotate(-5deg); }
  .rayon .couv { width:104px; height:158px; border-radius:5px; object-fit:cover;
                 transform:translateY(calc(var(--i) * 13px));
                 box-shadow:0 8px 18px -8px rgba(20,14,6,.5); }
  .fondu { position:absolute; inset:0; z-index:2; background:
      linear-gradient(180deg, rgba(252,250,246,.25) 0%, rgba(252,250,246,0) 12%,
                      rgba(252,250,246,.85) 26%, var(--creme) 34%); }

  /* C — le contexte */
  .scene { height:250px; display:grid; place-items:center; position:relative; }
  .pile { position:relative; width:230px; height:200px; display:grid; place-items:center; }
  .pile .couv { position:absolute; width:118px; height:180px; border-radius:6px;
                object-fit:cover;
                transform:translateX(var(--x)) rotate(var(--r)) scale(var(--s));
                box-shadow:0 10px 24px -10px rgba(20,14,6,.55); }
  .pile .couv:nth-child(2) { z-index:3; }
  .cadenas { position:absolute; z-index:5; width:52px; height:52px; border-radius:99px;
             background:var(--accent); color:#FFF; display:grid; place-items:center;
             font-size:22px; box-shadow:0 6px 18px -4px rgba(217,106,18,.65); }
  .titre-contexte { font-family:var(--serif); font-size:28px; font-weight:600;
                    color:#15110D; margin:0; }
  .detail-contexte { font-size:15.5px; line-height:22px; color:#6C645A; margin:9px 0 0; }
  .detail-contexte b { color:#17130F; }

  /* A — le bandeau de couvertures */
  .bandeau { display:flex; gap:7px; padding:6px 0 0 16px; overflow:hidden;
             transform:rotate(-3deg) scale(1.06); transform-origin:left top; }
  .bandeau .couv { width:76px; height:116px; border-radius:4px; object-fit:cover;
                   transform:translateY(calc(var(--i) * 7px));
                   box-shadow:0 6px 14px -6px rgba(20,14,6,.45); }

  /* D — la roue */
  .scene-roue { position:relative; display:grid; place-items:center; padding-top:14px; }
  .roue { width:258px; height:258px;
          filter:drop-shadow(0 10px 26px rgba(20,14,6,.22)); }
  .fleche { position:absolute; top:6px; font-size:20px; color:#D96A12; }

  /* E — le gain */
  .ecran.gagnant { background:linear-gradient(165deg,#C25E0D,#8E3F06 60%,#6B2E04);
                   color:#FFF; }
  .ecran.gagnant .etat { color:#FFF; }
  .ecran.gagnant .signaux span { background:#FFF; }
  .ecran.gagnant .jauge { border-color:#FFF; }
  .ecran.gagnant .jauge::after { background:#FFF; }
  .ecran.gagnant .barre { background:rgba(255,255,255,.42); }
  .gros-gain { font-family:var(--serif); font-size:76px; font-weight:600;
               line-height:1; color:#FFE6C9; }
  .titre-gain { font-family:var(--serif); font-size:29px; line-height:35px;
                margin:10px 0 0; color:#FFF; }
  .detail-gain { font-size:14.5px; line-height:21px; margin:12px 0 0;
                 color:rgba(255,255,255,.75); }
  .liste.clair .avantage b { color:#FFF; }
  .liste.clair .avantage span { color:rgba(255,255,255,.7); }
  .liste.clair .pic { background:rgba(255,255,255,.16); color:#FFE6C9; }
  .bouton.blanc { background:#FFF; color:#8E3F06; }
  .mentions.pale { color:rgba(255,255,255,.6); }

  footer { margin-top:70px; padding-top:24px; border-top:1px solid var(--trait);
           font-size:14.5px; line-height:1.65; max-width:70ch; }
  footer b { color:var(--encre); }

  @media (max-width:640px) { :root { --s:0.82; } .page { padding:40px 20px 70px; } }
</style>

<div class="page">
  <header>
    <p class="surtitre">Honya · l'écran d'abonnement</p>
    <h1>Trois façons de présenter Honya+</h1>
    <p>Dessinées à 393 × 852 points, la taille réelle de l'iPhone : les tailles de
      police, les marges et les hauteurs de bouton se reportent telles quelles
      dans SwiftUI. Les tarifs sont ceux de la grille validée.</p>
  </header>

  <div class="grille">MAQUETTES</div>

  <footer>
    <p><b>L'enchaînement : A ou C, puis D si l'on ferme.</b> C s'ouvre depuis chaque
      verrou en montrant la chose exacte qui manque. A vit dans les réglages, pour
      qui veut comparer. Et la roue n'apparaît qu'au refus — jamais à l'ouverture,
      jamais deux fois.</p>
    <p><b>La roue est légitime, je me suis trompé en le contestant.</b> Yazio
      l'utilise et affiche jusqu'à 75 %. Techniquement, le « gain » révèle une
      offre d'introduction StoreKit déclarée dans App Store Connect : la roue
      n'est que la mise en scène d'un tarif qui existe déjà. Rien d'interdit.</p>
    <p><b>Le seul réglage que je discuterais :</b> −10 % ne fait basculer
      personne, c'est 3 €. À −40 % (17,99 € la première année), la remise est
      assez forte pour décider, et le renouvellement se fait au tarif normal —
      contrairement au « 75 % à vie » de Yazio, qui sacrifie durablement la
      valeur de l'abonnement.</p>
  </footer>
</div>
"""


def ecrire():
    blocs = []
    for lettre, nom, ecran, note, cout in MAQUETTES:
        blocs.append(f'''
    <section class="bloc-maquette">
      <div class="etiquette"><span class="lettre">{lettre}</span><span class="nom">{nom}</span></div>
      <div class="cadre">{ecran}</div>
      <p class="note">{note}</p>
      <p class="cout">{cout}</p>
    </section>''')

    chemin = os.path.join(DOSSIER, "honya-plus-ecrans.html")
    with open(chemin, "w", encoding="utf-8") as fichier:
        fichier.write(PAGE.replace("MAQUETTES", "".join(blocs)))
    print(f"honya-plus-ecrans.html écrit — {os.path.getsize(chemin) // 1024} ko")


if __name__ == "__main__":
    ecrire()

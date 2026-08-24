# -*- coding: utf-8 -*-
"""Écrit la maquette de l'écran d'ouverture de Honya — quatre variantes du mur.

Les couvertures sont embarquées en base64 : la page publiée ne peut pas aller
chercher d'images ailleurs, et une maquette avec des rectangles gris ne se
juge pas.

Tout est dessiné à 393 × 852 points — la taille réelle d'un iPhone 16 Pro —
puis réduit à l'affichage. Chaque valeur écrite ici se reporte telle quelle
dans SwiftUI.
"""
import json
import os

DOSSIER = os.path.dirname(os.path.abspath(__file__))
COUV = json.load(open(os.path.join(DOSSIER, "couvertures.json"), encoding="utf-8"))

# Romans grand public d'abord, mangas glissés au milieu : le mur doit dire
# « tous les livres », pas « une app de manga ».
ORDRE = [
    "la-femme-de-m-nage", "one-piece", "jamais-plus", "le-petit-prince",
    "cinquante-nuances-de-grey", "demon-slayer", "verity", "dune",
    "les-sept-maris-d-evelyn-hu", "chainsaw-man", "da-vinci-code", "1984",
    "il-tait-deux-fois", "l-attaque-des-titans", "l-tranger",
    "le-probl-me-trois-corps", "harry-potter-l-cole-des-so", "death-note",
    "l-alchimiste", "le-comte-de-monte-cristo",
]


def img(cle, classe="", style=""):
    return (f'<img class="couv {classe}" src="{COUV[cle]["data"]}" alt="" '
            f'style="{style}">')


def colonnes(groupes, classe_col=""):
    """Un groupe = (liste de clés, décalage vertical en points)."""
    html = ""
    for cles, decalage in groupes:
        html += f'<div class="colonne {classe_col}" style="transform:translateY({decalage}px)">'
        html += "".join(img(c) for c in cles)
        html += "</div>"
    return html


POMME = ('<svg width="17" height="20" viewBox="0 0 17 20" fill="currentColor" aria-hidden="true">'
         '<path d="M14.1 10.6c0-2.3 1.9-3.4 2-3.5-1.1-1.6-2.8-1.8-3.4-1.8-1.4-.15-2.8.85-3.5.85'
         's-1.85-.83-3-.81C4.6 5.3 3.2 6.2 2.4 7.6c-1.6 2.8-.4 7 1.15 9.3.76 1.1 1.67 2.4 2.86 '
         '2.35 1.15-.05 1.58-.74 2.97-.74s1.78.74 3 .72c1.24-.02 2.02-1.14 2.78-2.25.88-1.29 '
         '1.24-2.54 1.26-2.6-.03-.01-2.4-.93-2.42-3.68zM11.8 3.6c.63-.77 1.06-1.83.94-2.9-.91.04'
         '-2.01.61-2.66 1.37-.58.68-1.09 1.76-.95 2.8 1.01.08 2.04-.52 2.67-1.27z"/></svg>')

ETAT = ('<div class="etat"><span>9:41</span><div class="signaux">'
        '<span style="height:5px"></span><span style="height:8px"></span>'
        '<span style="height:11px"></span><span style="height:13px"></span>'
        '<div class="jauge"></div></div></div>')


def actions(secondaire="doux"):
    return (f'<div class="actions">'
            f'<div class="bouton pomme">{POMME}Continuer avec Apple</div>'
            f'<div class="bouton {secondaire}">Continuer avec un e-mail</div>'
            f'<div class="sans-compte">Continuer sans compte</div></div>')


# ══════════════════════════════════════════════════════════════════
# A — COLONNES  ·  la version que vous avez retenue, resserrée
# ══════════════════════════════════════════════════════════════════

def a_colonnes():
    mur = colonnes([(ORDRE[0:5], -76), (ORDRE[5:10], 40), (ORDRE[10:15], -34)])
    return f'''
    <div class="ecran">
      <div class="scene"><div class="mur-incline">{mur}</div></div>
      <div class="voile-bas"></div>
      {ETAT}
      <div class="corps">
        <div style="flex:1"></div>
        <div style="padding:0 26px;">
          <h2 class="serif" style="font-size:46px; line-height:50px;">Honya</h2>
          <p class="accroche">Rangez vos livres, suivez vos lectures.</p>
        </div>
        <div style="height:30px"></div>
        {actions()}
      </div>
      <div class="barre"></div>
    </div>'''


# ══════════════════════════════════════════════════════════════════
# B — GRILLE  ·  droite, sans perspective. Plus calme, plus Apple Books.
# ══════════════════════════════════════════════════════════════════

def b_grille():
    mur = colonnes([(ORDRE[0:5], -30), (ORDRE[5:10], -118), (ORDRE[10:15], -30)],
                   "serree")
    return f'''
    <div class="ecran">
      <div class="scene"><div class="mur-droit">{mur}</div></div>
      <div class="voile-bas doux-bas"></div>
      {ETAT}
      <div class="corps">
        <div style="flex:1"></div>
        <div style="padding:0 26px; text-align:center;">
          <h2 class="serif" style="font-size:46px; line-height:50px;">Honya</h2>
          <p class="accroche">Votre bibliothèque, et où vous en êtes.</p>
        </div>
        <div style="height:28px"></div>
        {actions()}
      </div>
      <div class="barre"></div>
    </div>'''


# ══════════════════════════════════════════════════════════════════
# C — BANDEAU  ·  les couvertures en haut seulement, la typo prend la place
# ══════════════════════════════════════════════════════════════════

def c_bandeau():
    mur = colonnes([(ORDRE[0:4], -18), (ORDRE[4:8], -84), (ORDRE[8:12], -18),
                    (ORDRE[12:16], -84)], "menue")
    return f'''
    <div class="ecran">
      <div class="scene bandeau"><div class="mur-droit">{mur}</div></div>
      <div class="voile-bandeau"></div>
      {ETAT}
      <div class="corps">
        <div style="height:382px"></div>
        <div style="padding:0 28px;">
          <h2 class="serif" style="font-size:56px; line-height:58px;">Honya</h2>
          <p class="accroche" style="font-size:19px; line-height:27px; margin-top:14px;
             max-width:270px;">Toute votre bibliothèque,<br>et le fil de vos lectures.</p>
        </div>
        <div style="flex:1"></div>
        {actions("contour")}
      </div>
      <div class="barre"></div>
    </div>'''


# ══════════════════════════════════════════════════════════════════
# D — VERRE  ·  le mur va jusqu'en bas, une plaque de verre dépoli par-dessus
# ══════════════════════════════════════════════════════════════════

def d_verre():
    mur = colonnes([(ORDRE[0:6], -60), (ORDRE[6:12], 30), (ORDRE[12:18], -20)])
    return f'''
    <div class="ecran">
      <div class="scene"><div class="mur-incline">{mur}</div></div>
      <div class="voile-haut"></div>
      {ETAT}
      <div class="corps">
        <div style="flex:1"></div>
        <div class="verre">
          <h2 class="serif" style="font-size:42px; line-height:46px;">Honya</h2>
          <p class="accroche" style="margin-top:8px;">Vos livres rangés, vos lectures suivies.</p>
          {actions("verre-doux")}
        </div>
      </div>
      <div class="barre"></div>
    </div>'''


VARIANTES = [
    ("A", "Colonnes", a_colonnes(),
     "<b>Celle que vous avez retenue, resserrée.</b> Trois colonnes en perspective "
     "qui montent vers la droite. C'est la plus vivante des quatre : dans l'app, "
     "chaque colonne défile à sa propre vitesse.",
     "« Rangez vos livres, suivez vos lectures. »"),
    ("B", "Grille", b_grille(),
     "<b>La même idée, sans perspective.</b> Une grille droite, la colonne du "
     "milieu décalée. Plus calme, plus sage — c'est la plus proche de ce que ferait "
     "Apple, et celle qui vieillira le mieux.",
     "« Votre bibliothèque, et où vous en êtes. »"),
    ("C", "Bandeau", c_bandeau(),
     "<b>Les couvertures cèdent la place au texte.</b> Quatre colonnes de petites "
     "couvertures en haut, puis du vide et un grand titre. La plus lisible, la "
     "moins chargée.",
     "« Toute votre bibliothèque, et le fil de vos lectures. »"),
    ("D", "Verre", d_verre(),
     "<b>Le mur ne s'arrête jamais.</b> Les couvertures vont jusqu'en bas, et une "
     "plaque de verre dépoli porte le texte. C'est le matériau d'iOS 26 — le plus "
     "spectaculaire, et le plus risqué si les couvertures sont sombres.",
     "« Vos livres rangés, vos lectures suivies. »"),
]


PAGE = """<title>L'accueil de Honya</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500&display=swap">

<style>
  /* L'atelier suit le thème du lecteur. Les téléphones restent CLAIRS :
     ce sont des maquettes de l'interface claire, les inverser mentirait
     sur le rendu. */

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
       font-weight:600; color:var(--encre); margin:0 0 16px; text-wrap:balance; }
  header p { font-size:16.5px; line-height:1.62; margin:0 0 10px; max-width:60ch; }
  .rappel { border-left:2px solid var(--accent); padding-left:16px; margin:28px 0 0;
            font-size:15px; line-height:1.6; max-width:60ch; }

  .grille { display:grid; grid-template-columns:repeat(auto-fit,minmax(292px,1fr));
            gap:54px 34px; margin-top:56px; }
  .variante { display:flex; flex-direction:column; gap:15px; }
  .etiquette { display:flex; align-items:baseline; gap:10px; }
  .lettre { font-family:var(--mono); font-size:12px; font-weight:500; color:#FFF;
            background:var(--encre); border-radius:5px; padding:3px 7px; }
  .nom { font-family:var(--serif); font-size:21px; font-weight:600; color:var(--encre); }
  .note { font-size:14px; line-height:1.6; margin:0; }
  .note b { color:var(--encre); font-weight:600; }
  .phrase { font-family:var(--serif); font-size:15px; font-style:italic;
            color:var(--accent); margin:0; padding-top:5px;
            border-top:1px solid var(--trait); }

  /* ---------- téléphone ---------- */

  .cadre { width:calc(393px * var(--s)); height:calc(852px * var(--s));
           border-radius:calc(56px * var(--s)); padding:calc(3px * var(--s));
           background:linear-gradient(150deg,#736C64,#2A2622 45%,#57514A);
           box-shadow:0 24px 48px -18px rgba(26,20,12,.5), 0 3px 10px -4px rgba(26,20,12,.35);
           overflow:hidden; }
  .ecran { width:393px; height:852px; transform:scale(var(--s)); transform-origin:top left;
           border-radius:53px; overflow:hidden; position:relative; background:var(--creme);
           color:#17130F; font-family:var(--sf); display:flex; flex-direction:column; }

  .etat { height:54px; padding:18px 34px 0; display:flex; justify-content:space-between;
          align-items:center; font-size:15px; font-weight:600; color:#17130F;
          flex:none; position:relative; z-index:6; }
  .signaux { display:flex; align-items:center; gap:6px; }
  .signaux span { display:block; background:#17130F; width:4px; border-radius:1px; }
  .jauge { width:25px; height:12px; border:1.4px solid #17130F; border-radius:3.5px;
           position:relative; margin-left:5px; opacity:.9; }
  .jauge::after { content:""; position:absolute; inset:2px; right:8px;
                  background:#17130F; border-radius:1.5px; }

  .corps { flex:1; display:flex; flex-direction:column; position:relative; z-index:5; }
  .serif { font-family:var(--serif); font-weight:600; color:#15110D;
           letter-spacing:-.5px; margin:0; }
  .accroche { font-size:17px; line-height:24px; color:#6C645A; margin:10px 0 0; }

  .actions { display:flex; flex-direction:column; gap:12px; padding:0 24px 34px; }
  .bouton { height:50px; border-radius:15px; display:flex; align-items:center;
            justify-content:center; gap:8px; font-size:17px; font-weight:600;
            letter-spacing:-.2px; }
  .bouton.pomme { background:#000; color:#FFF; }
  .bouton.doux { background:rgba(23,19,15,.06); color:#17130F; }
  .bouton.contour { border:1.5px solid rgba(23,19,15,.17); color:#17130F; }
  .bouton.verre-doux { background:rgba(255,255,255,.55); color:#17130F;
                       border:1px solid rgba(255,255,255,.7); }
  .sans-compte { text-align:center; font-size:15px; color:#8C8479; padding-top:4px; }
  .barre { position:absolute; bottom:9px; left:50%; transform:translateX(-50%);
           width:140px; height:5px; border-radius:3px; background:rgba(23,19,15,.32); z-index:7; }

  /* ---------- le mur ---------- */

  .scene { position:absolute; inset:0; z-index:1; overflow:hidden; }
  .scene.bandeau { bottom:auto; height:400px; }
  .colonne { display:flex; flex-direction:column; gap:14px; }
  .couv { display:block; width:148px; height:226px; border-radius:5px; object-fit:cover;
          box-shadow:0 1px 2px rgba(20,14,6,.18), 0 9px 20px -8px rgba(20,14,6,.4); }

  .mur-incline { position:absolute; top:-92px; left:-56px; display:flex; gap:14px;
                 transform:perspective(1100px) rotateX(7deg) rotateY(-15deg) scale(1.16);
                 transform-origin:top center; }

  .mur-droit { position:absolute; top:0; left:0; display:flex; gap:9px; padding:0 5px; }
  .colonne.serree { gap:9px; }
  .colonne.serree .couv { width:121px; height:185px; }
  .colonne.menue { gap:7px; }
  .colonne.menue .couv { width:91px; height:139px; border-radius:4px; }
  .mur-droit:has(.menue) { gap:7px; padding:0 4px; }

  .voile-bas { position:absolute; inset:0; z-index:2; background:
      linear-gradient(180deg, rgba(252,250,246,.36) 0%, rgba(252,250,246,0) 15%,
                      rgba(252,250,246,0) 29%, rgba(252,250,246,.88) 50%, var(--creme) 60%); }
  .voile-bas.doux-bas { background:
      linear-gradient(180deg, rgba(252,250,246,.4) 0%, rgba(252,250,246,0) 16%,
                      rgba(252,250,246,0) 33%, rgba(252,250,246,.9) 53%, var(--creme) 63%); }
  /* Le fondu doit être achevé AVANT la fin des couvertures (400 px sur 852,
     soit 47 %), sans quoi une coupure nette apparaît. */
  .voile-bandeau { position:absolute; inset:0; z-index:2; background:
      linear-gradient(180deg, rgba(252,250,246,.42) 0%, rgba(252,250,246,0) 13%,
                      rgba(252,250,246,0) 28%, rgba(252,250,246,.9) 42%, var(--creme) 47%); }
  .voile-haut { position:absolute; inset:0 0 auto 0; height:150px; z-index:2; background:
      linear-gradient(180deg, rgba(252,250,246,.72), rgba(252,250,246,0)); }

  .verre { margin:0 10px 10px; padding:30px 16px 0; border-radius:34px;
           background:rgba(252,250,246,.62);
           -webkit-backdrop-filter:blur(34px) saturate(150%);
           backdrop-filter:blur(34px) saturate(150%);
           border:1px solid rgba(255,255,255,.65);
           box-shadow:0 -1px 30px rgba(20,14,6,.14); text-align:center; }
  .verre .actions { padding:22px 8px 24px; }

  footer { margin-top:76px; padding-top:26px; border-top:1px solid var(--trait);
           font-size:14.5px; line-height:1.65; max-width:70ch; }
  footer b { color:var(--encre); }
  footer ul { margin:12px 0 0; padding-left:20px; }
  footer li { margin-bottom:7px; }
  footer em { font-family:var(--serif); font-style:italic; color:var(--encre);
              font-size:15.5px; }

  @media (max-width:640px) {
    :root { --s:0.82; }
    .page { padding:40px 20px 70px; }
    .grille { gap:48px 24px; }
  }
</style>

<div class="page">
  <header>
    <p class="surtitre">Honya · écran d'ouverture</p>
    <h1>Le mur, en quatre variantes</h1>
    <p>Quatorze romans grand public et six mangas, tirés du catalogue Apple Books
      français — la même source que l'application. Chaque écran est dessiné à
      393 × 852 points, la taille réelle de l'iPhone : les tailles de police, les
      marges et les hauteurs de bouton se reportent telles quelles dans SwiftUI.</p>
    <p class="rappel">Les téléphones restent clairs même si vous lisez cette page en
      thème sombre — ce sont des maquettes de l'interface claire. Le passage au noir
      se fera dans l'app, une fois la variante choisie.</p>
  </header>

  <div class="grille">VARIANTES</div>

  <footer>
    <p><b>Les phrases.</b> Chaque variante en porte une différente pour que vous les
      jugiez en situation, mais elles sont interchangeables. Toutes disent la même
      chose : on range sa bibliothèque, et on suit ses lectures.</p>
    <ul>
      <li><em>Rangez vos livres, suivez vos lectures.</em> — deux verbes, deux gestes.
        C'est la plus directe, et celle que je garderais.</li>
      <li><em>Votre bibliothèque, et où vous en êtes.</em> — plus douce, sous-entend
        le suivi sans le nommer.</li>
      <li><em>Toute votre bibliothèque, et le fil de vos lectures.</em> — la plus
        littéraire, mais aussi la plus longue.</li>
      <li><em>Vos livres rangés, vos lectures suivies.</em> — symétrique, un peu
        plus froide.</li>
    </ul>
    <p style="margin-top:18px;"><b>Les couvertures.</b> Dans la vraie application,
      ce seront celles de votre bibliothèque dès la deuxième ouverture — l'écran
      d'accueil devient le vôtre. Cette sélection ne sert qu'au premier lancement.</p>
  </footer>
</div>
"""


def ecrire():
    blocs = []
    for lettre, nom, ecran, note, phrase in VARIANTES:
        blocs.append(f'''
    <section class="variante">
      <div class="etiquette"><span class="lettre">{lettre}</span><span class="nom">{nom}</span></div>
      <div class="cadre">{ecran}</div>
      <p class="note">{note}</p>
      <p class="phrase">{phrase}</p>
    </section>''')

    chemin = os.path.join(DOSSIER, "bienvenue.html")
    with open(chemin, "w", encoding="utf-8") as fichier:
        fichier.write(PAGE.replace("VARIANTES", "".join(blocs)))
    print(f"bienvenue.html écrit — {os.path.getsize(chemin) // 1024} ko")


if __name__ == "__main__":
    ecrire()

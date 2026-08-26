# -*- coding: utf-8 -*-
"""Écrit les modèles de courrier envoyés par Supabase.

En anglais : l'application parle 14 langues, et Supabase n'a qu'un seul
modèle par type de courrier. L'anglais est ce qui laisse le moins de monde
sur le carreau.

Contraintes du courrier électronique, qui expliquent le code ci-dessous :
tableaux plutôt que flexbox, styles en ligne plutôt que feuille séparée,
largeur fixe de 600 px. Outlook ignore tout le reste.

Les variables entre doubles accolades sont remplies par Supabase au moment
de l'envoi — ne pas y toucher.
"""
import os

DOSSIER = os.path.dirname(os.path.abspath(__file__))

CREME = "#F6F1E8"
ENCRE = "#1A1614"
TEXTE = "#4A4440"
DISCRET = "#8A8078"
ACCENT = "#EE7A1E"
SERIF = "'Iowan Old Style', 'Palatino Linotype', Palatino, Georgia, serif"
SANS = "-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif"

SQUELETTE = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light">
<meta name="supported-color-schemes" content="light">
<title>TITRE</title>
</head>
<body style="margin:0; padding:0; background:CREME;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"
       style="background:CREME; padding:32px 16px;">
  <tr>
    <td align="center">
      <table role="presentation" width="600" cellpadding="0" cellspacing="0" border="0"
             style="width:100%; max-width:600px;">

        <tr>
          <td align="center" style="padding:0 0 14px 0;">
            <!-- Hébergée sur le site : Gmail bloque les images intégrées au
                 message. Le masque arrondi est cuit dans le PNG, parce
                 qu'Outlook ignore border-radius. -->
            <!-- alt vide : le nom est écrit juste en dessous, et un client
                 qui bloque les images afficherait sinon « Honya » deux fois. -->
            <img src="https://www.honya.app/icone-courriel.png" alt=""
                 width="72" height="72"
                 style="display:block; width:72px; height:72px; border:0;">
          </td>
        </tr>

        <tr>
          <td align="center" style="padding:0 0 28px 0;">
            <span style="font-family:SERIF; font-size:26px; letter-spacing:0.5px;
                         color:ENCRE;">Honya</span>
          </td>
        </tr>

        <tr>
          <td style="background:#FFFFFF; border-radius:16px; padding:44px 44px 38px 44px;">

            <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
              <tr>
                <td style="padding:0 0 18px 0;">
                  <div style="width:38px; height:3px; background:ACCENT;
                              border-radius:2px;"></div>
                </td>
              </tr>
              <tr>
                <td style="font-family:SERIF; font-size:30px; line-height:38px;
                           color:ENCRE; padding:0 0 16px 0;">TITRE</td>
              </tr>
              <tr>
                <td style="font-family:SANS; font-size:16px; line-height:26px;
                           color:TEXTE; padding:0 0 30px 0;">CORPS</td>
              </tr>
ACTION
              <tr>
                <td style="font-family:SANS; font-size:13px; line-height:21px;
                           color:DISCRET; padding:16px 0 0 0;">NOTE</td>
              </tr>
            </table>

          </td>
        </tr>

        <tr>
          <td align="center" style="font-family:SANS; font-size:12px; line-height:20px;
                                    color:DISCRET; padding:26px 0 0 0;">
            This message comes from an address that doesn't take replies.<br>
            Need a hand? Write to
            <a href="mailto:contact@honya.app" style="color:DISCRET;"
               >contact@honya.app</a><br><br>
            <a href="https://www.honya.app" style="color:DISCRET; text-decoration:none;"
               >honya.app</a>
          </td>
        </tr>

      </table>
    </td>
  </tr>
</table>
</body>
</html>
"""

# Un bouton qui mene quelque part.
BLOC_LIEN = """              <tr>
                <td style="padding:0 0 30px 0;">
                  <table role="presentation" cellpadding="0" cellspacing="0" border="0">
                    <tr>
                      <td style="background:ACCENT; border-radius:10px;">
                        <a href="LIENACTION"
                           style="display:inline-block; padding:15px 30px; font-family:SANS;
                                  font-size:16px; font-weight:600; color:#FFFFFF;
                                  text-decoration:none;">BOUTON</a>
                      </td>
                    </tr>
                  </table>
                </td>
              </tr>
              <tr>
                <td style="font-family:SANS; font-size:13px; line-height:21px;
                           color:DISCRET; border-top:1px solid #EDE7DD; padding:22px 0 0 0;">
                  If the button doesn't work, copy this link into your browser:<br>
                  <a href="LIENACTION"
                     style="color:ACCENT; text-decoration:none; word-break:break-all;"
                     >LIENACTION</a>
                </td>
              </tr>"""

# Un code a recopier. Le mot de passe oublie se termine DANS l'application,
# sur son propre ecran : un lien ferait sortir le lecteur pour rien.
BLOC_CODE = """              <tr>
                <td style="padding:0 0 26px 0;">
                  <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%">
                    <tr>
                      <td align="center"
                          style="background:#FBF6EF; border:1px solid #EDE7DD; border-radius:12px;
                                 padding:22px 0; font-family:SANS; font-size:34px;
                                 font-weight:600; letter-spacing:7px; color:ENCRE;">{{ .Token }}</td>
                    </tr>
                  </table>
                </td>
              </tr>
              <tr>
                <td style="font-family:SANS; font-size:13px; line-height:21px;
                           color:DISCRET; border-top:1px solid #EDE7DD; padding:22px 0 0 0;">
                  Type this code into Honya, on the screen that asked for it.
                  It expires in one hour, and works only once.
                </td>
              </tr>"""


# Le lien du courrier pointe vers honya.app et non vers Supabase.
#
# C'est ce qui permet au bouton d'ouvrir l'APPLICATION : un lien universel ne
# se declenche que sur un clic direct, jamais au bout d'une redirection — et
# passer par Supabase, c'est precisement une redirection. L'application
# recupere le jeton hache dans l'adresse et fait la verification elle-meme.
# Si elle n'est pas installee, la page web du site prend le relais.
def lien(type_):
    return ("https://www.honya.app/fr/confirme/"
            "?token_hash={{ .TokenHash }}&type=" + type_)


MODELES = {
    "confirmation-inscription": {
        "lien": lien("signup"),
        "sujet": "Confirm your email address",
        "titre": "One last step",
        "corps": "Confirm this address and your shelves are ready. Add one volume "
                 "and Honya lays out the whole series, release dates included.",
        "bouton": "Confirm my address",
        "note": "If you didn't create a Honya account, you can ignore this message — "
                "nothing was set up with your address.",
    },
    "mot-de-passe-oublie": {
        "lien": None,
        "sujet": "Reset your password",
        "titre": "Forgotten password",
        "corps": "It happens to everyone. Here is your code — type it into Honya "
                 "and you're back among your books.",
        "bouton": None,
        "note": "If you didn't ask for this, ignore the message: your password "
                "stays as it is.",
    },
    "changement-adresse": {
        "lien": lien("email_change"),
        "sujet": "Confirm your new email address",
        "titre": "New address",
        "corps": "Confirm this address to start using it to sign in to Honya. "
                 "Your library doesn't move — only the way you reach it.",
        "bouton": "Confirm this address",
        "note": "If you didn't ask to change your address, ignore this message and "
                "your old one stays in place.",
    },
}


def ecrire():
    for nom, m in MODELES.items():
        action = BLOC_LIEN if m["lien"] else BLOC_CODE
        page = (SQUELETTE
                .replace("ACTION", action)
                .replace("LIENACTION", m["lien"] or "")
                .replace("BOUTON", m["bouton"] or "")
                .replace("TITRE", m["titre"])
                .replace("CORPS", m["corps"])
                .replace("NOTE", m["note"])
                .replace("CREME", CREME)
                .replace("ENCRE", ENCRE)
                .replace("TEXTE", TEXTE)
                .replace("DISCRET", DISCRET)
                .replace("ACCENT", ACCENT)
                .replace("SERIF", SERIF)
                .replace("SANS", SANS))
        chemin = os.path.join(DOSSIER, nom + ".html")
        with open(chemin, "w", encoding="utf-8") as fichier:
            fichier.write(page)
        print(f"{nom}.html   sujet : {m['sujet']}")


if __name__ == "__main__":
    ecrire()

# Honya

Suivi de collection **livres, mangas & BD** — possédé / lu / à lire / wishlist / prêté, tomes et
chapitres, sessions chronométrées, statistiques, badges. Design dans l'ADN d'Apple Books
(serif New York, arc d'objectif, couvertures 3D, fiches teintées par la couverture).

Concept design complet : voir l'artifact « Honya — concept design » (écrans, système de
design, roadmap).

## Inventaire fonctionnel v1

- **Bibliothèque** : livres, mangas, BD et séries ; statuts À lire, En cours, Lu,
  Wishlist et Abandonné ; filtres, grille/liste, progression et notes.
- **Éditions** : scan EAN/ISBN-10/ISBN-13 avec validation de la clé de contrôle,
  recherche texte, ajout manuel de secours, déduplication sur l'ISBN exact, titre et
  couverture de l'édition possédée prioritaires.
- **Séries** : fiche série et fiche de chaque tome, tomes possédés/lus/manquants,
  complétion du rayon, prochaine sortie et rappel local stable.
- **Organisation** : étagères personnelles et automatiques, suivi, citations et prêt
  d'un livre ou d'un tome avec date et emprunteur.
- **Lecture** : chronomètre, pages lues, historique, séries de jours, objectifs,
  statistiques et badges.
- **International** : interface traduite en 15 variantes linguistiques et éditions
  recherchées dans la langue choisie, sans traduction automatique des titres.
- **Comptes et Honya+** : compte Apple ou e-mail obligatoire via Supabase,
  restauration StoreKit, verrous contextuels et déblocage uniquement par un droit
  Apple vérifié dans les builds distribués.

## Ouvrir & compiler

Le projet utilise le **format Xcode moderne à dossiers synchronisés** : tout fichier ajouté
dans `Honya/` est automatiquement compilé, sans toucher au `.xcodeproj`.

- **Sur Mac** : ouvrir `Honya.xcodeproj` (Xcode 26+, cible iOS 26). Sélectionner votre équipe
  de signature dans *Signing & Capabilities*, puis ⌘R.
- **Sans Mac** — deux CI complémentaires :
  - **GitHub Actions** (`.github/workflows/build.yml`) : compile à chaque push sur un
    runner macOS. Gratuit, c'est le filet anti-régression.
  - **Codemagic** (`codemagic.yaml`) : workflow `testflight`, archive signée et envoi à
    TestFlight. Deux façons de le lancer :
    1. **Automatiquement** : chaque push sur `main` déclenche le webhook Codemagic ; un
       nouveau push annule l'archive précédente encore en cours.
    2. **Manuellement** : *Start new build* → branche `main` → workflow
       « Honya · Archive signée → TestFlight », si le webhook est momentanément indisponible.
    3. **Par tag** : `git tag v0.1 && git push origin v0.1` pour un jalon explicite.

    GitHub Actions compile le même SHA sur simulateur pendant que Codemagic construit
    l'archive signée et l'envoie à TestFlight. Ne pas soumettre ce build à l'App Store
    avant que la compilation et le parcours sur iPhone soient validés.

    Prérequis : intégration *Developer Portal* (clé API App Store Connect) enregistrée
    sous le nom repris dans `integrations → app_store_connect` (ici : `Binjo ASC key`).

    ⚠️ Si Codemagic affiche une erreur de validation portant sur une version ancienne du
    fichier, il sert un cache : cliquer le ⟳ à côté du sélecteur de branche, ou retirer
    puis ré-ajouter l'application dans Codemagic pour forcer un nouveau clone.
- Écrit sous Windows sans toolchain iOS : GitHub Actions reste la vérification de
  compilation de référence avant chaque archive TestFlight.

## Architecture

```
Honya/
├── HonyaApp.swift            Point d'entrée, ModelContainer, données d'aperçu
├── Models/Modeles.swift      SwiftData : Oeuvre, Exemplaire, Serie, Tome,
│                             SessionLecture, Citation, Objectif, BadgeGagne
├── DesignSystem/             Theme (couleurs statuts, typo serif), Composants
│                             (couverture 3D, pilule CTA, chips, étoiles), Jauges
│                             (arc d'objectif, semaine de série)
├── Services/
│   ├── Metadonnees/          Agrégateur Open Library et bibliothèques nationales
│   │                         (BnF, Sudoc,
│   │                         DNB, NDL/openBD, LIBRIS, BN Pologne)
│   │                         + adaptateurs Google/Apple/AniList désactivés
│   │                         sans autorisation commerciale explicite
│   ├── ImportService.swift   Résultat de recherche → SwiftData, déduplication
│   ├── StatsEngine.swift     Streak (avec joker), heatmap, records, genres…
│   ├── BadgesEngine.swift    Les 8 badges
│   ├── NotificationsService  Rappels de sorties de tomes
│   └── ImageCharge.swift     Cache mémoire + cache HTTP borné + couleur dominante
└── Vues/
    ├── RacineView            TabView 4 onglets (Recherche en rôle .search)
    ├── Accueil/              Arc d'objectif, Reprendre, streak, À suivre, sorties
    ├── Bibliotheque/         Chips statuts, grille/liste, piles de séries
    ├── Fiches/               Fiche livre teintée · Fiche série (grille de tomes)
    ├── Session/              Mode « lampe de chevet » + feuille de fin
    ├── Stats/                Swift Charts, heatmap, défi annuel, badges
    ├── Recherche/            Recherche en ligne + locale, ScannerSheet (VisionKit)
    ├── Onboarding/           3 étapes : types, objectif, langues
    └── Reglages/
```

## Décisions produit clés

- **Édition exacte d'abord** : la couverture et le titre associés à l'ISBN scanné
  priment. Si aucune source ne connaît la couverture de ce code précis, Honya la
  laisse vide au lieu d'afficher celle d'un autre tirage ou de l'ebook. Le lecteur
  peut alors choisir sa propre photo depuis la fiche du livre ou du tome ; elle
  reste dans le conteneur privé de l'app et est supprimée avec le livre/compte.
- **Titres officiels par langue** : jamais de traduction automatique. `Oeuvre.titres[langue]`
  est rempli par les éditions réellement publiées (Open Library au niveau édition
  et catalogues nationaux) ;
  repli d'affichage : langue de l'utilisateur → anglais → translittération → original.
- **ISBN d'abord** : le scan ne conserve qu'une réponse portant le même ISBN canonique ;
  le groupe d'enregistrement (978-2 = zone francophone, 978-4 = zone japonaise)
  sert seulement à router vers un catalogue/storefront probable. Il n'est jamais
  enregistré comme langue du livre : seule une métadonnée explicite peut localiser
  son titre et sa couverture.
- **Test de non-régression réel** : `9782749958194` doit rendre via Sudoc l'édition
  papier française d'**Instinct, tome 2**, avec sa tomaison, et ne jamais être
  fusionné avec l'ebook `9782749963990`. La BnF ne possède actuellement aucune
  vignette pour cet EAN ; la couverture vient donc de la fiche officielle Michel
  Lafon qui relie explicitement ce poster au même ISBN, avec attribution `© MLP`.
- **Streak avec joker** : un trou d'un jour est pardonné (anti-culpabilité).
- **Branding** : « Honya » s'emploie comme un nom propre, sans aucune référence japonaise
  (pas de kanji, pas de traduction du nom).

## Limites connues / v1.1+

- [ ] **Exhaustivité catalogue** : aucun catalogue public ne garantit tous les livres
      publiés dans le monde. Honya cumule plusieurs sources et propose un ajout manuel
      avec ISBN exact ; la fiche App Store ne doit donc pas promettre « 100 % des livres ».
- [ ] **Licences catalogue commercial** : Google Books impose son attribution, des liens
      visibles et une présentation de ses résultats que l'interface agrégée actuelle ne
      respecte pas encore ; Apple limite son contenu promotionnel ; AniList demande une
      autorisation adaptée à cet usage. Les trois adaptateurs restent coupés
      (`HONYA_* = NO`) tant que leurs conditions et leurs UX ne sont pas validées. Pour
      monter en charge avec Open Library, contacter Internet Archive ou ingérer ses dumps
      selon leur politique plutôt que d'en faire un backend mobile massif.
- [ ] **Photos de couverture dans la sauvegarde** : le snapshot Supabase protège les neuf
      modèles et leurs relations, mais pas encore les octets des photos personnelles. Leur
      référence reste sauvegardée ; l'image elle-même reste uniquement dans le conteneur
      privé de l'iPhone jusqu'à l'ajout d'un bucket Storage privé.
- [ ] **Plusieurs éditions du même ouvrage** : le modèle v1 représente un exemplaire et
      un ISBN par œuvre (ou par tome). Une migration `Œuvre → Édition → Exemplaire` sera
      nécessaire pour posséder simultanément plusieurs traductions/tirages du même titre.
- [ ] **Widgets** (arc + streak, livre en cours) et **Live Activity** de session — nécessite
      une extension de cible.
- [ ] **Rétrospective annuelle** partageable (cartes ShareLink) — teaser déjà dans Stats.
- [ ] **Citations au scanner** (Live Text / VisionKit `ImageAnalyzer`).
- [ ] Import Goodreads/CSV et numérotation fine des chapitres via MangaDex.
- [ ] Ajouter des tests UI/XCTest StoreKit, scanner, quotas et parcours de suppression de
      compte ; la CI actuelle compile et contrôle les 15 traductions.

## Crédits données

Sources actives par défaut : Open Library · BnF · Sudoc · DNB · NDL/openBD ·
LIBRIS · Bibliothèque nationale de Pologne. Les couvertures restent la propriété
de leurs éditeurs. Une vignette BnF affiche aussi sa provenance et sa date de
récupération, conformément à la licence ouverte de l'État.

## Contrôle avant soumission App Store

- [ ] Faire passer le build GitHub macOS sur les modifications finales, puis tester sur
      un iPhone réel le scan `9782749958194` et un ISBN invalide.
- [ ] Décider la stratégie catalogue sous licence. Garder Google/Apple/AniList coupés
      pour la v1, ou obtenir les accords écrits avant de poser les flags sécurisés
      `HONYA_GOOGLE_BOOKS_LICENSED`, `HONYA_APPLE_BOOKS_PROMO_COMPLIANT` et
      `HONYA_ANILIST_LICENSED` à `YES` dans Codemagic.
- [x] Déployer et auditer la migration Supabase de suppression idempotente. Reste à
      vérifier sur iPhone création, déconnexion, reconnexion et suppression définitive
      d'un compte Apple et d'un compte e-mail.
- [x] La page publique de confirmation reçoit `token_hash` et `type`, le schéma
      `honya://` est déclaré et l'app vérifie elle-même le jeton. Reste à tester le lien
      universel et son bouton de secours sur un iPhone installé.
- [x] Le modèle Supabase **Reset password** affiche `{{ .Token }}` et le SMTP Resend de
      production est activé. Reste à tester sur iPhone demande, renvoi, expiration,
      saisie du code et changement effectif du mot de passe.
- [ ] Publier dans Supabase le modèle d'inscription préparé avec `{{ .RedirectTo }}`.
      L'app enregistre désormais la préférence `user_metadata.language` ; le contenu du
      courrier doit encore l'utiliser, avec l'anglais comme repli.
- [x] La sauvegarde/restauration Supabase est liée à `auth.users.id` : stores locaux
      séparés par compte, UUID stables pour les neuf modèles, snapshot canonique contrôlé
      par SHA-256 et révision optimiste, restauration automatique d'un nouvel appareil et
      arbitrage explicite si deux bibliothèques divergent. La v2 lit encore les snapshots
      v1, mais le serveur interdit qu'une ancienne bêta remplace ensuite une v2 par une
      copie amputée des nouveaux statuts/dates de tomes. Les photos personnelles restent
      la limite documentée ci-dessus.
- [ ] Pour les comptes Apple, ajouter au backend la révocation du jeton Apple lors de la
      suppression du compte, puis tester ce parcours de bout en bout. Supprimer seulement
      l'utilisateur Supabase ne suffit pas à valider cette exigence Apple.
- [ ] Vérifier dans le sandbox StoreKit les trois produits publics, la restauration,
      l'expiration/révocation et l'ouverture de la gestion des abonnements.
- [ ] Renseigner dans App Store Connect la politique de confidentialité
      `https://www.honya.app/en/privacy/`, l'assistance
      `https://www.honya.app/en/support/` et des fiches d'abonnement cohérentes dans
      toutes les langues distribuées.
- [ ] Faire correspondre les réponses « App Privacy » d'App Store Connect à
      `Honya/PrivacyInfo.xcprivacy`, joindre les captures et fournir un compte de revue
      e-mail si ce parcours doit être testé par Apple.
- [ ] Mettre à jour les pages publiques : remplacer l'ancien choix par région de l'iPhone
      par la langue de lecture choisie, et ajouter les bibliothèques nationales/Sudoc aux
      fournisseurs mentionnés dans la politique de confidentialité.

## Webhook Codemagic

Le déclenchement automatique des builds Codemagic repose sur un webhook GitHub
pointant vers `https://api.codemagic.io/hooks/<app-id-codemagic>` (events :
`push`, `create`, `pull_request`). Si les builds ne partent plus tout seuls,
vérifier sa présence :

```bash
gh api repos/remia2b/Honya/hooks --jq '.[].config.url'
```

## Comptes (Connexion avec Apple + Supabase)

Deux chemins mènent au **même** compte : l'identifiant Apple, ou une adresse
e-mail. Le jeton d'identité Apple est échangé contre une session Supabase
(`grant_type=id_token`), donc un lecteur entré par Apple et le même lecteur
entré par e-mail sont un seul utilisateur côté serveur.

Le client d'authentification est écrit en REST à la main
(`Honya/Services/SupabaseAuth.swift`) : **aucune dépendance n'est ajoutée au
projet Xcode**, qui est écrit à la main et supporte mal les paquets SPM. Les
jetons de session vivent dans le Trousseau, jamais dans les préférences.

Honya exige un compte authentifié, y compris en développement : Supabase doit donc
être configuré pour entrer dans l'app. Une déconnexion conserve la bibliothèque locale
jusqu'à la prochaine connexion ; seule la suppression explicite du compte l'efface.
Google Books est optionnel et reste inactif sans accord écrit, même lorsqu'une clé API
technique existe.

### Mise en place (une seule fois)

1. **Apple** — developer.apple.com → Identifiers → `com.remiabbou.honya` →
   cocher **Sign In with Apple** → **Save**. Sans cette capacité, le profil
   généré par la CI ne contient pas l'entitlement et l'archive échoue.

2. **Projet Supabase** — créer un projet **dédié à Honya** (les projets sont
   étanches : base, utilisateurs et clés séparés de tout autre projet).

3. **Codemagic** → Honya → Environment variables, groupe `signing`,
   case **Secure** cochée :
   - `SUPABASE_URL` — Settings → API → Project URL
   - `SUPABASE_ANON_KEY` — de préférence la clé publique moderne
     `sb_publishable_…` (la clé `anon` historique reste compatible)
   - `CERTIFICATE_PRIVATE_KEY_B64` — clé privée PEM du certificat Apple Distribution,
     encodée en base64 (le compte Apple est déjà à sa limite de certificats)

   Ces valeurs ne sont jamais dans le dépôt : la CI les écrit dans
   `Honya/Config/Secrets.swift` juste avant la compilation.

4. **Provider Apple dans Supabase** — Authentication → Providers → Apple :
   activer, et mettre `com.remiabbou.honya` en *Client ID*. (Le flux est
   natif : aucun secret OAuth n'est nécessaire.)

5. **Suppression de compte** — la migration versionnée du dossier
   `supabase/migrations/` est déployée. La fonction `SECURITY DEFINER` ne peut
   supprimer que `auth.uid()` et évite d'exposer une clé d'administration dans
   l'app. Elle ajoute une clé d'idempotence et un reçu UUID sans donnée
   personnelle, pour prouver le succès même si la réponse réseau se perd.

6. **Confirmation par e-mail** — Authentication → Providers → Email. Si elle
   reste activée, l'inscription affiche « ouvrez le courrier de confirmation »
   ; désactivée, l'inscription connecte directement.

7. **Récupération par e-mail** — Authentication → Email Templates →
   **Reset password** : inclure le code `{{ .Token }}` dans le corps du message.
   L'interface Honya demande ce code et l'échange avec `type=recovery`; le lien
   `{{ .ConfirmationURL }}` du modèle Supabase par défaut ne suffit pas à ce parcours.

### État de la configuration (projet Honya)

| Étape | État |
|---|---|
| Capacité *Sign In with Apple* sur l'App ID | fait |
| Projet Supabase dédié (West EU, Paris) | fait |
| Migration `20260827171723_suppression_compte_idempotente` | fait et vérifié le 27/08/2026 |
| Migrations `20260827183316_sauvegarde_bibliotheque_v1` et `20260827185323_sauvegarde_bibliotheque_octets_v1` | faites et vérifiées le 27/08/2026 |
| Migration `20260828085009_sauvegarde_bibliotheque_v2` | faite et vérifiée le 28/08/2026 ; v1 lisible, régression v2→v1 bloquée |
| Provider Apple activé, *Client ID* `com.remiabbou.honya` | fait |
| Provider Email activé (mot de passe ≥ 6 caractères) | fait |
| Inscriptions anonymes | désactivées |
| Confirmation d'adresse e-mail | obligatoire |
| Site URL / redirections | `https://www.honya.app` / `https://www.honya.app/*` |
| SMTP personnalisé Resend | activé ; envois Auth réussis observés le 27/08/2026 |
| Modèle **Reset password** avec `{{ .Token }}` | fait |
| CAPTCHA Auth | à configurer avant montée en charge |
| Protection des mots de passe compromis | indisponible sur le plan Free |
| `SUPABASE_URL` / `SUPABASE_ANON_KEY` dans Codemagic | **à confirmer par le prochain build** |

Sans configuration Supabase, un build local reste bloqué sur la connexion et
l'archive TestFlight s'arrête volontairement avant la compilation.

> Le SMTP personnalisé est déjà actif. Avant la production publique, vérifier le
> domaine d'envoi dans Resend, désactiver le suivi des liens et tester la délivrabilité,
> les indésirables et les limites avec une adresse de revue dédiée.

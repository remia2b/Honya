# Honya

Suivi de collection **livres & mangas** — possédé / lu / à lire / wishlist / prêté, tomes et
chapitres, sessions chronométrées, statistiques, badges. Design dans l'ADN d'Apple Books
(serif New York, arc d'objectif, couvertures 3D, fiches teintées par la couverture).

Concept design complet : voir l'artifact « Honya — concept design » (écrans, système de
design, roadmap).

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
    1. **Manuellement** (le plus sûr) : *Start new build* → branche `main` → workflow
       « Honya · Archive signée → TestFlight ». Ne dépend d'aucun webhook.
    2. **Par tag** : `git tag v0.1 && git push origin v0.1` — nécessite que le webhook
       GitHub de Codemagic soit actif.

    Prérequis : intégration *Developer Portal* (clé API App Store Connect) enregistrée
    sous le nom repris dans `integrations → app_store_connect` (ici : `Codemagic`).

    ⚠️ Si Codemagic affiche une erreur de validation portant sur une version ancienne du
    fichier, il sert un cache : cliquer le ⟳ à côté du sélecteur de branche, ou retirer
    puis ré-ajouter l'application dans Codemagic pour forcer un nouveau clone.
- Écrit sous Windows sans possibilité de compiler : le premier build peut révéler quelques
  erreurs de compilation mineures — collez-les à Claude pour correction immédiate.

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
│   ├── Metadonnees/          MetadataProvider + Google Books, Open Library,
│   │                         AniList (GraphQL), Agrégateur en cascade ISBN-first
│   ├── ImportService.swift   Résultat de recherche → SwiftData, déduplication
│   ├── StatsEngine.swift     Streak (avec joker), heatmap, records, genres…
│   ├── BadgesEngine.swift    Les 8 badges
│   ├── NotificationsService  Rappels de sorties de tomes
│   └── ImageCharge.swift     Cache couvertures (mémoire+disque) + couleur dominante
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

- **Couverture canonique globale** : une seule couverture par œuvre, identique pour tous
  (l'édition scannée est stockée en interne mais pas affichée).
- **Titres officiels par langue** : jamais de traduction automatique. `Oeuvre.titres[langue]`
  est rempli par les éditions réellement publiées (Google Books `langRestrict`, AniList) ;
  repli : langue de l'utilisateur → anglais → titre original.
- **ISBN d'abord** : le scan donne l'édition exacte ; le préfixe (978-2 = FR, 978-4 = JP)
  détecte la langue.
- **Streak avec joker** : un trou d'un jour est pardonné (anti-culpabilité).
- **Branding** : « Honya » s'emploie comme un nom propre, sans aucune référence japonaise
  (pas de kanji, pas de traduction du nom).

## Reste à faire (v1.1+)

- [ ] **CloudKit** : passer `ModelConfiguration(cloudKitDatabase: .automatic)` + capability
      iCloud (les modèles sont déjà compatibles : défauts partout, relations optionnelles).
- [ ] **Widgets** (arc + streak, livre en cours) et **Live Activity** de session — nécessite
      une extension de cible.
- [ ] **Rétrospective annuelle** partageable (cartes ShareLink) — teaser déjà dans Stats.
- [ ] **Citations au scanner** (Live Text / VisionKit `ImageAnalyzer`).
- [ ] Fournisseurs supplémentaires : **BnF SRU** (éditions FR exhaustives), **MangaDex**
      (numérotation fine des chapitres).
- [ ] Import Goodreads/CSV · icône App Store (voir `Design/AppIcon.svg`) · localisation EN
      complète (socle `Localizable.xcstrings` posé, statuts/moods encore en dur).
- [ ] Clé API Google Books optionnelle (quota) : `GoogleBooksProvider.cleAPI`, à restreindre
      au bundle.

## Crédits données

Google Books · Open Library · AniList. Les couvertures restent la propriété de leurs éditeurs.

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

Sans configuration Supabase, l'app fonctionne : seule la connexion avec Apple
est proposée, et le chemin e-mail explique qu'il n'est pas encore disponible.

### Mise en place (une seule fois)

1. **Apple** — developer.apple.com → Identifiers → `com.remiabbou.honya` →
   cocher **Sign In with Apple** → **Save**. Sans cette capacité, le profil
   généré par la CI ne contient pas l'entitlement et l'archive échoue.

2. **Projet Supabase** — créer un projet **dédié à Honya** (les projets sont
   étanches : base, utilisateurs et clés séparés de tout autre projet).

3. **Codemagic** → Honya → Environment variables, groupe `signing`,
   case **Secure** cochée :
   - `SUPABASE_URL` — Settings → API → Project URL
   - `SUPABASE_ANON_KEY` — la clé publique `anon`

   Ces valeurs ne sont jamais dans le dépôt : la CI les écrit dans
   `Honya/Config/Secrets.swift` juste avant la compilation.

4. **Provider Apple dans Supabase** — Authentication → Providers → Apple :
   activer, et mettre `com.remiabbou.honya` en *Client ID*. (Le flux est
   natif : aucun secret OAuth n'est nécessaire.)

5. **Suppression de compte** — Apple exige qu'une app qui crée des comptes
   permette aussi de les supprimer. Le client appelle une fonction Postgres,
   pour n'avoir jamais besoin d'une clé d'administration. Dans le SQL Editor :

   ```sql
   create or replace function public.supprimer_mon_compte()
   returns void
   language sql
   security definer
   set search_path = ''
   as $$ delete from auth.users where id = auth.uid(); $$;

   revoke all on function public.supprimer_mon_compte() from anon;
   grant execute on function public.supprimer_mon_compte() to authenticated;
   ```

6. **Confirmation par e-mail** — Authentication → Providers → Email. Si elle
   reste activée, l'inscription affiche « ouvrez le courrier de confirmation »
   ; désactivée, l'inscription connecte directement.

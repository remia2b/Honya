import SwiftUI
import SwiftData

enum Onglet: Hashable {
    case accueil, bibliotheque, decouverte, stats, recherche
}

struct RacineView: View {
    @Environment(\.modelContext) private var contexte
    @Query private var objectifs: [Objectif]
    @State private var onglet: Onglet = .accueil
    /// Nettoyage one-shot des données héritées ou corrompues des vieux bugs.
    @AppStorage("editionsLocalesV10") private var editionsMigrees = false
    /// Une seule fois : chaque série existante gagne le rayon complet du catalogue.
    @AppStorage("catalogueCompletV11") private var catalogueComplet = false
    /// Les couvertures locales posées par un simple homonyme de titre — avant
    /// que l'auteur ne départage — doivent repartir se faire vérifier.
    @AppStorage("editionsVerifieesV49") private var editionsVerifiees = false
    /// Langue qui a produit les données locales actuellement affichées.
    @AppStorage("langueEditionsV1") private var langueEditions = ""
    /// Les anciennes versions ne distinguaient pas une fiche saisie à la main
    /// d'une fiche dérivée. On protège une fois leur contenu avant toute purge.
    @AppStorage("provenanceTomesV1") private var provenanceTomesMigree = false
    @State private var celebrations = Celebrations.partage

    var body: some View {
        TabView(selection: $onglet) {
            Tab("Aujourd'hui", systemImage: "house.fill", value: Onglet.accueil) {
                AccueilView(allerRecherche: { onglet = .recherche })
            }
            Tab("Bibliothèque", systemImage: "books.vertical.fill", value: Onglet.bibliotheque) {
                BibliothequeView(allerRecherche: { onglet = .recherche })
            }
            Tab("Découverte", systemImage: "sparkles", value: Onglet.decouverte) {
                DecouverteView()
            }
            Tab("Stats", systemImage: "chart.bar.fill", value: Onglet.stats) {
                StatsView()
            }
            // Recherche isolée dans sa bulle, à la iOS 26 (pattern Apple Books).
            Tab(value: Onglet.recherche, role: .search) {
                RechercheView()
            }
        }
        .tint(Couleurs.accent)
        .overlay {
            if celebrations.actif {
                ConfettisView(message: celebrations.message)
                    .transition(.opacity)
            }
        }
        .task(id: objectifs.first?.languePrincipale ?? Langues.codeAppareil) {
            await demarrage()
        }
    }

    /// Tout se répare sans intervention : noms de séries nettoyés, puis les
    /// éditions dans la langue du lecteur récupérées en tâche de fond.
    private func demarrage() async {
        reparerNomsDeSeries()

        let langue = Objectif.courant(dans: contexte).languePrincipale
        let series = (try? contexte.fetch(FetchDescriptor<Serie>())) ?? []
        let oeuvres = (try? contexte.fetch(FetchDescriptor<Oeuvre>())) ?? []
        let langueAChanger = langueEditions != langue
        let migrationLocaleAExecuter = !editionsMigrees
        let verificationAExecuter = !editionsVerifiees

        if !provenanceTomesMigree {
            for tome in series.flatMap(\.tomes)
                where tome.isbn == nil
                    && (tome.titre != nil || tome.pages != nil || tome.couvertureURL != nil) {
                // Impossible de reconstruire rétrospectivement la provenance.
                // Préserver vaut mieux que détruire une saisie du lecteur ;
                // les enrichissements sûrs pourront toujours la remplacer.
                tome.metadonneesManuelles = true
            }
        }

        // Les anciennes versions persistaient le statut manuel sans sa date.
        // Dater une seule fois ces choix permet aux sorties réellement futures
        // de rouvrir ensuite une série « Lu », sans réinterpréter son passé.
        for serie in series
            where serie.statutManuelRaw != nil && serie.statutManuelLe == nil {
            serie.statutManuelLe = Date()
        }

        // Changer la langue principale invalide uniquement les métadonnées
        // dérivées. L'ISBN et la couverture de l'exemplaire réellement
        // scanné restent intacts ; le nouveau storefront remplit le reste.
        if langueAChanger {
            for serie in series {
                serie.couvertureLocaleURL = nil
                serie.attributionCouverture = nil
                serie.resumeLocal = nil
                serie.dernierEssaiEditionLocale = nil
                for tome in serie.tomes
                    where tome.isbn == nil && !tome.metadonneesManuelles {
                    tome.couvertureURL = nil
                    tome.titre = nil
                    tome.pages = nil
                }
                ResolveurTomes.reinitialiser(serie)
            }
            for oeuvre in oeuvres {
                oeuvre.couvertureLocaleURL = nil
                if oeuvre.exemplaire?.couvertureEditionURL == nil {
                    oeuvre.attributionCouverture = nil
                }
                oeuvre.resumeLocal = nil
                oeuvre.dernierEssaiEditionLocale = nil
            }
        }

        if migrationLocaleAExecuter {
            // Une seule fois : purge des dégâts des anciens bugs — noms écrasés
            // par un script illisible ou par un AUTRE livre, couvertures d'une
            // autre édition (VO, VIZ, Carlsen…). Les états lu/possédé restent.
            for serie in series {
                for (code, nom) in serie.noms {
                    let base = Tomaison.decomposer(nom).base
                    let illisible = !Titres.estLisible(base, langue: code)
                    // Deux traductions officielles peuvent n'avoir aucun mot
                    // commun ("Attack on Titan" / "L'Attaque des Titans").
                    // Une comparaison littérale entre langues les détruisait.
                    if illisible {
                        serie.noms[code] = nil
                    }
                }
                serie.couvertureLocaleURL = nil
                serie.attributionCouverture = nil
                serie.resumeLocal = nil
                for tome in serie.tomes {
                    // Un ISBN présent identifie une édition réellement ajoutée
                    // ou scannée : sa fiche ne doit jamais être détruite par
                    // une migration de données dérivées.
                    if tome.isbn == nil && !tome.metadonneesManuelles {
                        tome.couvertureURL = nil
                        tome.titre = nil
                        tome.pages = nil
                    }
                }
                ResolveurTomes.reinitialiser(serie)
            }
            for oeuvre in oeuvres {
                for (code, titre) in oeuvre.titres where code != "en" {
                    let base = Tomaison.decomposer(titre).base
                    let illisible = !Titres.estLisible(base, langue: code)
                    if illisible {
                        oeuvre.titres[code] = nil
                    }
                }
                oeuvre.couvertureLocaleURL = nil
                if oeuvre.exemplaire?.couvertureEditionURL == nil {
                    oeuvre.attributionCouverture = nil
                }
                oeuvre.resumeLocal = nil
            }
        }

        // Une seule fois : tout ce qu'un homonyme de titre a pu poser est
        // rendu au doute. Un lecteur s'est retrouvé avec la couverture d'un
        // manuel de survie sur le livre qu'il venait de scanner ; effacer ces
        // données dérivées suffit, le rattrapage ci-dessous les refait avec
        // l'auteur pour juge. Rien de ce que le lecteur a saisi n'est touché.
        if verificationAExecuter {
            for serie in series {
                serie.couvertureLocaleURL = nil
                serie.attributionCouverture = nil
                serie.resumeLocal = nil
                // Les noms publiés restent : on ne peut pas valider une
                // traduction en la comparant mot à mot à l'anglais. La
                // couverture et le résumé dérivés, eux, sont recalculés avec
                // le couple titre + auteur ci-dessous.
                // Le titre d'un tome se retrouve, lui, à chaque passe : il ne
                // coûte rien de le redemander, et il vient du même homonyme.
                for tome in serie.tomes
                    where tome.isbn == nil && !tome.metadonneesManuelles {
                    tome.titre = nil
                }
                ResolveurTomes.reinitialiser(serie)
            }
            for oeuvre in oeuvres {
                oeuvre.couvertureLocaleURL = nil
                if oeuvre.exemplaire?.couvertureEditionURL == nil {
                    oeuvre.attributionCouverture = nil
                }
                oeuvre.resumeLocal = nil
            }
        }

        // Les drapeaux UserDefaults ne deviennent vrais qu'après la sauvegarde
        // SwiftData correspondante. Si l'app est interrompue ou le disque
        // échoue, la migration se rejouera au prochain lancement.
        do {
            try contexte.save()
        } catch {
            return
        }
        if langueAChanger { langueEditions = langue }
        if migrationLocaleAExecuter { editionsMigrees = true }
        if verificationAExecuter { editionsVerifiees = true }
        if !provenanceTomesMigree { provenanceTomesMigree = true }

        // Une seule fois : les séries d'avant la v0.11 récupèrent le rayon
        // complet — tous les tomes parus du catalogue, et les précommandes.
        if !catalogueComplet {
            for serie in series where serie.couvertureLocaleURL != nil {
                guard !Task.isCancelled else { return }
                await EditionsLocales.rafraichirSerieComplete(serie, langue: langue)
            }
            guard !Task.isCancelled else { return }
            do {
                try contexte.save()
                catalogueComplet = true
            } catch {
                return
            }
        }

        // Rattrapage permanent, en file indienne : une requête par série
        // remplit son nom local ET les couvertures de tous ses tomes.
        let limiteNouvelEssai = Date().addingTimeInterval(-24 * 60 * 60)
        for serie in series where serie.couvertureLocaleURL == nil {
            guard !Task.isCancelled else { return }
            if let dernier = serie.dernierEssaiEditionLocale,
               dernier >= limiteNouvelEssai { continue }
            await EditionsLocales.rafraichirSerieComplete(serie, langue: langue)
        }
        // Les séries déjà illustrées vieillissent elles aussi : de nouveaux
        // tomes et dates de précommande apparaissent. On rafraîchit au plus
        // quatre des plus anciennes par lancement, en rotation, afin de ne pas
        // épuiser les quotas publics avec une grande bibliothèque.
        let seriesAVerifier = series
            .filter {
                $0.couvertureLocaleURL != nil
                    && ($0.dernierEssaiEditionLocale ?? .distantPast) < limiteNouvelEssai
            }
            .sorted {
                ($0.dernierEssaiEditionLocale ?? .distantPast)
                    < ($1.dernierEssaiEditionLocale ?? .distantPast)
            }
            .prefix(4)
        for serie in seriesAVerifier {
            guard !Task.isCancelled else { return }
            await EditionsLocales.rafraichirSerieComplete(serie, langue: langue)
        }
        for oeuvre in oeuvres where oeuvre.couvertureLocaleURL == nil {
            guard !Task.isCancelled else { return }
            if let dernier = oeuvre.dernierEssaiEditionLocale,
               dernier >= limiteNouvelEssai { continue }
            await EditionsLocales.rafraichirOeuvre(oeuvre, langue: langue)
        }
        try? contexte.save()
    }

    /// Répare les séries baptisées du nom d'un tome (« Kagurabachi, Vol. 1 »)
    /// par une résolution antérieure : on n'en garde que le nom de série.
    private func reparerNomsDeSeries() {
        let series = (try? contexte.fetch(FetchDescriptor<Serie>())) ?? []
        for serie in series {
            let nettoyage = Tomaison.decomposer(serie.nom)
            if nettoyage.numero != nil { serie.nom = nettoyage.base }
            for (code, nom) in serie.noms {
                let propre = Tomaison.decomposer(nom)
                if propre.numero != nil { serie.noms[code] = propre.base }
            }
            if let romaji = serie.nomRomaji {
                let propre = Tomaison.decomposer(romaji)
                if propre.numero != nil { serie.nomRomaji = propre.base }
            }
        }
    }
}

#Preview {
    RacineView()
        .modelContainer(Apercu.conteneur)
}

import SwiftUI
import SwiftData

enum Onglet: Hashable {
    case accueil, bibliotheque, decouverte, stats, recherche
}

struct RacineView: View {
    @Environment(\.modelContext) private var contexte
    @State private var onglet: Onglet = .accueil
    /// Nettoyage one-shot des données héritées ou corrompues des vieux bugs.
    @AppStorage("editionsLocalesV10") private var editionsMigrees = false
    /// Une seule fois : chaque série existante gagne le rayon complet du catalogue.
    @AppStorage("catalogueCompletV11") private var catalogueComplet = false
    /// Les couvertures locales posées par un simple homonyme de titre — avant
    /// que l'auteur ne départage — doivent repartir se faire vérifier.
    @AppStorage("editionsVerifieesV49") private var editionsVerifiees = false
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
        .task { await demarrage() }
    }

    /// Tout se répare sans intervention : noms de séries nettoyés, puis les
    /// éditions dans la langue du lecteur récupérées en tâche de fond.
    private func demarrage() async {
        reparerNomsDeSeries()

        let langue = Objectif.courant(dans: contexte).languePrincipale
        let series = (try? contexte.fetch(FetchDescriptor<Serie>())) ?? []
        let oeuvres = (try? contexte.fetch(FetchDescriptor<Oeuvre>())) ?? []

        if !editionsMigrees {
            // Une seule fois : purge des dégâts des anciens bugs — noms écrasés
            // par un script illisible ou par un AUTRE livre, couvertures d'une
            // autre édition (VO, VIZ, Carlsen…). Les états lu/possédé restent.
            editionsMigrees = true
            for serie in series {
                let referenceBase = Tomaison.decomposer(
                    serie.noms["en"] ?? serie.nomRomaji ?? serie.nom
                ).base
                for (code, nom) in serie.noms {
                    let base = Tomaison.decomposer(nom).base
                    let illisible = Titres.estNonLatin(base) && !Titres.litScriptNonLatin(code)
                    if illisible || !Tomaison.memeSerie(base, referenceBase) {
                        serie.noms[code] = nil
                    }
                }
                serie.couvertureLocaleURL = nil
                serie.resumeLocal = nil
                for tome in serie.tomes {
                    tome.couvertureURL = nil
                    tome.titre = nil
                    tome.isbn = nil
                    tome.pages = nil
                }
                ResolveurTomes.reinitialiser(serie)
            }
            for oeuvre in oeuvres {
                let referenceBase = Tomaison.decomposer(
                    oeuvre.titres["en"] ?? oeuvre.titreRomaji ?? oeuvre.titreOriginal
                ).base
                for (code, titre) in oeuvre.titres where code != "en" {
                    let base = Tomaison.decomposer(titre).base
                    let illisible = Titres.estNonLatin(base) && !Titres.litScriptNonLatin(code)
                    if illisible || !Tomaison.memeSerie(base, referenceBase) {
                        oeuvre.titres[code] = nil
                    }
                }
                oeuvre.couvertureLocaleURL = nil
                oeuvre.resumeLocal = nil
            }
        }

        // Une seule fois : tout ce qu'un homonyme de titre a pu poser est
        // rendu au doute. Un lecteur s'est retrouvé avec la couverture d'un
        // manuel de survie sur le livre qu'il venait de scanner ; effacer ces
        // données dérivées suffit, le rattrapage ci-dessous les refait avec
        // l'auteur pour juge. Rien de ce que le lecteur a saisi n'est touché.
        if !editionsVerifiees {
            editionsVerifiees = true
            for serie in series {
                serie.couvertureLocaleURL = nil
                serie.resumeLocal = nil
                ResolveurTomes.reinitialiser(serie)
            }
            for oeuvre in oeuvres {
                oeuvre.couvertureLocaleURL = nil
                oeuvre.resumeLocal = nil
            }
        }

        // Une seule fois : les séries d'avant la v0.11 récupèrent le rayon
        // complet — tous les tomes parus du catalogue, et les précommandes.
        if !catalogueComplet {
            for serie in series where serie.couvertureLocaleURL != nil {
                await EditionsLocales.rafraichirSerieComplete(serie, langue: langue)
            }
            catalogueComplet = true
        }

        // Rattrapage permanent, en file indienne : une requête par série
        // remplit son nom local ET les couvertures de tous ses tomes.
        for serie in series where serie.couvertureLocaleURL == nil {
            await EditionsLocales.rafraichirSerieComplete(serie, langue: langue)
        }
        for oeuvre in oeuvres where oeuvre.couvertureLocaleURL == nil {
            await EditionsLocales.rafraichirOeuvre(oeuvre, langue: langue)
        }
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

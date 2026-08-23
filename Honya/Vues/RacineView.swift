import SwiftUI
import SwiftData

enum Onglet: Hashable {
    case accueil, bibliotheque, stats, recherche
}

struct RacineView: View {
    @Environment(\.modelContext) private var contexte
    @State private var onglet: Onglet = .accueil
    /// Nettoyage one-shot des couvertures héritées d'autres éditions (VO, EN…).
    @AppStorage("editionsLocalesV9") private var editionsMigrees = false

    var body: some View {
        TabView(selection: $onglet) {
            Tab("Aujourd'hui", systemImage: "house.fill", value: Onglet.accueil) {
                AccueilView(allerRecherche: { onglet = .recherche })
            }
            Tab("Bibliothèque", systemImage: "books.vertical.fill", value: Onglet.bibliotheque) {
                BibliothequeView(allerRecherche: { onglet = .recherche })
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
            // Une seule fois : les métadonnées héritées d'une autre édition
            // (couverture VO du tome 1, titres VIZ…) repartent à zéro.
            editionsMigrees = true
            for serie in series {
                serie.couvertureLocaleURL = nil
                for tome in serie.tomes {
                    tome.couvertureURL = nil
                    tome.titre = nil
                    tome.isbn = nil
                    tome.pages = nil
                }
                ResolveurTomes.reinitialiser(serie)
            }
        }

        // Rattrapage permanent : tout ce qui n'a pas encore son édition locale
        // la récupère, en file indienne pour respecter les quotas.
        for serie in series where serie.couvertureLocaleURL == nil {
            await EditionsLocales.rafraichirSerie(serie, langue: langue)
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

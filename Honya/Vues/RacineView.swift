import SwiftUI
import SwiftData

enum Onglet: Hashable {
    case accueil, bibliotheque, stats, recherche
}

struct RacineView: View {
    @Environment(\.modelContext) private var contexte
    @State private var onglet: Onglet = .accueil

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
        .task { reparerNomsDeSeries() }
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

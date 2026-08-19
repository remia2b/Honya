import SwiftUI

enum Onglet: Hashable {
    case accueil, bibliotheque, stats, recherche
}

struct RacineView: View {
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
    }
}

#Preview {
    RacineView()
        .modelContainer(Apercu.conteneur)
}

import SwiftUI
import SwiftData

/// Page auteur, comme dans Apple Books : tout ce que vous possédez de cette
/// plume, réuni au même endroit, avec ce que vous en avez déjà lu.
struct FicheAuteurView: View {
    let auteur: String
    let langue: String

    @Query private var oeuvres: [Oeuvre]
    @Query private var series: [Serie]

    private var sesOeuvres: [Oeuvre] {
        oeuvres.filter { $0.auteurs.contains { $0.localizedCaseInsensitiveContains(auteur) } }
    }

    private var sesSeries: [Serie] {
        series.filter { ($0.auteur ?? "").localizedCaseInsensitiveContains(auteur) }
    }

    private var nbLus: Int {
        sesOeuvres.filter { $0.exemplaire?.statut == .lu }.count
            + sesSeries.reduce(0) { $0 + $1.nbLus }
    }

    private var minutes: Int {
        (sesOeuvres.flatMap(\.sessions) + sesSeries.flatMap(\.sessions))
            .reduce(0) { $0 + $1.dureeSecondes } / 60
    }

    var body: some View {
        VStack(spacing: 0) {
            entete
            GrilleOeuvres(
                oeuvres: sesOeuvres,
                series: sesSeries,
                langue: langue,
                messageVide: "Aucun titre de cet auteur dans votre bibliothèque."
            )
        }
        .navigationTitle(auteur)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var entete: some View {
        VStack(spacing: 10) {
            Text(initiales)
                .font(.chiffreSerif(26))
                .foregroundStyle(.white)
                .frame(width: 68, height: 68)
                .background(
                    RadialGradient(
                        colors: [Couleurs.accent.opacity(0.85), Couleurs.accent],
                        center: .topLeading, startRadius: 4, endRadius: 70
                    ),
                    in: Circle()
                )

            Text(auteur)
                .font(.titreOeuvre(22))
                .multilineTextAlignment(.center)

            HStack(spacing: 18) {
                statistique("\(sesOeuvres.count + sesSeries.count)", "en rayon")
                if nbLus > 0 { statistique("\(nbLus)", nbLus > 1 ? "lus" : "lu") }
                if minutes > 0 { statistique(dureeLisible, "de lecture") }
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private func statistique(_ valeur: String, _ libelle: String) -> some View {
        VStack(spacing: 1) {
            Text(valeur)
                .font(.system(size: 17, weight: .bold, design: .serif))
                .monospacedDigit()
            Text(libelle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var initiales: String {
        let mots = auteur.split(separator: " ").prefix(2)
        return mots.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }

    private var dureeLisible: String {
        minutes >= 60 ? "\(minutes / 60) h" : "\(minutes) min"
    }
}

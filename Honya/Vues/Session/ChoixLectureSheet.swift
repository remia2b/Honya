import SwiftData
import SwiftUI

/// Que lit-on maintenant ?
///
/// Le chronomètre partait tout seul sur le dernier livre ouvert — pratique
/// quand c'est le bon, agaçant sinon, et impossible à rattraper une fois la
/// session lancée. On demande donc, en mettant en tête ce qui est le plus
/// probable : les lectures en cours.
struct ChoixLectureSheet: View {
    /// Ce qui a été choisi, prêt à ouvrir le chronomètre.
    var surChoix: (CibleSession) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query private var exemplaires: [Exemplaire]
    @Query private var series: [Serie]
    @Query private var objectifs: [Objectif]

    private var langue: String {
        objectifs.first?.languePrincipale ?? Langues.codeAppareil
    }

    /// Les lectures commencées d'abord : c'est presque toujours l'une d'elles.
    private var enCours: [Exemplaire] {
        exemplaires
            .filter { $0.statut == .enCours }
            .sorted { ($0.dateDebut ?? .distantPast) > ($1.dateDebut ?? .distantPast) }
    }

    private var aLire: [Exemplaire] {
        exemplaires.filter { $0.statut == .aLire && $0.possede }
    }

    private var seriesEnCours: [Serie] {
        series.filter { $0.statut == .enCours }
    }

    var body: some View {
        NavigationStack {
            List {
                if !enCours.isEmpty {
                    Section("En cours") {
                        ForEach(enCours) { ligneLivre($0) }
                    }
                }
                if !seriesEnCours.isEmpty {
                    Section("Séries commencées") {
                        ForEach(seriesEnCours) { ligneSerie($0) }
                    }
                }
                if !aLire.isEmpty {
                    Section("À lire") {
                        ForEach(aLire) { ligneLivre($0) }
                    }
                }
                if enCours.isEmpty && seriesEnCours.isEmpty && aLire.isEmpty {
                    Text("Ajoutez un livre à votre bibliothèque pour lancer une session.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Que lisez-vous ?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func ligneLivre(_ exemplaire: Exemplaire) -> some View {
        if let oeuvre = exemplaire.oeuvre {
            Button {
                surChoix(.oeuvre(oeuvre))
                dismiss()
            } label: {
                ligne(
                    url: oeuvre.couvertureAffichee,
                    titre: oeuvre.titre(langue),
                    detail: oeuvre.auteurs.first,
                    manga: oeuvre.type != .livre
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func ligneSerie(_ serie: Serie) -> some View {
        Button {
            surChoix(.serie(serie))
            dismiss()
        } label: {
            ligne(
                url: serie.couvertureAffichee,
                titre: serie.nomAffiche(langue),
                detail: serie.auteur,
                manga: serie.type != .livre
            )
        }
        .buttonStyle(.plain)
    }

    private func ligne(
        url: String?, titre: String, detail: String?, manga: Bool
    ) -> some View {
        HStack(spacing: 12) {
            CouvertureView(urlString: url, titre: titre, coins: 4, manga: manga, cote: 400)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(titre)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "play.circle.fill")
                .font(.title3)
                .foregroundStyle(Couleurs.accent)
        }
        .contentShape(Rectangle())
    }
}

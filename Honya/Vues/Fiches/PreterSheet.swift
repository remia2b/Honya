import SwiftData
import SwiftUI

/// Prêter un livre : à qui, depuis maintenant.
///
/// Les personnes à qui l'on a déjà prêté reviennent en suggestion — on prête
/// presque toujours aux mêmes, autant leur éviter le clavier.
/// Ce qu'on prête : un livre seul ou le tome d'une série. Le geste est le
/// même, l'écran aussi — seul le porteur du nom change.
enum CiblePret {
    case exemplaire(Exemplaire)
    case tome(Tome)

    func confier(a personne: String) {
        switch self {
        case .exemplaire(let e): e.preteA = personne; e.preteLe = .now
        case .tome(let t): t.preteA = personne; t.preteLe = .now
        }
    }
}

struct PreterSheet: View {
    let cible: CiblePret
    let titre: String

    @Environment(\.dismiss) private var dismiss
    @Query private var exemplaires: [Exemplaire]
    @Query private var tomes: [Tome]
    @State private var nom = ""
    @FocusState private var clavier: Bool

    /// Les emprunteurs connus, du plus récent au plus ancien, sans doublon.
    private var habitues: [String] {
        var vus = Set<String>()
        // Livres seuls ET tomes : on prête aux mêmes personnes, quel que
        // soit le format de ce qu'on leur confie.
        let depuisLivres = exemplaires.compactMap { e -> (String, Date)? in
            guard let nom = e.preteA else { return nil }
            return (nom, e.preteLe ?? .distantPast)
        }
        let depuisTomes = tomes.compactMap { t -> (String, Date)? in
            guard let nom = t.preteA else { return nil }
            return (nom, t.preteLe ?? .distantPast)
        }
        return (depuisLivres + depuisTomes)
            .sorted { $0.1 > $1.1 }
            .map(\.0)
            .filter { vus.insert($0).inserted }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Prêter ce livre")
                .font(.system(size: 28, weight: .semibold, design: .serif))
                .padding(.top, 30)
            Text(titre)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.top, 4)
                .padding(.horizontal, 30)

            TextField("À qui ?", text: $nom)
                .textContentType(.name)
                .autocorrectionDisabled()
                .focused($clavier)
                .submitLabel(.done)
                .onSubmit(preter)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    Color(uiColor: .secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .padding(.horizontal, 24)
                .padding(.top, 24)

            if !habitues.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(habitues.prefix(8), id: \.self) { personne in
                            Button {
                                nom = personne
                                preter()
                            } label: {
                                Text(personne)
                                    .font(.subheadline.weight(.medium))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(
                                        Couleurs.accent.opacity(0.13),
                                        in: Capsule()
                                    )
                                    .foregroundStyle(Couleurs.accent)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.top, 12)
            }

            Button(action: preter) {
                Text("Prêter")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .foregroundStyle(.white)
                    .background(
                        Couleurs.accent,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .disabled(nom.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(nom.trimmingCharacters(in: .whitespaces).isEmpty ? 0.55 : 1)
            .padding(.horizontal, 24)
            .padding(.top, 22)

            Text("Le livre rejoint l'étagère « Prêtés » jusqu'à son retour.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 12)
                .padding(.bottom, 26)
        }
        .presentationDetents([.height(360)])
        .presentationDragIndicator(.visible)
        .onAppear { clavier = habitues.isEmpty }
    }

    private func preter() {
        let propre = nom.trimmingCharacters(in: .whitespaces)
        guard !propre.isEmpty else { return }
        cible.confier(a: propre)
        dismiss()
    }
}

import SwiftData
import SwiftUI

/// Prêter un livre : à qui, depuis maintenant.
///
/// Les personnes à qui l'on a déjà prêté reviennent en suggestion — on prête
/// presque toujours aux mêmes, autant leur éviter le clavier.
struct PreterSheet: View {
    let exemplaire: Exemplaire
    let titre: String

    @Environment(\.dismiss) private var dismiss
    @Query private var exemplaires: [Exemplaire]
    @State private var nom = ""
    @FocusState private var clavier: Bool

    /// Les emprunteurs connus, du plus récent au plus ancien, sans doublon.
    private var habitues: [String] {
        var vus = Set<String>()
        return exemplaires
            .filter { $0.preteA != nil }
            .sorted { ($0.preteLe ?? .distantPast) > ($1.preteLe ?? .distantPast) }
            .compactMap { $0.preteA }
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
        exemplaire.preteA = propre
        exemplaire.preteLe = .now
        dismiss()
    }
}

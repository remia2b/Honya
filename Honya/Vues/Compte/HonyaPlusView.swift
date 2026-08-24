import SwiftUI

/// L'écran Honya+ : ce que l'abonnement apporte, dit dans le ton de l'app.
///
/// Pendant TestFlight, le bouton active un essai local — les abonnements
/// StoreKit le remplaceront à la sortie App Store, sans toucher au reste.
struct HonyaPlusView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var droits = Droits.partage

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Couleurs.accent)
                    .padding(.top, 34)

                Text(verbatim: "Honya+")
                    .font(.system(size: 40, weight: .semibold, design: .serif))
                    .padding(.top, 12)

                Text("Pour ceux qui vivent dans leur bibliothèque.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
                    .padding(.horizontal, 30)

                VStack(alignment: .leading, spacing: 18) {
                    avantage("bell.badge.fill", "Alertes de sortie sur toutes vos séries")
                    avantage("person.badge.clock.fill", "Prêts de livres : qui a quoi, depuis quand")
                    avantage("barcode.viewfinder", "Scannez des étagères entières")
                    avantage("chart.bar.fill", "Vos statistiques sur tout l'historique")
                    avantage("square.grid.2x2.fill", "Étagères illimitées")
                    avantage("gift.fill", "La rétrospective complète de décembre")
                }
                .padding(26)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color(uiColor: .secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
                .padding(.horizontal, 24)
                .padding(.top, 28)

                Button {
                    droits.activerEssai()
                    dismiss()
                } label: {
                    Text("Débloquer pour l'essai TestFlight")
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
                .padding(.horizontal, 24)
                .padding(.top, 24)

                Text("Les abonnements ouvriront avec la sortie sur l'App Store.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)

                Button("Plus tard") { dismiss() }
                    .font(.subheadline.weight(.semibold))
                    .tint(.secondary)
                    .padding(.top, 18)
                    .padding(.bottom, 30)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.large])
    }

    private func avantage(_ symbole: String, _ texte: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Image(systemName: symbole)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Couleurs.accent)
                .frame(width: 24)
            Text(texte)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    HonyaPlusView()
}

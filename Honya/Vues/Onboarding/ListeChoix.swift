import SwiftUI

/// Une ligne de choix, à la manière des Réglages : le libellé, et un cercle
/// à droite qui se remplit.
///
/// Pas d'icône devant le libellé — un pictogramme pour « Livre » et un autre
/// pour « Manga » n'apprennent rien à personne, et deux symboles voisins se
/// confondent plus qu'ils n'aident. Le texte suffit.
struct LigneChoix: View {
    var libelle: String
    var choisi: Bool
    var teinte: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(libelle)
                    .font(.system(size: 16, weight: choisi ? .semibold : .regular))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 8)

                ZStack {
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.22), lineWidth: 1.5)
                    if choisi {
                        Circle().fill(teinte)
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 22, height: 22)
                // Le ressort : la coche se pose, elle n'apparaît pas.
                .animation(.spring(response: 0.3, dampingFraction: 0.55), value: choisi)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Le bloc qui contient les lignes : un fond translucide, un contour fin, et
/// des séparateurs qui ne courent pas jusqu'au bord.
struct BlocChoix<Contenu: View>: View {
    @ViewBuilder var contenu: () -> Contenu

    var body: some View {
        VStack(spacing: 0) {
            contenu()
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Le trait entre deux lignes, décalé pour ne pas toucher les bords.
struct SeparateurChoix: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.09))
            .frame(height: 1)
            .padding(.leading, 16)
    }
}

/// Le bouton du bas : plein, à coins doux, sans lueur autour — seulement un
/// liseré clair sur l'arête haute, et une brillance qui le traverse de temps
/// en temps pour qu'il ne soit pas tout à fait immobile.
struct BoutonAccueil: View {
    var titre: LocalizedStringKey
    var teinte: Color
    var actif: Bool
    var action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var mouvementReduit
    @State private var passage = false

    var body: some View {
        Button(action: action) {
            Text(titre)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    LinearGradient(
                        colors: [teinte.opacity(0.92), teinte],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.white.opacity(0.3))
                        .frame(height: 1)
                }
                .overlay {
                    if !mouvementReduit {
                        GeometryReader { geo in
                            LinearGradient(
                                colors: [.clear, .white.opacity(0.3), .clear],
                                startPoint: .leading, endPoint: .trailing
                            )
                            .frame(width: geo.size.width * 0.45)
                            .offset(x: passage ? geo.size.width * 1.2 : -geo.size.width * 0.6)
                        }
                        .allowsHitTesting(false)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!actif)
        .opacity(actif ? 1 : 0.45)
        .onAppear {
            guard !mouvementReduit else { return }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false).delay(2.4)) {
                passage = true
            }
        }
    }
}

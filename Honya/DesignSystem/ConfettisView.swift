import SwiftUI

// MARK: - Célébrations
// Un seul endroit déclenche la pluie de confettis plein écran : finir un
// livre, finir une série. La racine de l'app observe et affiche.

@Observable
final class Celebrations {
    static let partage = Celebrations()

    var actif = false
    var message = ""

    private var extinction: Task<Void, Never>?

    @MainActor
    func feter(_ message: String) {
        self.message = message
        withAnimation(.spring(duration: 0.3)) { actif = true }
        extinction?.cancel()
        extinction = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3.4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.5)) { self.actif = false }
        }
    }
}

// MARK: - La pluie de confettis

struct ConfettisView: View {
    let message: String

    var body: some View {
        ZStack {
            PluieConfettis()

            VStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(Couleurs.accent)
                Text(message)
                    .font(.system(size: 28, weight: .semibold, design: .serif))
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 24, y: 10)
        }
        .allowsHitTesting(false)
    }
}

/// La pluie seule, sans message : la roue la veut nue sur son écran de gain.
struct PluieConfettis: View {
    @State private var depart = Date()
    @State private var particules: [Particule] = []

    private struct Particule {
        let x: Double          // position horizontale relative (0…1)
        let teinte: Color
        let delai: Double      // départ décalé, pour une pluie vivante
        let vitesse: Double    // hauteur d'écran par seconde
        let taille: Double
        let rotation: Double   // tours par seconde
        let oscillation: Double
    }

    private static let teintes: [Color] = [
        Couleurs.accent, Couleurs.lu, Couleurs.aLire, Couleurs.wishlist,
        .orange, .yellow,
    ]

    var body: some View {
        TimelineView(.animation) { chrono in
            let temps = chrono.date.timeIntervalSince(depart)
            Canvas { contexte, taille in
                for particule in particules {
                    let vie = temps - particule.delai
                    guard vie > 0 else { continue }

                    let y = -30 + vie * particule.vitesse * taille.height
                    guard y < taille.height + 40 else { continue }
                    let x = particule.x * taille.width
                        + sin(vie * particule.oscillation) * 26

                    let alpha = vie < 2.2 ? 1.0 : max(0, 1 - (vie - 2.2) / 0.8)
                    var calque = contexte
                    calque.opacity = alpha
                    calque.translateBy(x: x, y: y)
                    calque.rotate(by: .radians(vie * particule.rotation * 2 * .pi))

                    let rect = CGRect(
                        x: -particule.taille / 2,
                        y: -particule.taille / 3.4,
                        width: particule.taille,
                        height: particule.taille / 1.7
                    )
                    calque.fill(
                        Path(roundedRect: rect, cornerRadius: 1.5),
                        with: .color(particule.teinte)
                    )
                }
            }
        }
        .ignoresSafeArea()
        .onAppear(perform: semer)
    }

    /// Les particules sont tirées une seule fois : un tirage à chaque image
    /// ne ressemblerait à rien.
    private func semer() {
        depart = Date()
        particules = (0..<110).map { _ in
            Particule(
                x: .random(in: 0...1),
                teinte: Self.teintes.randomElement() ?? Couleurs.accent,
                delai: .random(in: 0...0.9),
                vitesse: .random(in: 0.35...0.75),
                taille: .random(in: 7...13),
                rotation: .random(in: 0.6...2.2) * (Bool.random() ? 1 : -1),
                oscillation: .random(in: 1.2...3.4)
            )
        }
    }
}

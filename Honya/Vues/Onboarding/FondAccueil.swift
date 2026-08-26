import SwiftUI
import UIKit

/// Le fond des écrans d'accueil : trois auréoles de couleur qui dérivent
/// lentement, sous un grain fin.
///
/// Le mur de couvertures a été essayé et écarté : il gênait la lecture, et
/// il appartient déjà à l'écran de connexion — l'accueil se serait répété.
/// Ici il n'y a rien à déchiffrer derrière le texte, seulement de la
/// profondeur. Le grain compte autant que les auréoles : sans lui, un
/// dégradé pur a l'air de plastique.
struct FondAccueil: View {
    /// La teinte de l'étape. L'ambre accueille, le vert dit que ça avance.
    var teinte: Color

    @Environment(\.colorScheme) private var apparence
    @Environment(\.accessibilityReduceMotion) private var mouvementReduit
    @State private var derive = false

    private var sombre: Bool { apparence == .dark }

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)

            GeometryReader { geo in
                let l = geo.size.width
                let h = geo.size.height

                ZStack {
                    auréole(teinte.opacity(0.85), largeur: l * 1.05, hauteur: h * 0.42)
                        .offset(x: -l * 0.22, y: -h * 0.10)
                        .offset(x: derive ? l * 0.16 : 0, y: derive ? h * 0.06 : 0)
                        .scaleEffect(derive ? 1.16 : 1)
                        .animation(rythme(19), value: derive)

                    auréole(teinte, largeur: l * 0.9, hauteur: h * 0.36)
                        .offset(x: l * 0.28, y: h * 0.04)
                        .offset(x: derive ? -l * 0.13 : 0, y: derive ? h * 0.10 : 0)
                        .scaleEffect(derive ? 0.92 : 1.08)
                        .animation(rythme(23), value: derive)

                    auréole(teinte.opacity(0.6), largeur: l * 1.1, hauteur: h * 0.32)
                        .offset(x: -l * 0.04, y: h * 0.26)
                        .offset(x: derive ? l * 0.09 : 0, y: derive ? -h * 0.09 : 0)
                        .scaleEffect(derive ? 1.14 : 0.94)
                        .animation(rythme(27), value: derive)
                }
                .blur(radius: 62)
                .opacity(sombre ? 0.5 : 0.55)
            }

            // Le voile : le haut respire la couleur, le bas redevient net pour
            // que le texte et les listes se lisent sans effort.
            LinearGradient(
                stops: [
                    .init(color: fond.opacity(0.24), location: 0),
                    .init(color: fond.opacity(0.64), location: 0.36),
                    .init(color: fond.opacity(0.93), location: 0.66),
                    .init(color: fond, location: 0.88),
                ],
                startPoint: .top, endPoint: .bottom
            )

            Image(uiImage: Self.grain)
                .resizable(resizingMode: .tile)
                .blendMode(.overlay)
                .opacity(sombre ? 0.5 : 0.3)
                .allowsHitTesting(false)
        }
        .onAppear {
            guard !mouvementReduit else { return }
            derive = true
        }
    }

    private var fond: Color { Color(uiColor: .systemBackground) }

    private func auréole(_ couleur: Color, largeur: CGFloat, hauteur: CGFloat) -> some View {
        Ellipse()
            .fill(couleur)
            .frame(width: largeur, height: hauteur)
    }

    /// Des durées volontairement premières entre elles : les trois auréoles ne
    /// repassent jamais par la même figure, le fond ne se répète pas.
    private func rythme(_ duree: Double) -> Animation? {
        mouvementReduit
            ? nil
            : .easeInOut(duration: duree).repeatForever(autoreverses: true)
    }

    /// Le grain, dessiné une seule fois puis répété en mosaïque.
    private static let grain: UIImage = {
        let cote = 128
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(
            size: CGSize(width: cote, height: cote), format: format
        ).image { contexte in
            let cg = contexte.cgContext
            for x in 0..<cote {
                for y in 0..<cote {
                    let valeur = CGFloat.random(in: 0.42...0.58)
                    cg.setFillColor(gray: valeur, alpha: 1)
                    cg.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
    }()
}

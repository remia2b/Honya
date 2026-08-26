import SwiftUI
import UIKit

/// Le fond des écrans d'accueil : trois auréoles de couleur qui dérivent
/// lentement, sous un grain fin.
///
/// Le mur de couvertures a été essayé et écarté : il gênait la lecture, et il
/// appartient déjà à l'écran de connexion — l'accueil se serait répété. Ici il
/// n'y a rien à déchiffrer derrière le texte, seulement de la profondeur. Le
/// grain compte autant que les auréoles : sans lui, un dégradé pur a l'air de
/// plastique.
///
/// Le mouvement vient d'une horloge, PAS d'une animation SwiftUI. Une
/// animation `repeatForever` capture les changements de ses enfants : le
/// virage de teinte d'une étape à l'autre se retrouvait étalé sur vingt
/// secondes, et le fond restait ambre alors que l'écran était déjà vert. Avec
/// l'horloge, la position est un simple calcul à chaque image — rien à
/// capturer, et la couleur change quand on le lui demande.
struct FondAccueil: View {
    /// La teinte de l'étape. L'ambre accueille, le vert dit que ça avance.
    var teinte: Color

    @Environment(\.colorScheme) private var apparence
    @Environment(\.accessibilityReduceMotion) private var mouvementReduit

    private var sombre: Bool { apparence == .dark }

    /// Chaque auréole a sa taille, son ancrage, sa course et sa période. Des
    /// périodes premières entre elles : les trois ne repassent jamais par la
    /// même figure, le fond ne se répète pas.
    private struct Aureole {
        let largeur: CGFloat, hauteur: CGFloat
        let x: CGFloat, y: CGFloat
        let courseX: CGFloat, courseY: CGFloat
        let periode: Double
        let opacite: Double
    }

    private static let aureoles: [Aureole] = [
        .init(largeur: 1.05, hauteur: 0.42, x: -0.22, y: -0.10,
              courseX: 0.16, courseY: 0.06, periode: 19, opacite: 0.85),
        .init(largeur: 0.90, hauteur: 0.36, x: 0.28, y: 0.04,
              courseX: -0.13, courseY: 0.10, periode: 23, opacite: 1),
        .init(largeur: 1.10, hauteur: 0.32, x: -0.04, y: 0.26,
              courseX: 0.09, courseY: -0.09, periode: 27, opacite: 0.6),
    ]

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)

            TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: mouvementReduit)) { contexte in
                GeometryReader { geo in
                    let instant = contexte.date.timeIntervalSinceReferenceDate
                    ZStack {
                        ForEach(Array(Self.aureoles.enumerated()), id: \.offset) { _, aureole in
                            auréole(aureole, dans: geo.size, instant: instant)
                        }
                    }
                    .blur(radius: 62)
                    .opacity(sombre ? 0.5 : 0.55)
                }
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
    }

    private var fond: Color { Color(uiColor: .systemBackground) }

    private func auréole(
        _ aureole: Aureole, dans taille: CGSize, instant: TimeInterval
    ) -> some View {
        // Une sinusoïde : la dérive va et vient sans jamais s'arrêter net.
        let phase = sin(instant / aureole.periode * 2 * .pi)
        let ampleur = (phase + 1) / 2

        return Ellipse()
            .fill(teinte.opacity(aureole.opacite))
            .frame(width: taille.width * aureole.largeur,
                   height: taille.height * aureole.hauteur)
            .scaleEffect(1 + 0.14 * ampleur)
            .offset(
                x: taille.width * (aureole.x + aureole.courseX * ampleur),
                y: taille.height * (aureole.y + aureole.courseY * ampleur)
            )
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
                    cg.setFillColor(gray: CGFloat.random(in: 0.42...0.58), alpha: 1)
                    cg.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
    }()
}

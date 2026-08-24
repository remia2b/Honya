import SwiftUI

/// La roue de la deuxième chance, au refus de l'écran Honya+.
///
/// Elle n'apparaît qu'une fois par personne, et jamais à l'ouverture de l'app.
/// Premier tour perdant, puis « tout le monde a droit à une deuxième chance » :
/// c'est le mécanisme de Yazio, qui l'affiche jusqu'à 75 %.
///
/// Le gain n'invente pas un prix : il révèle une offre d'introduction qui
/// existe déjà dans App Store Connect. La roue est la mise en scène, pas la
/// facturation.
struct RoueSheet: View {
    /// Appelé quand tout est fini, pour refermer l'écran Honya+ derrière.
    var surFermeture: () -> Void = {}
    /// Ouvre directement sur le gain, pour les aperçus et les captures.
    var surLeGain = false

    @Environment(\.dismiss) private var dismiss
    @AppStorage("roueUtilisee") private var utilisee = false

    @State private var etape: Etape = .avantPremier
    @State private var angle: Double = 0
    @State private var apparu = false

    private enum Etape { case avantPremier, tourne, entreDeux, gagne }

    /// Une seule fois par personne : la deuxième chance n'en est une que si
    /// elle ne revient pas tous les jours.
    @MainActor
    static var disponible: Bool {
        !UserDefaults.standard.bool(forKey: "roueUtilisee") && !Droits.partage.plus
    }

    // MARK: - Les secteurs

    private struct Secteur {
        let libelle: LocalizedStringKey
        let gagnant: Bool
        let teinte: Color
    }

    private static let secteurs: [Secteur] = [
        .init(libelle: "−40 %", gagnant: true,  teinte: Color(red: 0.85, green: 0.36, blue: 0.06)),
        .init(libelle: "Rien",  gagnant: false, teinte: Color(red: 0.29, green: 0.24, blue: 0.20)),
        .init(libelle: "−15 %", gagnant: true,  teinte: Color(red: 0.93, green: 0.62, blue: 0.16)),
        .init(libelle: "Rien",  gagnant: false, teinte: Color(red: 0.35, green: 0.29, blue: 0.24)),
        .init(libelle: "−25 %", gagnant: true,  teinte: Color(red: 0.78, green: 0.26, blue: 0.22)),
        .init(libelle: "Rien",  gagnant: false, teinte: Color(red: 0.29, green: 0.24, blue: 0.20)),
        .init(libelle: "−10 %", gagnant: true,  teinte: Color(red: 0.96, green: 0.75, blue: 0.28)),
        .init(libelle: "Rien",  gagnant: false, teinte: Color(red: 0.35, green: 0.29, blue: 0.24)),
    ]

    private static let part = 360.0 / Double(secteurs.count)

    /// L'angle du milieu d'un secteur, en degrés, zéro pointant vers le haut.
    private static func milieu(_ index: Int) -> Double {
        Double(index) * part + part / 2
    }

    /// L'inclinaison de l'étiquette. Dans la moitié basse de la roue, on la
    /// retourne : sans ça elle se lirait à l'envers.
    private static func orientation(_ index: Int) -> Double {
        let angle = milieu(index)
        return (angle > 90 && angle < 270) ? angle - 90 : angle + 90
    }

    /// Où poser l'étiquette d'un secteur. Sortie de la vue : l'inférence de
    /// types de SwiftUI cale sur une trigonométrie écrite en ligne.
    private static func position(_ index: Int) -> CGSize {
        let radians = (milieu(index) - 90) * .pi / 180
        let rayon = 92.0
        return CGSize(width: rayon * cos(radians), height: rayon * sin(radians))
    }

    /// L'angle qui amène le milieu du secteur sous la flèche, après `tours`.
    private static func arret(sur index: Int, tours: Int) -> Double {
        Double(tours) * 360 - milieu(index)
    }

    var body: some View {
        ZStack {
            fond.ignoresSafeArea()

            // Le contenu défile si l'écran est petit ; les boutons, eux,
            // vivent dans une zone ancrée et ne peuvent jamais être coupés.
            ScrollView {
                VStack(spacing: 0) {
                    if etape == .gagne {
                        gain
                    } else {
                        entete
                        roue.padding(.top, 22).padding(.bottom, 26)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaInset(edge: .bottom) {
                (etape == .gagne ? AnyView(actionGain) : AnyView(action))
                    .padding(.bottom, 12)
            }

            if etape == .gagne {
                PluieConfettis()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) { apparu = true }
            if surLeGain { etape = .gagne }
        }
    }

    private var fond: some View {
        LinearGradient(
            colors: etape == .gagne
                ? [Color(red: 0.76, green: 0.37, blue: 0.05),
                   Color(red: 0.50, green: 0.21, blue: 0.02),
                   Color(red: 0.34, green: 0.14, blue: 0.02)]
                : [Color(red: 0.16, green: 0.12, blue: 0.10),
                   Color(red: 0.10, green: 0.08, blue: 0.07)],
            startPoint: .top, endPoint: .bottom
        )
        .animation(.easeInOut(duration: 0.6), value: etape)
    }

    // MARK: - Avant de tourner

    private var entete: some View {
        VStack(spacing: 12) {
            Text(etape == .entreDeux
                 ? "Tout le monde a droit à une deuxième chance"
                 : "Une chance, avant de partir")
                .font(.system(size: 29, weight: .semibold, design: .serif))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text(etape == .entreDeux
                 ? "Votre premier tour n'a rien donné. Celui-ci est le bon."
                 : "Un tour de roue, sans rien acheter.")
                .font(.system(size: 15.5))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 34)
        .padding(.top, 20)
        .animation(.snappy, value: etape)
    }

    // MARK: - La roue

    private var roue: some View {
        ZStack {
            // Le cerclage, avec ses ampoules de fête foraine.
            Circle()
                .fill(Color(red: 0.20, green: 0.15, blue: 0.12))
                .overlay(Circle().strokeBorder(Color(red: 0.96, green: 0.75, blue: 0.28), lineWidth: 3))
                .shadow(color: .black.opacity(0.5), radius: 26, y: 12)
            ForEach(0..<16, id: \.self) { rang in
                Circle()
                    .fill(Color(red: 1, green: 0.90, blue: 0.68))
                    .frame(width: 5, height: 5)
                    .offset(y: -145)
                    .rotationEffect(.degrees(Double(rang) * 22.5))
                    .opacity(etape == .tourne ? 0.45 : 1)
            }

            // Les parts, dessinées à l'arc.
            ZStack {
                ForEach(Array(Self.secteurs.enumerated()), id: \.offset) { index, secteur in
                    Part(index: index, part: Self.part)
                        .fill(secteur.teinte)
                        .overlay(
                            Part(index: index, part: Self.part)
                                .stroke(Color.black.opacity(0.18), lineWidth: 1)
                        )
                    Text(secteur.libelle)
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(
                            secteur.gagnant ? AnyShapeStyle(Color.white)
                                            : AnyShapeStyle(Color.white.opacity(0.42))
                        )
                        .rotationEffect(.degrees(Self.orientation(index)))
                        .offset(Self.position(index))
                }
            }
            .frame(width: 268, height: 268)
            .rotationEffect(.degrees(angle))

            // Le moyeu.
            Circle()
                .fill(Color(red: 0.96, green: 0.75, blue: 0.28))
                .frame(width: 66, height: 66)
                .overlay(
                    Image(systemName: "book.closed.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Color(red: 0.34, green: 0.14, blue: 0.02))
                )
                .shadow(color: .black.opacity(0.35), radius: 8, y: 3)

            // La flèche, en haut, fixe.
            Triangle()
                .fill(Color(red: 1, green: 0.93, blue: 0.76))
                .frame(width: 26, height: 22)
                .offset(y: -152)
                .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
        }
        .frame(width: 300, height: 300)
        .scaleEffect(apparu ? 1 : 0.86)
        .opacity(apparu ? 1 : 0)
    }

    // MARK: - Le bouton

    private var action: some View {
        VStack(spacing: 14) {
            Button(action: tourner) {
                Text(etape == .entreDeux ? "Retenter ma chance" : "Faire tourner la roue")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .foregroundStyle(Color(red: 0.20, green: 0.10, blue: 0.03))
                    .background(
                        Color(red: 0.96, green: 0.78, blue: 0.34),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .disabled(etape == .tourne)
            .opacity(etape == .tourne ? 0.5 : 1)

            Button("Non merci") { fermer() }
                .font(.system(size: 15))
                .tint(.white.opacity(0.55))
        }
        .padding(.horizontal, 30)
        .padding(.top, 20)
    }

    // MARK: - Le gain

    private var gain: some View {
        VStack(spacing: 0) {
            Text(verbatim: "−40 %")
                .font(.system(size: 68, weight: .semibold, design: .serif))
                .foregroundStyle(Color(red: 1, green: 0.90, blue: 0.78))

            Text("La première année à 17,99 €")
                .font(.system(size: 26, weight: .semibold, design: .serif))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
                .padding(.horizontal, 34)

            billet.padding(.top, 26).padding(.horizontal, 30)

            VStack(alignment: .leading, spacing: 13) {
                gagne("books.vertical.fill", "Séries automatiques sans limite")
                gagne("bell.badge.fill", "Alertes à chaque nouveau tome")
                gagne("barcode.viewfinder", "Scan illimité, étagères entières")
                gagne("chart.bar.fill", "Tout votre historique de lecture")
            }
            .padding(.top, 26)
            .padding(.horizontal, 34)
            .frame(maxWidth: .infinity, alignment: .leading)

        }
        .padding(.top, 26)
        .padding(.bottom, 10)
        .transition(.opacity)
    }

    private var actionGain: some View {
        VStack(spacing: 0) {
            Button {
                Droits.partage.activerEssai()
                fermer()
            } label: {
                Text("Profiter des 17,99 €")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .foregroundStyle(Color(red: 0.50, green: 0.21, blue: 0.02))
                    .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)

            Button("Plus tard") { fermer() }
                .font(.system(size: 15))
                .tint(.white.opacity(0.6))
                .padding(.top, 12)

            Text("Cette offre n'est proposée qu'une fois.")
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.top, 8)
        }
        .padding(.horizontal, 30)
    }

    /// Un billet de tombola : le prix barré, le nouveau à côté. C'est lui qui
    /// remplit le vide que laissait le grand chiffre tout seul.
    private var billet: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "Honya+")
                    .font(.system(size: 19, weight: .semibold, design: .serif))
                Text("un an")
                    .font(.system(size: 13))
                    .opacity(0.7)
            }
            Spacer(minLength: 12)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: "29,99 €")
                    .font(.system(size: 15))
                    .strikethrough()
                    .opacity(0.55)
                Text(verbatim: "17,99 €")
                    .font(.system(size: 24, weight: .semibold, design: .serif))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(0.13))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    .white.opacity(0.45),
                    style: StrokeStyle(lineWidth: 1.5, dash: [7, 5])
                )
        )
    }

    private func gagne(_ symbole: String, _ texte: LocalizedStringKey) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbole)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(red: 1, green: 0.90, blue: 0.78))
                .frame(width: 22)
            Text(texte)
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.92))
            Spacer(minLength: 0)
        }
    }

    // MARK: - La mécanique

    private func tourner() {
        let premierTour = etape == .avantPremier
        // Un secteur perdant au premier tour, le meilleur au second : la
        // « deuxième chance » n'en est pas une, et c'est assumé.
        let cible = premierTour ? 5 : 0
        let tours = premierTour ? 4 : 6

        etape = .tourne
        // On repart du tour entier suivant : sans ça, le second lancer
        // calculerait un angle plus petit que le premier et la roue
        // reviendrait en arrière.
        let base = (angle / 360).rounded(.up) * 360
        withAnimation(.timingCurve(0.17, 0.72, 0.15, 1, duration: premierTour ? 3.2 : 4.0)) {
            angle = base + Double(tours) * 360 - Self.milieu(cible)
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(premierTour ? 3.4 : 4.2))
            withAnimation(.snappy(duration: 0.45)) {
                etape = premierTour ? .entreDeux : .gagne
            }
            if !premierTour { utilisee = true }
        }
    }

    private func fermer() {
        utilisee = true
        dismiss()
        surFermeture()
    }
}

// MARK: - Formes

/// Une part de roue : un secteur circulaire depuis le centre.
private struct Part: Shape {
    let index: Int
    let part: Double

    func path(in rect: CGRect) -> Path {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let rayon = min(rect.width, rect.height) / 2
        var chemin = Path()
        chemin.move(to: centre)
        chemin.addArc(
            center: centre,
            radius: rayon,
            startAngle: .degrees(Double(index) * part - 90),
            endAngle: .degrees(Double(index + 1) * part - 90),
            clockwise: false
        )
        chemin.closeSubpath()
        return chemin
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var chemin = Path()
        chemin.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        chemin.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        chemin.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        chemin.closeSubpath()
        return chemin
    }
}

#Preview {
    RoueSheet()
}

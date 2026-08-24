import SwiftUI

/// La roue promotionnelle, proposée au refus de l'écran Honya+.
///
/// Elle n'apparaît qu'une fois par personne, et jamais à l'ouverture de
/// l'application. Le parcours tient en trois temps : un tour, une page
/// intermédiaire, puis l'offre. Chacun a sa page pour rester lisible.
///
/// L'offre n'invente pas un prix : elle révèle un tarif d'introduction déclaré
/// dans App Store Connect. La roue est la présentation, pas la facturation.
struct RoueSheet: View {
    /// Appelé quand tout est fini, pour refermer l'écran Honya+ derrière.
    var surFermeture: () -> Void = {}
    /// Ouvre directement sur une étape, pour les aperçus et les captures.
    var etapeDepart: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var apparence
    @AppStorage("roueUtilisee") private var utilisee = false

    @State private var etape: Etape = .avantPremier
    @State private var angle: Double = 0
    @State private var apparu = false

    private enum Etape { case avantPremier, tourne, perdu, avantSecond, gagne }

    private var sombre: Bool { apparence == .dark }

    /// Une seule fois par personne : une offre qui revient tous les jours
    /// n'est plus une offre.
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
        .init(libelle: "Rien",  gagnant: false, teinte: Color(red: 0.42, green: 0.36, blue: 0.30)),
        .init(libelle: "−15 %", gagnant: true,  teinte: Color(red: 0.93, green: 0.62, blue: 0.16)),
        .init(libelle: "Rien",  gagnant: false, teinte: Color(red: 0.50, green: 0.43, blue: 0.36)),
        .init(libelle: "−25 %", gagnant: true,  teinte: Color(red: 0.78, green: 0.26, blue: 0.22)),
        .init(libelle: "Rien",  gagnant: false, teinte: Color(red: 0.42, green: 0.36, blue: 0.30)),
        .init(libelle: "−10 %", gagnant: true,  teinte: Color(red: 0.96, green: 0.75, blue: 0.28)),
        .init(libelle: "Rien",  gagnant: false, teinte: Color(red: 0.50, green: 0.43, blue: 0.36)),
    ]

    private static let part = 360.0 / Double(secteurs.count)

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

    // MARK: - Les couleurs, selon le thème

    private var encre: Color { sombre ? .white : Color(red: 0.16, green: 0.11, blue: 0.06) }
    private var encreDouce: Color { encre.opacity(sombre ? 0.7 : 0.62) }
    private var cerclage: Color {
        sombre ? Color(red: 0.96, green: 0.75, blue: 0.28)
               : Color(red: 0.82, green: 0.55, blue: 0.13)
    }
    private var fondRoue: Color {
        sombre ? Color(red: 0.20, green: 0.15, blue: 0.12)
               : Color(red: 0.99, green: 0.96, blue: 0.90)
    }

    var body: some View {
        ZStack {
            fond.ignoresSafeArea()

            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 0) {
                        switch etape {
                        case .gagne: gain
                        case .perdu: pageDeuxiemeChance
                        default:
                            entete
                            roue.padding(.top, 22).padding(.bottom, 26)
                        }
                    }
                    // Centré tant que ça tient, défilant au-delà.
                    .frame(maxWidth: .infinity, minHeight: geo.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .safeAreaInset(edge: .bottom) { bas.padding(.bottom, 12) }

            if etape == .gagne {
                PluieConfettis()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) { apparu = true }
            switch etapeDepart {
            case "gain": etape = .gagne
            case "perdu": etape = .perdu
            default: break
            }
        }
    }

    private var fond: some View {
        LinearGradient(
            colors: etape == .gagne
                ? [Color(red: 0.76, green: 0.37, blue: 0.05),
                   Color(red: 0.50, green: 0.21, blue: 0.02),
                   Color(red: 0.34, green: 0.14, blue: 0.02)]
                : sombre
                    ? [Color(red: 0.16, green: 0.12, blue: 0.10),
                       Color(red: 0.10, green: 0.08, blue: 0.07)]
                    : [Color(red: 1.00, green: 0.93, blue: 0.83),
                       Color(red: 0.99, green: 0.96, blue: 0.92)],
            startPoint: .top, endPoint: .bottom
        )
        .animation(.easeInOut(duration: 0.6), value: etape)
    }

    // MARK: - Avant de tourner

    private var entete: some View {
        VStack(spacing: 12) {
            Text(etape == .avantSecond
                 ? "Votre deuxième chance"
                 : "Une chance, avant de partir")
                .font(.system(size: 29, weight: .semibold, design: .serif))
                .foregroundStyle(encre)
                .multilineTextAlignment(.center)

            Text(etape == .avantSecond
                 ? "Celui-ci est le bon. Faites-la tourner."
                 : "Un tour de roue, sans rien acheter.")
                .font(.system(size: 15.5))
                .foregroundStyle(encreDouce)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 34)
        .padding(.top, 20)
        .animation(.snappy, value: etape)
    }

    // MARK: - La roue

    private var roue: some View {
        ZStack {
            Circle()
                .fill(fondRoue)
                .overlay(Circle().strokeBorder(cerclage, lineWidth: 3))
                .shadow(color: .black.opacity(sombre ? 0.5 : 0.18), radius: 26, y: 12)
            ForEach(0..<16, id: \.self) { rang in
                Circle()
                    .fill(cerclage.opacity(sombre ? 0.9 : 0.8))
                    .frame(width: 5, height: 5)
                    .offset(y: -145)
                    .rotationEffect(.degrees(Double(rang) * 22.5))
                    .opacity(etape == .tourne ? 0.45 : 1)
            }

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
                                            : AnyShapeStyle(Color.white.opacity(0.55))
                        )
                        .rotationEffect(.degrees(Self.orientation(index)))
                        .offset(Self.position(index))
                }
            }
            .frame(width: 268, height: 268)
            .rotationEffect(.degrees(angle))

            Circle()
                .fill(cerclage)
                .frame(width: 66, height: 66)
                .overlay(
                    Image(systemName: "book.closed.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Color(red: 0.34, green: 0.14, blue: 0.02))
                )
                .shadow(color: .black.opacity(0.35), radius: 8, y: 3)

            Triangle()
                .fill(sombre ? Color(red: 1, green: 0.93, blue: 0.76)
                             : Color(red: 0.68, green: 0.28, blue: 0.04))
                .frame(width: 26, height: 22)
                .offset(y: -152)
                .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
        }
        .frame(width: 300, height: 300)
        .scaleEffect(apparu ? 1 : 0.86)
        .opacity(apparu ? 1 : 0)
    }

    // MARK: - La page de la deuxième chance

    private var pageDeuxiemeChance: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(cerclage.opacity(sombre ? 0.16 : 0.22))
                    .frame(width: 132, height: 132)
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(cerclage)
            }
            .padding(.bottom, 30)

            Text("Rien cette fois.")
                .font(.system(size: 21, design: .serif))
                .foregroundStyle(encreDouce)

            Text("Tout le monde a droit à une deuxième chance")
                .font(.system(size: 32, weight: .semibold, design: .serif))
                .foregroundStyle(encre)
                .multilineTextAlignment(.center)
                .padding(.top, 10)
                .padding(.horizontal, 30)

            Text("Une seule autre, et elle est pour vous.")
                .font(.system(size: 16))
                .foregroundStyle(encreDouce)
                .multilineTextAlignment(.center)
                .padding(.top, 12)
                .padding(.horizontal, 40)
        }
        .padding(.vertical, 30)
        .transition(.opacity)
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

    /// Un billet de tombola : le prix barré, le nouveau à côté.
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

    // MARK: - Le bas, selon l'étape

    @ViewBuilder
    private var bas: some View {
        switch etape {
        case .gagne: actionGain
        case .perdu: actionDeuxiemeChance
        default: actionRoue
        }
    }

    private var actionRoue: some View {
        VStack(spacing: 14) {
            Button(action: tourner) {
                boutonJaune(etape == .avantSecond ? "Retenter ma chance" : "Faire tourner la roue")
            }
            .buttonStyle(.plain)
            .disabled(etape == .tourne)
            .opacity(etape == .tourne ? 0.5 : 1)

            Button("Non merci") { fermer() }
                .font(.system(size: 15))
                .tint(encreDouce)
        }
        .padding(.horizontal, 30)
    }

    private var actionDeuxiemeChance: some View {
        VStack(spacing: 14) {
            Button {
                withAnimation(.snappy(duration: 0.4)) { etape = .avantSecond }
            } label: {
                boutonJaune("Retenter ma chance")
            }
            .buttonStyle(.plain)

            Button("Non merci") { fermer() }
                .font(.system(size: 15))
                .tint(encreDouce)
        }
        .padding(.horizontal, 30)
    }

    private func boutonJaune(_ titre: LocalizedStringKey) -> some View {
        Text(titre)
            .font(.system(size: 17, weight: .semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .foregroundStyle(Color(red: 0.20, green: 0.10, blue: 0.03))
            .background(
                Color(red: 0.96, green: 0.78, blue: 0.34),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
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

    // MARK: - La mécanique

    private func tourner() {
        let premierTour = etape == .avantPremier
        // Le secteur d'arrivée est fixé par le parcours promotionnel.
        let cible = premierTour ? 5 : 0
        let tours = premierTour ? 4 : 6

        etape = .tourne
        // On repart du tour entier suivant : sans ça, le second lancer
        // calculerait un angle plus petit et la roue reviendrait en arrière.
        let base = (angle / 360).rounded(.up) * 360
        withAnimation(.timingCurve(0.17, 0.72, 0.15, 1, duration: premierTour ? 3.2 : 4.0)) {
            angle = base + Double(tours) * 360 - Self.milieu(cible)
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(premierTour ? 3.6 : 4.3))
            withAnimation(.snappy(duration: 0.45)) {
                etape = premierTour ? .perdu : .gagne
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

#Preview("La roue") { RoueSheet() }
#Preview("Deuxième chance") { RoueSheet(etapeDepart: "perdu") }
#Preview("Le gain") { RoueSheet(etapeDepart: "gain") }

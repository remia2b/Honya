import SwiftUI
import SwiftData

/// Trois étapes, pas une de plus : ce que vous lisez, votre objectif, vos
/// langues.
///
/// C'est le premier écran de l'application, il donne le ton. D'où le fond en
/// auréoles qui dérivent — de la profondeur sans rien à déchiffrer derrière le
/// texte — et les choix présentés comme dans les Réglages : une colonne, des
/// séparateurs fins, un cercle qui se remplit. Chaque étape a sa teinte :
/// l'ambre accueille, le vert des lectures faites dit que ça avance.
struct OnboardingView: View {
    /// Ouvre directement une étape, pour les captures.
    var etapeDepart = 0

    @Environment(\.modelContext) private var contexte
    @AppStorage("onboardingTermine") private var onboardingTermine = false

    @State private var etape = 0
    @State private var typesChoisis: Set<TypeOeuvre> = [.livre, .manga]
    @State private var minutesChoisies = 20
    @State private var dureeLibre = false
    @State private var languesChoisies: Set<String> = [Langues.codeAppareil]

    /// Les durées proposées d'emblée. Au-delà, le réglage libre prend le
    /// relais : dix minutes suffisent à certains, une heure à d'autres, et une
    /// liste figée finit toujours par exclure quelqu'un.
    private let dureesProposees = [10, 15, 20, 30, 45]

    private static let pasLibre = 5
    private static let minimumLibre = 5
    private static let maximumLibre = 240

    /// La teinte de l'étape. Le vert est celui des lectures terminées : la
    /// couleur que le lecteur reverra chaque fois qu'il tiendra sa série.
    private var teinte: Color {
        etape == 1 ? Couleurs.lu : Couleurs.accent
    }

    var body: some View {
        ZStack {
            FondAccueil(teinte: teinte)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.5), value: etape)

            VStack(spacing: 0) {
                indicateurEtapes
                    .padding(.top, 18)

                TabView(selection: $etape) {
                    etapeTypes.tag(0)
                    etapeObjectif.tag(1)
                    etapeLangues.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.snappy, value: etape)
            }
        }
        .safeAreaInset(edge: .bottom) { basDePage }
        .onAppear {
            if etapeDepart != 0 {
                etape = etapeDepart
                // L'étape de l'objectif se montre avec le réglage libre
                // ouvert : c'est la nouveauté à juger.
                if etapeDepart == 1 { dureeLibre = true; minutesChoisies = 25 }
            }
        }
    }

    private var indicateurEtapes: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(index <= etape ? AnyShapeStyle(teinte)
                                         : AnyShapeStyle(Color.primary.opacity(0.16)))
                    .frame(width: index == etape ? 22 : 7, height: 7)
            }
        }
        .animation(.snappy, value: etape)
    }

    // MARK: - L'en-tête commun

    private func enTete(
        rang: Int, titre: LocalizedStringKey, texte: LocalizedStringKey
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Capsule()
                    .fill(teinte)
                    .frame(width: 18, height: 2)
                Text("Étape \(rang) sur 3")
                    .font(.system(size: 11, weight: .bold))
                    .kerning(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(teinte)
            }
            .padding(.bottom, 12)

            Text(titre)
                .font(.titreEcran)
                .fixedSize(horizontal: false, vertical: true)

            Text(texte)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
        .padding(.top, 26)
        .padding(.bottom, 22)
    }

    // MARK: - Étape 1 : ce que vous lisez

    private var etapeTypes: some View {
        VStack(spacing: 0) {
            enTete(
                rang: 1,
                titre: "Bienvenue dans Honya",
                texte: "Votre bibliothèque, vivante.\nQue lisez-vous ?"
            )

            BlocChoix {
                ForEach(Array(TypeOeuvre.allCases.enumerated()), id: \.element) { rang, type in
                    if rang > 0 { SeparateurChoix() }
                    LigneChoix(
                        libelle: type.libelle,
                        choisi: typesChoisis.contains(type),
                        teinte: teinte
                    ) {
                        withAnimation(.snappy(duration: 0.2)) {
                            if typesChoisis.contains(type) {
                                typesChoisis.remove(type)
                            } else {
                                typesChoisis.insert(type)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 22)

            Spacer(minLength: 0)
        }
    }

    // MARK: - Étape 2 : l'objectif quotidien

    private var etapeObjectif: some View {
        VStack(spacing: 0) {
            enTete(
                rang: 2,
                titre: "Un petit objectif\nchaque jour",
                texte: "Quelques minutes par jour suffisent à construire une série."
            )

            VStack(spacing: 12) {
                BlocChoix {
                    ForEach(Array(dureesProposees.enumerated()), id: \.element) { rang, minutes in
                        if rang > 0 { SeparateurChoix() }
                        LigneChoix(
                            libelle: String(localized: "\(minutes) min"),
                            choisi: !dureeLibre && minutesChoisies == minutes,
                            teinte: teinte
                        ) {
                            withAnimation(.snappy(duration: 0.2)) {
                                dureeLibre = false
                                minutesChoisies = minutes
                            }
                        }
                    }

                    SeparateurChoix()

                    LigneChoix(
                        libelle: String(localized: "Autre durée"),
                        choisi: dureeLibre,
                        teinte: teinte
                    ) {
                        withAnimation(.snappy(duration: 0.25)) {
                            dureeLibre = true
                            // On repart de la valeur courante, arrondie au pas :
                            // le réglage libre continue le choix, il ne le
                            // recommence pas.
                            minutesChoisies = arrondi(minutesChoisies)
                        }
                    }
                }

                if dureeLibre { reglageLibre }
            }
            .padding(.horizontal, 22)

            Text("Modifiable à tout moment dans les réglages. Un joker par semaine protège votre série.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 22)
                .padding(.top, 14)

            Spacer(minLength: 0)
        }
    }

    /// Le réglage au pas de cinq minutes, déplié sous la liste.
    private var reglageLibre: some View {
        HStack(spacing: 0) {
            boutonPas("minus", actif: minutesChoisies > Self.minimumLibre) {
                minutesChoisies = max(Self.minimumLibre, minutesChoisies - Self.pasLibre)
            }

            Spacer(minLength: 0)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(minutesChoisies)")
                    .font(.chiffreSerif(26))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("min")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            boutonPas("plus", actif: minutesChoisies < Self.maximumLibre) {
                minutesChoisies = min(Self.maximumLibre, minutesChoisies + Self.pasLibre)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(teinte.opacity(0.5), lineWidth: 1.5)
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func boutonPas(
        _ symbole: String, actif: Bool, action: @escaping () -> Void
    ) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.22)) { action() }
        } label: {
            Image(systemName: symbole)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.primary)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(!actif)
        .opacity(actif ? 1 : 0.35)
    }

    private func arrondi(_ minutes: Int) -> Int {
        let cran = (minutes / Self.pasLibre) * Self.pasLibre
        return min(Self.maximumLibre, max(Self.minimumLibre, cran))
    }

    // MARK: - Étape 3 : les langues de lecture

    private var etapeLangues: some View {
        VStack(spacing: 0) {
            enTete(
                rang: 3,
                titre: "Vos langues\nde lecture",
                texte: "La recherche privilégie les éditions dans vos langues, et les titres s'affichent tels qu'ils sont officiellement publiés."
            )

            ScrollView {
                BlocChoix {
                    ForEach(Array(Langues.toutes.enumerated()), id: \.element.id) { rang, langue in
                        if rang > 0 { SeparateurChoix() }
                        LigneChoix(
                            libelle: langue.nomNatif,
                            choisi: languesChoisies.contains(langue.code),
                            teinte: teinte
                        ) {
                            withAnimation(.snappy(duration: 0.18)) {
                                if languesChoisies.contains(langue.code) {
                                    // Jamais zéro langue : la recherche n'aurait
                                    // plus de sol.
                                    if languesChoisies.count > 1 {
                                        languesChoisies.remove(langue.code)
                                    }
                                } else {
                                    languesChoisies.insert(langue.code)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .mask(
                // La liste se fond sous le bouton au lieu d'être tranchée net.
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.9),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )
        }
    }

    // MARK: - Le bas

    private var basDePage: some View {
        BoutonAccueil(
            titre: etape < 2 ? "Continuer" : "Ouvrir ma bibliothèque",
            teinte: teinte,
            actif: etape != 0 || !typesChoisis.isEmpty
        ) {
            if etape < 2 {
                withAnimation(.snappy) { etape += 1 }
            } else {
                terminer()
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(
            // Un fondu vers le fond : la liste glisse dessous sans qu'une arête
            // sépare les deux.
            LinearGradient(
                colors: [
                    Color(uiColor: .systemBackground).opacity(0),
                    Color(uiColor: .systemBackground).opacity(0.9),
                    Color(uiColor: .systemBackground),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    // MARK: - Fin

    private func terminer() {
        let objectif = Objectif.courant(dans: contexte)
        objectif.minutesParJour = minutesChoisies
        objectif.typesPreferes = typesChoisis.map(\.rawValue)
        // La langue de l'appareil d'abord, si elle fait partie des choix.
        let appareil = Langues.codeAppareil
        var ordonnees = Array(languesChoisies)
        if let index = ordonnees.firstIndex(of: appareil), index != 0 {
            ordonnees.swapAt(0, index)
        }
        objectif.languesLecture = ordonnees
        onboardingTermine = true
    }
}

#Preview {
    OnboardingView()
        .modelContainer(Apercu.conteneur)
}

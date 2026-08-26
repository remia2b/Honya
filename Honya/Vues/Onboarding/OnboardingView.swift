import SwiftUI
import SwiftData

/// Trois étapes, pas une de plus : ce que vous lisez, votre objectif, vos langues.
///
/// L'écran est le tout premier de l'application : il donne le ton. D'où la
/// lueur chaude qui monte du fond plutôt qu'un aplat, les cartes plutôt que
/// des pastilles nues, et une mise en page qui tient la même place à chaque
/// étape — le titre ne saute pas d'une page à l'autre.
struct OnboardingView: View {
    @Environment(\.modelContext) private var contexte
    @Environment(\.colorScheme) private var apparence
    @AppStorage("onboardingTermine") private var onboardingTermine = false

    @State private var etape = 0
    @State private var typesChoisis: Set<TypeOeuvre> = [.livre, .manga]
    @State private var minutesChoisies = 20
    @State private var languesChoisies: Set<String> = [Langues.codeAppareil]
    @State private var apparu = false

    private let optionsMinutes = [10, 15, 20, 30, 45]

    private var sombre: Bool { apparence == .dark }

    var body: some View {
        ZStack {
            fond.ignoresSafeArea()

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
        .safeAreaInset(edge: .bottom) { bouton }
        .onAppear {
            withAnimation(.easeOut(duration: 0.55)) { apparu = true }
        }
    }

    /// Une lueur chaude qui monte du haut et s'éteint : la couleur de
    /// l'application, respirée plutôt qu'affichée. Elle se règle d'elle-même
    /// sur le thème du système, comme tout le reste de l'écran.
    private var fond: some View {
        ZStack {
            Color(uiColor: .systemBackground)

            RadialGradient(
                colors: [
                    Couleurs.accent.opacity(sombre ? 0.26 : 0.20),
                    Couleurs.accent.opacity(0),
                ],
                center: UnitPoint(x: 0.5, y: 0.02),
                startRadius: 8,
                endRadius: 520
            )

            // Un second voile, très bas, pour que le bas de l'écran ne soit
            // pas un mur plat sous les cartes.
            LinearGradient(
                colors: [
                    Couleurs.accent.opacity(0),
                    Couleurs.accent.opacity(sombre ? 0.09 : 0.07),
                ],
                startPoint: .center,
                endPoint: .bottom
            )
        }
    }

    private var indicateurEtapes: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(index <= etape ? AnyShapeStyle(Couleurs.accent)
                                         : AnyShapeStyle(Color.primary.opacity(0.16)))
                    .frame(width: index == etape ? 26 : 8, height: 8)
            }
        }
        .animation(.snappy, value: etape)
    }

    // MARK: - L'en-tête commun

    /// Le même bloc à chaque étape, à la même hauteur : rien ne saute quand
    /// on glisse d'une page à l'autre.
    private func enTete(
        symbole: String, titre: LocalizedStringKey, texte: LocalizedStringKey
    ) -> some View {
        VStack(spacing: 14) {
            Image(systemName: symbole)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Couleurs.accent)
                .frame(width: 68, height: 68)
                .background(
                    Circle().fill(Couleurs.accent.opacity(sombre ? 0.18 : 0.13))
                )
                .overlay(
                    Circle().strokeBorder(Couleurs.accent.opacity(0.25), lineWidth: 1)
                )
                .scaleEffect(apparu ? 1 : 0.8)
                .opacity(apparu ? 1 : 0)

            Text(titre)
                .font(.titreEcran)
                .multilineTextAlignment(.center)

            Text(texte)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 28)
        .padding(.top, 26)
        .frame(height: 236, alignment: .top)
    }

    /// La plaque sous les choix : une carte posée sur la lueur, pas un aplat.
    private func carte<Contenu: View>(@ViewBuilder _ contenu: () -> Contenu) -> some View {
        contenu()
            .padding(18)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground).opacity(sombre ? 0.7 : 0.85))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )
            .padding(.horizontal, 22)
    }

    // MARK: - Étape 1 : ce que vous lisez

    private var etapeTypes: some View {
        VStack(spacing: 0) {
            enTete(
                symbole: "books.vertical.fill",
                titre: "Bienvenue dans Honya",
                texte: "Votre bibliothèque, vivante.\nQue lisez-vous ?"
            )

            carte {
                HStack(spacing: 10) {
                    ForEach(TypeOeuvre.allCases) { type in
                        let actif = typesChoisis.contains(type)
                        Button {
                            withAnimation(.snappy(duration: 0.2)) {
                                if actif { typesChoisis.remove(type) } else { typesChoisis.insert(type) }
                            }
                        } label: {
                            VStack(spacing: 8) {
                                Image(systemName: symbole(type))
                                    .font(.system(size: 22, weight: .semibold))
                                Text(type.libelle)
                                    .font(.subheadline.weight(.bold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 88)
                            .background(
                                actif ? AnyShapeStyle(Couleurs.accent)
                                      : AnyShapeStyle(Color.primary.opacity(0.06)),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                            )
                            .foregroundStyle(actif ? Color.white : Color.primary)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(
                                        actif ? Color.clear : Color.primary.opacity(0.08),
                                        lineWidth: 1
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            // Centrée dans ce qui reste sous l'en-tête : collée en haut,
            // elle laissait la moitié basse de l'écran vide.
            .frame(maxHeight: .infinity)
        }
    }

    private func symbole(_ type: TypeOeuvre) -> String {
        switch type {
        case .livre: return "book.closed.fill"
        case .manga: return "books.vertical.fill"
        case .bd: return "rectangle.3.group.fill"
        }
    }

    // MARK: - Étape 2 : l'objectif quotidien

    private var etapeObjectif: some View {
        VStack(spacing: 0) {
            enTete(
                symbole: "flame.fill",
                titre: "Un petit objectif\nchaque jour",
                texte: "Comme dans Apple Books : quelques minutes par jour suffisent à construire une série."
            )

            carte {
                VStack(spacing: 14) {
                    HStack(spacing: 8) {
                        ForEach(optionsMinutes, id: \.self) { minutes in
                            let actif = minutesChoisies == minutes
                            Button {
                                withAnimation(.snappy(duration: 0.2)) { minutesChoisies = minutes }
                            } label: {
                                VStack(spacing: 0) {
                                    Text("\(minutes)")
                                        .font(.chiffreSerif(24))
                                        .monospacedDigit()
                                    Text("min")
                                        .font(.caption2.weight(.bold))
                                        .opacity(0.8)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 68)
                                .background(
                                    actif ? AnyShapeStyle(Couleurs.accent)
                                          : AnyShapeStyle(Color.primary.opacity(0.06)),
                                    in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                                )
                                .foregroundStyle(actif ? Color.white : Color.primary)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                                        .strokeBorder(
                                            actif ? Color.clear : Color.primary.opacity(0.08),
                                            lineWidth: 1
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Text("Modifiable à tout moment dans les réglages. Un joker par semaine protège votre série.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    // MARK: - Étape 3 : les langues de lecture

    private var etapeLangues: some View {
        VStack(spacing: 0) {
            enTete(
                symbole: "globe",
                titre: "Vos langues\nde lecture",
                texte: "La recherche privilégie les éditions dans vos langues, et les titres s'affichent tels qu'ils sont officiellement publiés."
            )

            // La liste prend tout ce qui reste et se fond sous le bouton :
            // enfermée dans une hauteur fixe, elle laissait un vide en bas
            // sur les grands écrans et débordait sur les petits.
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 10),
                              GridItem(.flexible(), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(Langues.toutes) { langue in
                        ligneLangue(langue)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .mask(
                // Le bas s'efface au lieu d'être tranché net par le bouton.
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.88),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )
        }
    }

    private func ligneLangue(_ langue: LangueLecture) -> some View {
        let actif = languesChoisies.contains(langue.code)
        return Button {
            withAnimation(.snappy(duration: 0.18)) {
                if actif {
                    // Jamais zéro langue : la recherche n'aurait plus de sol.
                    if languesChoisies.count > 1 { languesChoisies.remove(langue.code) }
                } else {
                    languesChoisies.insert(langue.code)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(langue.nomNatif)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if actif {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15, weight: .bold))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(
                actif ? AnyShapeStyle(Couleurs.accent.opacity(sombre ? 0.22 : 0.14))
                      : AnyShapeStyle(Color(uiColor: .secondarySystemBackground).opacity(sombre ? 0.7 : 0.85)),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        actif ? Couleurs.accent.opacity(0.55) : Color.primary.opacity(0.07),
                        lineWidth: actif ? 1.5 : 1
                    )
            )
            .foregroundStyle(actif ? AnyShapeStyle(Couleurs.accent) : AnyShapeStyle(Color.primary))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Le bas

    private var bouton: some View {
        Button {
            if etape < 2 {
                withAnimation(.snappy) { etape += 1 }
            } else {
                terminer()
            }
        } label: {
            Text(etape < 2 ? "Continuer" : "Ouvrir ma bibliothèque")
                .font(.system(size: 17, weight: .bold))
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .foregroundStyle(.white)
                .background(
                    LinearGradient(
                        colors: [Couleurs.accent, Couleurs.accent.opacity(0.86)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                )
                .shadow(color: Couleurs.accent.opacity(0.32), radius: 12, y: 5)
        }
        .buttonStyle(.plain)
        .disabled(etape == 0 && typesChoisis.isEmpty)
        .opacity(etape == 0 && typesChoisis.isEmpty ? 0.5 : 1)
        .padding(.horizontal, 22)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(
            // Un fondu vers le fond : la liste de langues glisse dessous
            // sans qu'une arête sépare les deux.
            LinearGradient(
                colors: [
                    Color(uiColor: .systemBackground).opacity(0),
                    Color(uiColor: .systemBackground).opacity(0.85),
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

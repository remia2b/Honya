import SwiftUI
import SwiftData

/// Trois étapes, pas une de plus : ce que vous lisez, votre objectif, vos langues.
struct OnboardingView: View {
    @Environment(\.modelContext) private var contexte
    @AppStorage("onboardingTermine") private var onboardingTermine = false

    @State private var etape = 0
    @State private var typesChoisis: Set<TypeOeuvre> = [.livre, .manga]
    @State private var minutesChoisies = 20
    @State private var languesChoisies: Set<String> = [Locale.current.language.languageCode?.identifier ?? "fr"]

    private let optionsMinutes = [10, 15, 20, 30, 45]
    private let langues: [(code: String, nom: String)] = [
        ("fr", "Français"), ("en", "English"), ("ja", "日本語"),
        ("es", "Español"), ("de", "Deutsch"), ("it", "Italiano"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            indicateurEtapes
                .padding(.top, 24)

            TabView(selection: $etape) {
                etapeTypes.tag(0)
                etapeObjectif.tag(1)
                etapeLangues.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.snappy, value: etape)

            Button {
                if etape < 2 {
                    etape += 1
                } else {
                    terminer()
                }
            } label: {
                Text(etape < 2 ? "Continuer" : "Ouvrir ma bibliothèque")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(Couleurs.accent)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
            .disabled(etape == 0 && typesChoisis.isEmpty)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var indicateurEtapes: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(index <= etape ? Couleurs.accent : Color(uiColor: .secondarySystemFill))
                    .frame(width: index == etape ? 22 : 8, height: 8)
            }
        }
        .animation(.snappy, value: etape)
    }

    // MARK: - Étape 1 : ce que vous lisez

    private var etapeTypes: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 44))
                .foregroundStyle(Couleurs.accent)
            Text("Bienvenue dans Honya")
                .font(.titreEcran)
            Text("Votre bibliothèque, vivante.\nQue lisez-vous ?")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 10) {
                ForEach(TypeOeuvre.allCases) { type in
                    let actif = typesChoisis.contains(type)
                    Button {
                        if actif { typesChoisis.remove(type) } else { typesChoisis.insert(type) }
                    } label: {
                        Text(type.libelle)
                            .font(.subheadline.weight(.bold))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 11)
                            .background(
                                actif ? AnyShapeStyle(Couleurs.accent) : AnyShapeStyle(Color(uiColor: .secondarySystemGroupedBackground)),
                                in: Capsule()
                            )
                            .foregroundStyle(actif ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 28)
    }

    // MARK: - Étape 2 : l'objectif quotidien

    private var etapeObjectif: some View {
        VStack(spacing: 18) {
            Spacer()
            Text("Un petit objectif\nchaque jour")
                .font(.titreEcran)
                .multilineTextAlignment(.center)
            Text("Comme dans Apple Books : quelques minutes par jour suffisent à construire une série.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                ForEach(optionsMinutes, id: \.self) { minutes in
                    let actif = minutesChoisies == minutes
                    Button {
                        minutesChoisies = minutes
                    } label: {
                        VStack(spacing: 0) {
                            Text("\(minutes)")
                                .font(.chiffreSerif(24))
                                .monospacedDigit()
                            Text("min")
                                .font(.caption2.weight(.bold))
                        }
                        .frame(width: 58, height: 62)
                        .background(
                            actif ? AnyShapeStyle(Couleurs.accent) : AnyShapeStyle(Color(uiColor: .secondarySystemGroupedBackground)),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                        .foregroundStyle(actif ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("Modifiable à tout moment dans les réglages. Un joker par semaine protège votre série.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 28)
    }

    // MARK: - Étape 3 : les langues de lecture

    private var etapeLangues: some View {
        VStack(spacing: 18) {
            Spacer()
            Text("Vos langues\nde lecture")
                .font(.titreEcran)
                .multilineTextAlignment(.center)
            Text("La recherche privilégie les éditions dans vos langues, et les titres s'affichent tels qu'ils sont officiellement publiés.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(langues, id: \.code) { langue in
                    let actif = languesChoisies.contains(langue.code)
                    Button {
                        if actif {
                            if languesChoisies.count > 1 { languesChoisies.remove(langue.code) }
                        } else {
                            languesChoisies.insert(langue.code)
                        }
                    } label: {
                        HStack {
                            Text(langue.nom)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            if actif {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.black))
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(
                            actif ? AnyShapeStyle(Couleurs.accent.opacity(0.15)) : AnyShapeStyle(Color(uiColor: .secondarySystemGroupedBackground)),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .foregroundStyle(actif ? Couleurs.accent : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 28)
    }

    // MARK: - Fin

    private func terminer() {
        let objectif = Objectif.courant(dans: contexte)
        objectif.minutesParJour = minutesChoisies
        objectif.typesPreferes = typesChoisis.map(\.rawValue)
        // La langue de l'appareil d'abord, si elle fait partie des choix.
        let appareil = Locale.current.language.languageCode?.identifier ?? "fr"
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

import SwiftUI
import SwiftData

// MARK: - Cible d'une session (un livre ou une série)

enum CibleSession: Identifiable, Hashable {
    case oeuvre(Oeuvre)
    case serie(Serie)

    var id: PersistentIdentifier {
        switch self {
        case .oeuvre(let oeuvre): return oeuvre.persistentModelID
        case .serie(let serie): return serie.persistentModelID
        }
    }

    func titre(_ langue: String) -> String {
        switch self {
        case .oeuvre(let oeuvre): return oeuvre.titre(langue)
        case .serie(let serie): return serie.nomAffiche(langue)
        }
    }

    var couvertureURL: String? {
        switch self {
        case .oeuvre(let oeuvre): return oeuvre.couvertureAffichee
        case .serie(let serie): return serie.couvertureAffichee
        }
    }
}

// MARK: - Minuteur robuste (basé sur des dates : survit aux passages en arrière-plan)

@Observable
final class MinuteurSession {
    let debut = Date()
    private var reprise = Date()
    private var accumule: TimeInterval = 0
    var enPause = false

    var ecoule: TimeInterval {
        enPause ? accumule : accumule + Date().timeIntervalSince(reprise)
    }

    func basculerPause() {
        if enPause {
            reprise = Date()
            enPause = false
        } else {
            accumule += Date().timeIntervalSince(reprise)
            enPause = true
        }
    }

    func arreter() -> Int {
        if !enPause {
            accumule += Date().timeIntervalSince(reprise)
            enPause = true
        }
        return Int(accumule)
    }
}

// MARK: - Le mode « lampe de chevet »
// On pose le téléphone, on ouvre le vrai livre. Couverture floutée,
// chiffres serif géants, rien d'autre.

struct SessionLectureView: View {
    let cible: CibleSession

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var contexte
    @Query private var objectifs: [Objectif]
    @Query private var sessions: [SessionLecture]

    @State private var minuteur = MinuteurSession()
    @State private var finVisible = false
    @State private var confirmerAbandon = false
    @State private var couverture: UIImage?

    private var langue: String { objectifs.first?.languePrincipale ?? Langues.codeAppareil }
    private var objectifMinutes: Int { objectifs.first?.minutesParJour ?? 20 }

    var body: some View {
        ZStack {
            fondAmbiant

            VStack(spacing: 0) {
                HStack {
                    Button {
                        if minuteur.ecoule > 120 { confirmerAbandon = true } else { dismiss() }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.bold))
                            .padding(10)
                            .background(.white.opacity(0.12), in: Circle())
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Spacer()

                Text(cible.titre(langue).uppercased())
                    .font(.caption.weight(.heavy))
                    .kerning(1.5)
                    .opacity(0.65)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)

                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(formater(Int(minuteur.ecoule)))
                        .font(.chiffreSerif(66))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .padding(.top, 6)

                indicationObjectif
                    .padding(.top, 2)

                Button(action: { minuteur.basculerPause() }) {
                    Image(systemName: minuteur.enPause ? "play.fill" : "pause.fill")
                        .font(.title2)
                        .frame(width: 64, height: 64)
                        .background(.white.opacity(0.13), in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.22), lineWidth: 1))
                }
                .padding(.top, 30)
                .accessibilityLabel(minuteur.enPause ? "Reprendre" : "Pause")

                Button {
                    if !minuteur.enPause { minuteur.basculerPause() }
                    finVisible = true
                } label: {
                    Text("Terminer la session")
                        .font(.footnote.weight(.bold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(.white.opacity(0.1), in: Capsule())
                        .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1))
                }
                .padding(.top, 18)

                Spacer()

                Text("L'écran reste allumé pendant la session.")
                    .font(.caption2)
                    .opacity(0.45)
                    .padding(.bottom, 18)
            }
            .foregroundStyle(Color(white: 0.96))
        }
        .statusBarHidden()
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .task {
            couverture = await ImageCharge.partage.uiImage(depuis: cible.couvertureURL)
        }
        .confirmationDialog(
            "Abandonner cette session ?",
            isPresented: $confirmerAbandon,
            titleVisibility: .visible
        ) {
            Button("Abandonner sans enregistrer", role: .destructive) { dismiss() }
            Button("Continuer à lire", role: .cancel) {}
        }
        .sheet(isPresented: $finVisible) {
            FinSessionSheet(
                cible: cible,
                secondes: minuteur.arreter(),
                debut: minuteur.debut
            ) {
                dismiss()
            }
            .interactiveDismissDisabled()
        }
    }

    // MARK: - Fond ambiant : la couverture du livre, floutée et assombrie

    private var fondAmbiant: some View {
        ZStack {
            Color(red: 0.07, green: 0.06, blue: 0.05)
            if let couverture {
                Image(uiImage: couverture)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 70)
                    .opacity(0.55)
                    .saturation(1.2)
            } else {
                Circle()
                    .fill(Couleurs.accent.opacity(0.35))
                    .frame(width: 300, height: 300)
                    .blur(radius: 90)
                    .offset(x: -80, y: -220)
            }
            Color.black.opacity(0.35)
        }
        .ignoresSafeArea()
    }

    private var indicationObjectif: some View {
        let dejaFait = StatsEngine.minutesAujourdhui(sessions)
        let enCours = Int(minuteur.ecoule) / 60
        let restantes = objectifMinutes - dejaFait - enCours
        return Group {
            if restantes > 0 {
                Text("objectif du jour atteint dans \(restantes) min")
            } else {
                Text("objectif du jour atteint ✦")
                    .foregroundStyle(Couleurs.accent)
            }
        }
        .font(.caption.weight(.semibold))
        .opacity(0.85)
        .monospacedDigit()
    }

    private func formater(_ secondes: Int) -> String {
        let heures = secondes / 3600
        let minutes = (secondes % 3600) / 60
        let reste = secondes % 60
        if heures > 0 {
            return String(format: "%d:%02d:%02d", heures, minutes, reste)
        }
        return String(format: "%02d:%02d", minutes, reste)
    }
}

// MARK: - Fin de session : « Belle session ! » → page atteinte, mood, enregistrement

private struct FinSessionSheet: View {
    let cible: CibleSession
    let secondes: Int
    let debut: Date
    var surEnregistre: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var contexte

    @State private var page: Double = 0
    @State private var chapitres: Int = 0
    @State private var pagesManga: Int = 0
    @State private var mood: String?
    @State private var termine = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 4) {
                        Text("Belle session !")
                            .font(.titreOeuvre(24))
                        Text("\(max(1, secondes / 60)) minutes de lecture")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .padding(.top, 10)

                    switch cible {
                    case .oeuvre(let oeuvre):
                        sectionPageLivre(oeuvre)
                    case .serie:
                        sectionSerie
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        EtiquetteCarte("L'humeur de cette session (optionnel)")
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 6)], spacing: 6) {
                            ForEach(Moods.tous, id: \.self) { humeur in
                                let actif = mood == humeur
                                Button {
                                    mood = actif ? nil : humeur
                                } label: {
                                    Text(humeur)
                                        .font(.caption.weight(.bold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 6)
                                        .background(
                                            actif ? AnyShapeStyle(Couleurs.accent) : AnyShapeStyle(Color(uiColor: .secondarySystemFill)),
                                            in: Capsule()
                                        )
                                        .foregroundStyle(actif ? .white : .primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(20)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer", action: enregistrer)
                        .fontWeight(.bold)
                        .disabled(secondes <= 0)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Ignorer") {
                        dismiss()
                        surEnregistre()
                    }
                }
            }
        }
        .presentationDetents([.large])
        .onAppear {
            if case .oeuvre(let oeuvre) = cible {
                page = Double(oeuvre.exemplaire?.pageCourante ?? 0)
            }
            if case .serie(let serie) = cible {
                chapitres = serie.chapitresLus
            }
        }
    }

    // MARK: Sections spécifiques

    @ViewBuilder
    private func sectionPageLivre(_ oeuvre: Oeuvre) -> some View {
        let maxPages = Double(oeuvre.pages ?? 2000)
        VStack(spacing: 10) {
            EtiquetteCarte("Où en es-tu ?")
            Text("p. \(Int(page)) sur \(Int(maxPages))")
                .font(.chiffreSerif(28))
                .monospacedDigit()
            Slider(value: $page, in: 0...maxPages, step: 1)
                .tint(Couleurs.accent)
            Toggle(isOn: $termine) {
                Text("J'ai terminé ce livre")
                    .font(.subheadline.weight(.semibold))
            }
            .tint(Couleurs.lu)
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var sectionSerie: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Lu jusqu'au chapitre \(chapitres)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Spacer()
                Stepper("Chapitres", value: $chapitres, in: 0...9999)
                    .labelsHidden()
            }
            HStack {
                Text("Pages lues : \(pagesManga)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Spacer()
                Stepper("Pages", value: $pagesManga, in: 0...2000, step: 10)
                    .labelsHidden()
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: Enregistrement

    private func enregistrer() {
        guard secondes > 0 else { return }
        let session = SessionLecture(debut: debut, dureeSecondes: secondes)
        session.mood = mood

        switch cible {
        case .oeuvre(let oeuvre):
            let avant = oeuvre.exemplaire?.pageCourante ?? 0
            session.pagesLues = max(0, Int(page) - avant)
            session.oeuvre = oeuvre
            oeuvre.exemplaire?.pageCourante = Int(page)
            if oeuvre.exemplaire?.statut != .lu {
                oeuvre.exemplaire?.changerStatut(.enCours)
            }
            if termine {
                oeuvre.exemplaire?.changerStatut(.lu)
            }
        case .serie(let serie):
            session.pagesLues = pagesManga
            session.serie = serie
            serie.chapitresLus = max(serie.chapitresLus, chapitres)
            // Démarrer une session reprend réellement la série : même sans
            // chapitre renseigné (une session peut ne compter que des pages),
            // elle doit apparaître dans « En cours ». Une série dont tous les
            // tomes publiés sont déjà lus conserve néanmoins son état terminé.
            // `nil` laisse une série terminée se recalculer : si un tome déjà
            // annoncé paraît demain, elle quittera automatiquement « Lu ».
            serie.statutChoisi = serie.estTerminee ? nil : .enCours
        }

        contexte.insert(session)
        BadgesEngine.evaluer(dans: contexte)
        dismiss()
        surEnregistre()
    }
}

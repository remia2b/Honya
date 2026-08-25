import SwiftUI
import SwiftData

/// L'accueil, dessiné comme celui d'Apple Books : de grandes couvertures qui
/// portent l'écran, des titres de section en serif, des bandes de fond qui
/// séparent les rubriques — et surtout aucune carte arrondie qui enferme tout.
struct AccueilView: View {
    var allerRecherche: () -> Void

    @Environment(\.modelContext) private var contexte
    @Query(sort: \SessionLecture.debut, order: .reverse) private var sessions: [SessionLecture]
    @Query private var exemplaires: [Exemplaire]
    @Query private var series: [Serie]
    @Query private var objectifs: [Objectif]

    @State private var reglagesVisibles = false
    @State private var cibleSession: CibleSession?
    @State private var choixVisible = false

    private var objectifMinutes: Int { objectifs.first?.minutesParJour ?? 20 }
    private var langue: String { objectifs.first?.languePrincipale ?? Langues.codeAppareil }
    private var minutesDuJour: Int { StatsEngine.minutesAujourdhui(sessions) }

    /// Le livre en cours dont la dernière session est la plus récente.
    private var enCeMoment: Exemplaire? {
        exemplaires
            .filter { $0.statut == .enCours }
            .sorted { derniereActivite($0) > derniereActivite($1) }
            .first
    }

    /// La série la plus récemment lue, quand aucun livre n'est en cours.
    private var serieEnCours: Serie? {
        series
            .filter { $0.statut == .enCours || $0.prochainALire != nil }
            .sorted { ($0.derniereLecture ?? $0.dateAjout) > ($1.derniereLecture ?? $1.dateAjout) }
            .first
    }

    private var aSuivre: [Exemplaire] {
        exemplaires.filter { $0.aSuivre && $0.statut != .lu }
    }

    private var ajoutsRecents: [ElementBibli] {
        let livres = exemplaires.compactMap { ex -> (Date, ElementBibli)? in
            guard let oeuvre = ex.oeuvre else { return nil }
            return (oeuvre.dateAjout, .livre(ex))
        }
        let sfx = series.map { ($0.dateAjout, ElementBibli.serie($0)) }
        return (livres + sfx).sorted { $0.0 > $1.0 }.prefix(8).map(\.1)
    }

    private var sortiesAVenir: [Serie] {
        series
            .filter { ($0.prochaineSortieDate ?? .distantPast) >= Calendar.current.startOfDay(for: .now) }
            .sorted { ($0.prochaineSortieDate ?? .distantFuture) < ($1.prochaineSortieDate ?? .distantFuture) }
    }

    private var bibliothequeVide: Bool { exemplaires.isEmpty && series.isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    entete

                    if bibliothequeVide {
                        etatVide
                    } else {
                        if let courant = enCeMoment, let oeuvre = courant.oeuvre {
                            bandeEnCours(exemplaire: courant, oeuvre: oeuvre)
                        } else if let serie = serieEnCours {
                            bandeSerieEnCours(serie)
                        }

                        if !ajoutsRecents.isEmpty {
                            BandeSection {
                                TitreSection(titre: "Récemment ajoutés")
                                    .padding(.horizontal, 20)
                                rangeeCouvertures(ajoutsRecents)
                            }
                        }

                        bandeObjectif

                        BandeauPlus()
                            .padding(.horizontal, 20)
                            .padding(.top, 6)

                        if !aSuivre.isEmpty {
                            BandeSection {
                                TitreSection(
                                    titre: "À suivre",
                                    sousTitre: "Les livres que vous comptez ouvrir bientôt."
                                )
                                .padding(.horizontal, 20)
                                rangeeCouvertures(aSuivre.map(ElementBibli.livre))
                            }
                        }

                        if !sortiesAVenir.isEmpty {
                            BandeSection(teintee: true) {
                                TitreSection(
                                    titre: "Sorties à venir",
                                    sousTitre: "Les prochains tomes de vos séries."
                                )
                                .padding(.horizontal, 20)
                                sectionSorties
                            }
                        }
                    }
                }
                .padding(.bottom, 30)
            }
            .background(Color(uiColor: .systemBackground))
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $reglagesVisibles) { ReglagesView() }
            .fullScreenCover(item: $cibleSession) { SessionLectureView(cible: $0) }
            .sheet(isPresented: $choixVisible) {
                ChoixLectureSheet { cible in
                    // Un court délai : la feuille doit finir de se refermer
                    // avant que le chronomètre ne prenne l'écran entier.
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(350))
                        cibleSession = cible
                    }
                }
            }
        }
    }

    // MARK: - En-tête : titre, anneau de progression, réglages

    private var entete: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 1) {
                Text(dateDuJour)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                    .kerning(0.5)
                Text("Aujourd'hui")
                    .font(.system(size: 33, weight: .semibold, design: .serif))
            }
            Spacer()
            HStack(spacing: 12) {
                anneauProgression
                Button { reglagesVisibles = true } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Réglages")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    /// L'anneau du jour : un tap lance directement le chronomètre de lecture.
    private var anneauProgression: some View {
        let fraction = objectifMinutes > 0
            ? min(1, Double(minutesDuJour) / Double(objectifMinutes)) : 0
        return Button {
            // On demande QUOI plutôt que de partir sur le dernier livre : une
            // session lancée sur le mauvais titre ne se rattrape pas.
            choixVisible = true
        } label: {
            ZStack {
                Circle()
                    .fill(Color(uiColor: .secondarySystemFill).opacity(0.55))
                Circle()
                    .stroke(Color(uiColor: .secondarySystemFill), lineWidth: 3.5)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(
                        AngularGradient(
                            colors: [Couleurs.accent.opacity(0.55), Couleurs.accent],
                            center: .center,
                            startAngle: .degrees(0),
                            endAngle: .degrees(360 * max(fraction, 0.01))
                        ),
                        style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                if minutesDuJour > 0 {
                    Text("\(minutesDuJour)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                } else {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Couleurs.accent)
                }
            }
            .frame(width: 38, height: 38)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(minutesDuJour) minutes lues aujourd'hui — lancer une session")
    }

    // MARK: - En ce moment : la grande couverture qui ouvre l'écran

    private func bandeEnCours(exemplaire: Exemplaire, oeuvre: Oeuvre) -> some View {
        BandeSection(teintee: true) {
            NavigationLink {
                FicheOeuvreView(oeuvre: oeuvre)
            } label: {
                HStack(alignment: .top, spacing: 18) {
                    GrandeCouverture(
                        urlString: oeuvre.couvertureAffichee,
                        titre: oeuvre.titre(langue),
                        auteur: oeuvre.auteurPrincipal,
                        largeur: 118,
                        manga: oeuvre.type != .livre
                    )
                    infosEnCours(
                        titre: oeuvre.titre(langue),
                        detail: oeuvre.auteurPrincipal,
                        progression: exemplaire.progression,
                        legende: oeuvre.pages.map {
                            "p. \(exemplaire.pageCourante) sur \($0)"
                        } ?? "En cours"
                    )
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
            }
            .buttonStyle(.plain)

            PiluleCTA(titre: "Continuer la lecture", sousTitre: oeuvre.titre(langue)) {
                cibleSession = .oeuvre(oeuvre)
            }
            .padding(.horizontal, 20)
        }
    }

    private func bandeSerieEnCours(_ serie: Serie) -> some View {
        BandeSection(teintee: true) {
            NavigationLink {
                FicheSerieView(serie: serie)
            } label: {
                HStack(alignment: .top, spacing: 18) {
                    GrandeCouverture(
                        urlString: serie.couvertureAffichee,
                        titre: serie.nomAffiche(langue),
                        auteur: serie.auteur,
                        largeur: 118,
                        manga: serie.type != .livre
                    )
                    infosEnCours(
                        titre: serie.nomAffiche(langue),
                        detail: serie.prochainALire.map { "À lire : tome \($0.numero)" }
                            ?? serie.prochainAAcheter.map { "À acheter : tome \($0)" }
                            ?? serie.auteur ?? "",
                        progression: serie.tomes.isEmpty
                            ? 0 : Double(serie.nbLus) / Double(serie.tomes.count),
                        legende: "\(serie.nbLus) lus sur \(serie.tomes.count) tomes",
                        teinte: Couleurs.lu
                    )
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
            }
            .buttonStyle(.plain)

            PiluleCTA(titre: "Continuer la lecture", sousTitre: serie.nomAffiche(langue)) {
                cibleSession = .serie(serie)
            }
            .padding(.horizontal, 20)
        }
    }

    private func infosEnCours(
        titre: String,
        detail: String,
        progression: Double,
        legende: String,
        teinte: Color = Couleurs.accent
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("En ce moment")
                .font(.caption2.weight(.heavy))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .kerning(0.6)
            Text(titre)
                .font(.system(size: 21, weight: .semibold, design: .serif))
                .lineLimit(3)
                .foregroundStyle(.primary)
            if !detail.isEmpty {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(teinte == Couleurs.lu ? Couleurs.accent : .secondary)
            }
            Spacer(minLength: 4)
            BarreProgression(valeur: progression, teinte: teinte)
            Text(legende)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(height: 177, alignment: .top)
    }

    // MARK: - Objectif de lecture, en grand

    private var bandeObjectif: some View {
        BandeSection {
            VStack(spacing: 14) {
                VStack(spacing: 5) {
                    Text("Objectif de lecture")
                        .font(.system(size: 25, weight: .semibold, design: .serif))
                    Text("Lisez chaque jour : la série grandit et les statistiques suivent.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                ArcObjectifView(minutes: minutesDuJour, objectif: objectifMinutes)
                    .frame(maxWidth: 320)

                Button { reglagesVisibles = true } label: {
                    HStack(spacing: 3) {
                        Text("Ajuster l'objectif")
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Couleurs.accent)
                }

                if enCeMoment == nil && serieEnCours == nil {
                    PiluleCTA(titre: "Commencer une lecture") { allerRecherche() }
                        .frame(maxWidth: 300)
                }

                SemaineSerieView(joursActifs: StatsEngine.joursActifs(sessions))
                    .padding(.top, 2)

                legendeSerie
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
        }
    }

    private var legendeSerie: some View {
        let serie = StatsEngine.serieDeJours(sessions)
        let record = StatsEngine.serieMax(sessions)
        return VStack(spacing: 2) {
            HStack(spacing: 4) {
                Text("Votre série de lecture est de")
                Text("\(serie) \(serie > 1 ? "jours" : "jour")")
                    .fontWeight(.bold)
                    .monospacedDigit()
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if serie >= 2 && serie >= record {
                Text("Nouveau record")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Couleurs.accent)
            }
        }
    }

    // MARK: - Rangées de grandes couvertures

    private func rangeeCouvertures(_ elements: [ElementBibli]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(elements) { element in
                    switch element {
                    case .livre(let exemplaire):
                        if let oeuvre = exemplaire.oeuvre {
                            NavigationLink {
                                FicheOeuvreView(oeuvre: oeuvre)
                            } label: {
                                GrandeCouverture(
                                    urlString: oeuvre.couvertureAffichee,
                                    titre: oeuvre.titre(langue),
                                    auteur: oeuvre.auteurPrincipal,
                                    manga: oeuvre.type != .livre
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    case .serie(let serie):
                        NavigationLink {
                            FicheSerieView(serie: serie)
                        } label: {
                            GrandeCouverture(
                                urlString: serie.couvertureAffichee,
                                titre: serie.nomAffiche(langue),
                                auteur: serie.auteur,
                                manga: serie.type != .livre
                            )
                            .overlay(alignment: .topTrailing) {
                                Text("\(serie.nbPossedes)/\(serie.tomes.count)")
                                    .font(.system(size: 10, weight: .heavy))
                                    .monospacedDigit()
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.black.opacity(0.7), in: Capsule())
                                    .padding(7)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Sorties à venir

    private var sectionSorties: some View {
        VStack(spacing: 10) {
            ForEach(sortiesAVenir.prefix(3)) { serie in
                NavigationLink {
                    FicheSerieView(serie: serie)
                } label: {
                    HStack(spacing: 14) {
                        CouvertureView(
                            urlString: serie.couvertureAffichee,
                            titre: serie.nomAffiche(langue),
                            coins: 5,
                            manga: serie.type != .livre
                        )
                        .frame(width: 44)
                        .shadow(color: .black.opacity(0.3), radius: 6, y: 3)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(serie.nomAffiche(langue))
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .foregroundStyle(.primary)
                            HStack(spacing: 4) {
                                if let numero = serie.prochaineSortieNumero {
                                    Text("Tome \(numero) —")
                                }
                                if let date = serie.prochaineSortieDate {
                                    Text(date, format: .dateTime.day().month(.wide))
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(Couleurs.accent)
                        }
                        Spacer()
                        Image(systemName: serie.rappelActive ? "bell.fill" : "chevron.right")
                            .font(.caption)
                            .foregroundStyle(serie.rappelActive ? Couleurs.accent : .secondary)
                    }
                    .padding(.horizontal, 20)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Bibliothèque vide

    private var etatVide: some View {
        ContentUnavailableView {
            Label("Votre bibliothèque est vide", systemImage: "books.vertical")
        } description: {
            Text("Scannez un ISBN ou cherchez un titre pour poser votre premier livre sur l'étagère.")
        } actions: {
            Button("Ajouter un livre", action: allerRecherche)
                .buttonStyle(.borderedProminent)
                .tint(Couleurs.accent)
        }
        .padding(.top, 70)
    }

    // MARK: - Aides

    private var dateDuJour: String {
        Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    private func derniereActivite(_ exemplaire: Exemplaire) -> Date {
        exemplaire.oeuvre?.sessions.map(\.debut).max()
            ?? exemplaire.dateDebut
            ?? .distantPast
    }
}

#Preview {
    AccueilView(allerRecherche: {})
        .modelContainer(Apercu.conteneur)
}

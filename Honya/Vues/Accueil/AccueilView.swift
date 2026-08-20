import SwiftUI
import SwiftData

/// L'écran Reading Goals d'Apple Books, promu en page d'accueil.
/// Une seule question : où en suis-je, et je reprends quoi ?
struct AccueilView: View {
    var allerRecherche: () -> Void

    @Environment(\.modelContext) private var contexte
    @Query(sort: \SessionLecture.debut, order: .reverse) private var sessions: [SessionLecture]
    @Query private var exemplaires: [Exemplaire]
    @Query private var series: [Serie]
    @Query private var objectifs: [Objectif]

    @State private var reglagesVisibles = false
    @State private var cibleSession: CibleSession?

    private var objectifMinutes: Int { objectifs.first?.minutesParJour ?? 20 }
    private var langue: String { objectifs.first?.languePrincipale ?? Langues.codeAppareil }

    /// L'exemplaire « en ce moment » : en cours, dernière session la plus récente.
    private var enCeMoment: Exemplaire? {
        exemplaires
            .filter { $0.statut == .enCours }
            .sorted { derniereActivite($0) > derniereActivite($1) }
            .first
    }

    private var aSuivre: [Exemplaire] {
        exemplaires.filter { $0.aSuivre && $0.statut != .lu }
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
                VStack(alignment: .leading, spacing: 20) {
                    EnteteEcran(titre: "Aujourd'hui", sousTitre: dateDuJour) {
                        Button {
                            reglagesVisibles = true
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("Réglages")
                    }

                    if bibliothequeVide {
                        ContentUnavailableView {
                            Label("Votre bibliothèque est vide", systemImage: "books.vertical")
                        } description: {
                            Text("Scannez un ISBN ou cherchez un titre pour poser votre premier livre sur l'étagère.")
                        } actions: {
                            Button("Ajouter un livre", action: allerRecherche)
                                .buttonStyle(.borderedProminent)
                                .tint(Couleurs.accent)
                        }
                        .padding(.top, 60)
                    } else {
                        if let courant = enCeMoment, let oeuvre = courant.oeuvre {
                            carteEnCours(courant, oeuvre: oeuvre)
                                .padding(.horizontal, 20)
                        }

                        carteObjectif
                            .padding(.horizontal, 20)

                        if !aSuivre.isEmpty {
                            sectionASuivre
                        }

                        if !sortiesAVenir.isEmpty {
                            sectionSorties
                                .padding(.horizontal, 20)
                        }
                    }
                }
                .padding(.bottom, 24)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $reglagesVisibles) { ReglagesView() }
            .fullScreenCover(item: $cibleSession) { cible in
                SessionLectureView(cible: cible)
            }
        }
    }

    // MARK: - Carte « En ce moment »

    private func carteEnCours(_ exemplaire: Exemplaire, oeuvre: Oeuvre) -> some View {
        NavigationLink {
            FicheOeuvreView(oeuvre: oeuvre)
        } label: {
            HStack(spacing: 14) {
                CouvertureView(
                    urlString: oeuvre.couvertureCanoniqueURL,
                    titre: oeuvre.titre(langue),
                    auteur: oeuvre.auteurPrincipal
                )
                .frame(width: 64)

                VStack(alignment: .leading, spacing: 4) {
                    Text("En ce moment")
                        .font(.caption2.weight(.heavy))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                        .kerning(0.5)
                    Text(oeuvre.titre(langue))
                        .font(.titreOeuvre(18))
                        .lineLimit(2)
                    Text(oeuvre.auteurPrincipal)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    BarreProgression(valeur: exemplaire.progression)
                        .padding(.top, 3)
                    if let pages = oeuvre.pages {
                        Text("p. \(exemplaire.pageCourante) sur \(pages) · \(Int(exemplaire.progression * 100)) %")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Carte objectif (arc + pilule + semaine)

    private var carteObjectif: some View {
        VStack(spacing: 12) {
            VStack(spacing: 3) {
                Text("Objectif de lecture")
                    .font(.titreOeuvre(19))
                Text("Lisez chaque jour : la série grandit, les statistiques suivent.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 2)

            ArcObjectifView(
                minutes: StatsEngine.minutesAujourdhui(sessions),
                objectif: objectifMinutes
            )
            .frame(maxWidth: 240)

            Button { reglagesVisibles = true } label: {
                HStack(spacing: 2) {
                    Text("Ajuster l'objectif")
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Couleurs.accent)
            }

            if let courant = enCeMoment, let oeuvre = courant.oeuvre {
                PiluleCTA(
                    titre: "Reprendre la lecture",
                    sousTitre: oeuvre.titre(langue)
                ) {
                    cibleSession = .oeuvre(oeuvre)
                }
                .frame(maxWidth: 280)
            } else {
                PiluleCTA(titre: "Commencer une lecture") {
                    allerRecherche()
                }
                .frame(maxWidth: 280)
            }

            SemaineSerieView(joursActifs: StatsEngine.joursActifs(sessions))

            legendeSerie
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 14)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
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
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)

            if serie >= 2 && serie >= record {
                Text("Nouveau record")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Couleurs.accent)
            }
        }
    }

    // MARK: - À suivre

    private var sectionASuivre: some View {
        VStack(alignment: .leading, spacing: 10) {
            EtiquetteSection(texte: "À suivre")
                .padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(aSuivre) { exemplaire in
                        if let oeuvre = exemplaire.oeuvre {
                            NavigationLink {
                                FicheOeuvreView(oeuvre: oeuvre)
                            } label: {
                                CouvertureView(
                                    urlString: oeuvre.couvertureCanoniqueURL,
                                    titre: oeuvre.titre(langue),
                                    auteur: oeuvre.auteurPrincipal
                                )
                                .frame(width: 78)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Sorties à venir

    private var sectionSorties: some View {
        VStack(alignment: .leading, spacing: 10) {
            EtiquetteSection(texte: "Sorties à venir")
            VStack(spacing: 8) {
                ForEach(sortiesAVenir.prefix(3)) { serie in
                    NavigationLink {
                        FicheSerieView(serie: serie)
                    } label: {
                        HStack(spacing: 12) {
                            CouvertureView(
                                urlString: serie.couvertureURL,
                                titre: serie.nomAffiche(langue),
                                coins: 4
                            )
                            .frame(width: 34)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(serie.nomAffiche(langue))
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
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
                        .padding(12)
                        .background(
                            Color(uiColor: .secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
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

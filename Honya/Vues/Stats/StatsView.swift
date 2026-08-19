import SwiftUI
import SwiftData
import Charts

struct StatsView: View {
    @Query private var sessions: [SessionLecture]
    @Query private var exemplaires: [Exemplaire]
    @Query private var series: [Serie]
    @Query private var tomes: [Tome]
    @Query private var oeuvres: [Oeuvre]
    @Query private var badges: [BadgeGagne]
    @Query private var objectifs: [Objectif]

    @State private var periode: StatsEngine.Periode = .semaine

    private var filtrees: [SessionLecture] {
        StatsEngine.filtrer(sessions, periode: periode)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    EnteteEcran(titre: "Statistiques")

                    Picker("Période", selection: $periode) {
                        ForEach(StatsEngine.Periode.allCases) { cas in
                            Text(cas.libelle).tag(cas)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 20)

                    Group {
                        carteHero
                        carteTempsParJour
                        carteHeatmap
                        rangeTuiles
                        carteDefiAnnuel
                        carteRecords
                        carteGenres
                        carteBadges
                        carteRetrospective
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 24)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: - Héros : la réponse avant le graphique

    private var carteHero: some View {
        let totalMinutes = filtrees.reduce(0) { $0 + $1.dureeSecondes } / 60
        let joursActifs = StatsEngine.joursActifs(filtrees).count
        return carte {
            EtiquetteCarte("Temps de lecture · \(periode.libelle.lowercased())")
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(formaterHeures(totalMinutes))
                    .font(.chiffreSerif(34))
                    .monospacedDigit()
                if joursActifs > 0 {
                    Text("sur \(joursActifs) \(joursActifs > 1 ? "jours actifs" : "jour actif")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Barres : 14 derniers jours

    private var carteTempsParJour: some View {
        carte {
            EtiquetteCarte("14 derniers jours · minutes")
            Chart(StatsEngine.derniersJours(14, sessions: sessions)) { jour in
                BarMark(
                    x: .value("Jour", jour.date, unit: .day),
                    y: .value("Minutes", jour.minutes)
                )
                .foregroundStyle(
                    Calendar.current.isDateInToday(jour.date)
                        ? Couleurs.accent
                        : Couleurs.accent.opacity(0.42)
                )
                .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 7)) { _ in
                    AxisGridLine().foregroundStyle(.clear)
                    AxisValueLabel(format: .dateTime.day(), centered: true)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3))
            }
            .frame(height: 130)
        }
    }

    // MARK: - Heatmap calendrier du mois

    private var carteHeatmap: some View {
        let jours = StatsEngine.moisCourant(sessions: sessions)
        return carte {
            HStack {
                EtiquetteCarte(Date.now.formatted(.dateTime.month(.wide).year()).capitalized)
                Spacer()
                Text("moins → plus")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(["L", "M", "M", "J", "V", "S", "D"].indices, id: \.self) { index in
                    Text(["L", "M", "M", "J", "V", "S", "D"][index])
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                ForEach(0..<decalagePremierJour(jours), id: \.self) { _ in
                    Color.clear.frame(height: 18)
                }
                ForEach(jours) { jour in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(couleurChaleur(jour.minutes))
                        .frame(height: 18)
                        .overlay {
                            if Calendar.current.isDateInToday(jour.date) {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .strokeBorder(Couleurs.accent, lineWidth: 1.5)
                            }
                        }
                        .accessibilityLabel("\(jour.date.formatted(.dateTime.day().month())) : \(jour.minutes) minutes")
                }
            }
        }
    }

    private func decalagePremierJour(_ jours: [DonneesJour]) -> Int {
        guard let premier = jours.first?.date else { return 0 }
        let weekday = Calendar.current.component(.weekday, from: premier)
        return (weekday + 5) % 7 // lundi = 0
    }

    private func couleurChaleur(_ minutes: Int) -> Color {
        guard minutes > 0 else { return Color(uiColor: .secondarySystemFill) }
        let intensite = 0.25 + min(0.75, Double(minutes) / 60.0 * 0.75)
        return Couleurs.accent.opacity(intensite)
    }

    // MARK: - Tuiles pages & vitesse

    private var rangeTuiles: some View {
        HStack(spacing: 12) {
            tuile(
                valeur: "\(StatsEngine.totalPages(filtrees))",
                libelle: "pages · \(periode.libelle.lowercased())"
            )
            tuile(
                valeur: StatsEngine.vitessePagesParHeure(filtrees).map { "\($0) p/h" } ?? "—",
                libelle: "vitesse moyenne"
            )
        }
    }

    private func tuile(valeur: String, libelle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(valeur)
                .font(.chiffreSerif(24))
                .monospacedDigit()
            Text(libelle)
                .font(.caption2.weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .kerning(0.4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }

    // MARK: - Défi annuel

    private var carteDefiAnnuel: some View {
        let annee = Calendar.current.component(.year, from: .now)
        let objectifDefi = max(1, objectifs.first?.defiAnnuelLivres ?? 26)
        let termines = StatsEngine.terminesDansAnnee(annee, exemplaires: exemplaires, tomes: tomes)
        let jourDeLAnnee = Calendar.current.ordinality(of: .day, in: .year, for: .now) ?? 1
        let attendu = Double(objectifDefi) * Double(jourDeLAnnee) / 365.0
        let avance = termines - Int(attendu.rounded())

        return carte {
            EtiquetteCarte("Défi \(String(annee))")
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text("\(termines)")
                    .font(.chiffreSerif(30))
                    .monospacedDigit()
                Text("sur \(objectifDefi) lectures")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(texteRythme(avance))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(avance >= 0 ? Couleurs.lu : Couleurs.accent)
            }
            BarreProgression(valeur: Double(termines) / Double(objectifDefi))

            Chart(Array(0..<12), id: \.self) { index in
                BarMark(
                    x: .value("Mois", dateMois(index), unit: .month),
                    y: .value("Lectures", terminesParMois[index])
                )
                .foregroundStyle(Couleurs.accent.opacity(0.5))
                .cornerRadius(2)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.narrow), centered: true)
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 60)
        }
    }

    private var terminesParMois: [Int] {
        StatsEngine.terminesParMois(
            annee: Calendar.current.component(.year, from: .now),
            exemplaires: exemplaires,
            tomes: tomes
        )
    }

    private func dateMois(_ index: Int) -> Date {
        var composants = Calendar.current.dateComponents([.year], from: .now)
        composants.month = index + 1
        composants.day = 1
        return Calendar.current.date(from: composants) ?? .now
    }

    private func texteRythme(_ avance: Int) -> String {
        if avance > 0 { return "en avance de \(avance)" }
        if avance < 0 { return "en retard de \(-avance)" }
        return "pile dans le rythme"
    }

    // MARK: - Records

    private var carteRecords: some View {
        carte {
            EtiquetteCarte("Records")
            rangee(
                "Plus longue session",
                valeur: "\(StatsEngine.plusLongueSessionMinutes(sessions)) min"
            )
            if let meilleur = StatsEngine.meilleurMois(sessions) {
                rangee(
                    "Meilleur mois",
                    valeur: "\(meilleur.date.formatted(.dateTime.month(.wide).year())) · \(formaterHeures(meilleur.minutes))"
                )
            }
            rangee(
                "Série la plus longue",
                valeur: "\(StatsEngine.serieMax(sessions)) jours"
            )
        }
    }

    private func rangee(_ libelle: String, valeur: String) -> some View {
        HStack {
            Text(libelle)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(valeur)
                .font(.caption.weight(.bold))
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }

    // MARK: - Genres

    private var carteGenres: some View {
        let repartition = Array(StatsEngine.genres(oeuvres: oeuvres, series: series).prefix(5))
        let maximum = max(repartition.first?.nombre ?? 1, 1)
        return carte {
            EtiquetteCarte("Vos genres")
            if repartition.isEmpty {
                Text("Les genres apparaîtront avec vos premiers ajouts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(repartition, id: \.genre) { element in
                HStack(spacing: 10) {
                    Text(element.genre)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .frame(width: 92, alignment: .leading)
                    BarreProgression(valeur: Double(element.nombre) / Double(maximum))
                    Text("\(element.nombre)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 26, alignment: .trailing)
                }
            }
        }
    }

    // MARK: - Badges

    private var carteBadges: some View {
        let gagnes = Dictionary(uniqueKeysWithValues: badges.map { ($0.typeRaw, $0.date) })
        return carte {
            EtiquetteCarte("Badges · \(gagnes.count)/\(TypeBadge.allCases.count)")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(TypeBadge.allCases) { badge in
                    let dateGain = gagnes[badge.rawValue]
                    HStack(spacing: 10) {
                        Image(systemName: badge.symbole)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(dateGain != nil ? .white : Color.secondary)
                            .frame(width: 40, height: 40)
                            .background(
                                dateGain != nil
                                    ? AnyShapeStyle(
                                        RadialGradient(
                                            colors: [Couleurs.accent.opacity(0.85), Couleurs.accent],
                                            center: .topLeading, startRadius: 2, endRadius: 40
                                        )
                                    )
                                    : AnyShapeStyle(Color(uiColor: .secondarySystemFill)),
                                in: Circle()
                            )
                        VStack(alignment: .leading, spacing: 1) {
                            Text(badge.nom)
                                .font(.caption.weight(.bold))
                                .lineLimit(1)
                            Text(dateGain.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? badge.condition)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                    }
                    .opacity(dateGain != nil ? 1 : 0.75)
                }
            }
        }
    }

    // MARK: - Rétrospective (teaser)

    private var carteRetrospective: some View {
        carte {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title3)
                    .foregroundStyle(Couleurs.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rétrospective \(String(Calendar.current.component(.year, from: .now)))")
                        .font(.subheadline.weight(.bold))
                    Text("Votre année de lecture en cartes partageables — rendez-vous en décembre.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Aides

    private func carte(@ViewBuilder _ contenu: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            contenu()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }

    private func formaterHeures(_ minutes: Int) -> String {
        let heures = minutes / 60
        let reste = minutes % 60
        if heures > 0 { return "\(heures) h \(String(format: "%02d", reste))" }
        return "\(reste) min"
    }
}

#Preview {
    StatsView()
        .modelContainer(Apercu.conteneur)
}

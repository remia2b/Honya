import SwiftUI
import SwiftData
import Charts

/// Les statistiques, dans le langage visuel d'Apple Books : des bandes pleine
/// largeur qui alternent avec le fond, des grands chiffres serif, et surtout
/// des compteurs AUTOMATIQUES — possédés, lus, pages… tout se déduit des
/// étagères, sans que le lecteur n'ait rien à saisir.
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
                VStack(alignment: .leading, spacing: 0) {
                    EnteteEcran(titre: "Statistiques")

                    Picker("Période", selection: $periode) {
                        ForEach(StatsEngine.Periode.allCases) { cas in
                            Text(cas.libelle).tag(cas)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)

                    bandeTemps
                    bandeBibliotheque
                    bandeDefi
                    bandeMois
                    bandeGenres
                    bandeRecords
                    bandeBadges
                    bandeRetrospective
                }
                .padding(.bottom, 24)
            }
            .background(Color(uiColor: .systemBackground))
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: - Temps de lecture (bande héro)

    private var bandeTemps: some View {
        let totalMinutes = filtrees.reduce(0) { $0 + $1.dureeSecondes } / 60
        let joursActifs = StatsEngine.joursActifs(filtrees).count
        return BandeSection {
            TitreSection(
                titre: "Temps de lecture",
                sousTitre: LocalizedStringKey(periode.libelle)
            )
                .padding(.horizontal, 20)

            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(formaterHeures(totalMinutes))
                    .font(.chiffreSerif(52))
                    .monospacedDigit()
                if joursActifs > 0 {
                    Text("sur \(joursActifs) \(joursActifs > 1 ? "jours actifs" : "jour actif")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)

            graphe14Jours
                .padding(.horizontal, 20)

            HStack(spacing: 0) {
                miniStat("\(StatsEngine.totalPages(filtrees))", "pages")
                miniStat(
                    StatsEngine.vitessePagesParHeure(filtrees).map { "\($0)" } ?? "—",
                    "pages / heure"
                )
                miniStat("\(StatsEngine.plusLongueSessionMinutes(sessions))", "record · min")
            }
            .padding(.horizontal, 20)

            if sessions.isEmpty {
                Text("Lancez une session depuis l'accueil : minutes, pages et records se mesurent tout seuls.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
            }
        }
    }

    private var graphe14Jours: some View {
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
        .frame(height: 120)
    }

    // MARK: - La bibliothèque en chiffres (tout est automatique)

    private var bandeBibliotheque: some View {
        BandeSection(teintee: true) {
            TitreSection(
                titre: "Votre bibliothèque",
                sousTitre: "Compté tout seul depuis vos étagères"
            )
            .padding(.horizontal, 20)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3),
                spacing: 18
            ) {
                grandChiffre("\(nbPossedes)", "possédés")
                grandChiffre("\(nbLusTotal)", "lus")
                grandChiffre("\(nbEnCoursTotal)", "en cours")
                grandChiffre("\(seriesTerminees)", seriesTerminees > 1 ? "séries finies" : "série finie")
                grandChiffre("\(nbAAcheter)", "à acheter")
                grandChiffre(pagesLues.formatted(), "pages lues")
            }
            .padding(.horizontal, 20)

            repartitionTypes
                .padding(.horizontal, 20)
        }
    }

    /// Livres gardés + tomes cochés possédés.
    private var nbPossedes: Int {
        exemplaires.filter { $0.statut != .wishlist }.count
            + tomes.filter(\.possede).count
    }

    /// Livres lus + tomes lus.
    private var nbLusTotal: Int {
        exemplaires.filter { $0.statut == .lu }.count
            + tomes.filter(\.lu).count
    }

    private var nbEnCoursTotal: Int {
        exemplaires.filter { $0.statut == .enCours }.count
            + series.filter { $0.statut == .enCours }.count
    }

    private var seriesTerminees: Int {
        series.filter(\.estTerminee).count
    }

    /// Envies + tomes parus qui manquent encore au rayon.
    private var nbAAcheter: Int {
        exemplaires.filter { $0.statut == .wishlist }.count
            + series.flatMap(\.tomesParus).filter { !$0.possede }.count
    }

    /// Pages estimées d'après tout ce qui est marqué lu.
    private var pagesLues: Int {
        tomes.filter(\.lu).compactMap(\.pages).reduce(0, +)
            + exemplaires.filter { $0.statut == .lu }
                .compactMap { $0.oeuvre?.pages }
                .reduce(0, +)
    }

    private var comptesTypes: [(nom: String, nombre: Int, couleur: Color)] {
        func compte(_ type: TypeOeuvre) -> Int {
            series.filter { $0.type == type }.count
                + exemplaires.filter { $0.oeuvre?.type == type }.count
        }
        return [
            ("Mangas", compte(.manga), Couleurs.accent),
            ("Livres", compte(.livre), Couleurs.aLire),
            ("BD", compte(.bd), Couleurs.lu),
        ].filter { $0.1 > 0 }
    }

    @ViewBuilder
    private var repartitionTypes: some View {
        let comptes = comptesTypes
        let total = comptes.reduce(0) { $0 + $1.nombre }
        if total > 0 {
            VStack(alignment: .leading, spacing: 8) {
                GeometryReader { geo in
                    HStack(spacing: 3) {
                        ForEach(comptes, id: \.nom) { part in
                            Capsule()
                                .fill(part.couleur)
                                .frame(
                                    width: max(
                                        10,
                                        (geo.size.width - CGFloat(comptes.count - 1) * 3)
                                            * CGFloat(part.nombre) / CGFloat(total)
                                    )
                                )
                        }
                    }
                }
                .frame(height: 10)
                HStack(spacing: 14) {
                    ForEach(comptes, id: \.nom) { part in
                        HStack(spacing: 5) {
                            Circle().fill(part.couleur).frame(width: 7, height: 7)
                            Text("\(part.nom) · \(part.nombre)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Défi de l'année

    private var bandeDefi: some View {
        let annee = Calendar.current.component(.year, from: .now)
        let objectifDefi = max(1, objectifs.first?.defiAnnuelLivres ?? 26)
        let termines = StatsEngine.terminesDansAnnee(annee, exemplaires: exemplaires, tomes: tomes)
        let jourDeLAnnee = Calendar.current.ordinality(of: .day, in: .year, for: .now) ?? 1
        let attendu = Double(objectifDefi) * Double(jourDeLAnnee) / 365.0
        let avance = termines - Int(attendu.rounded())

        return BandeSection {
            TitreSection(titre: "Défi \(String(annee))", sousTitre: "Vos lectures terminées, mois par mois")
                .padding(.horizontal, 20)

            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text("\(termines)")
                    .font(.chiffreSerif(44))
                    .monospacedDigit()
                Text("sur \(objectifDefi) lectures")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(texteRythme(avance))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(avance >= 0 ? Couleurs.lu : Couleurs.accent)
            }
            .padding(.horizontal, 20)

            BarreProgression(valeur: Double(termines) / Double(objectifDefi))
                .padding(.horizontal, 20)

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
            .frame(height: 64)
            .padding(.horizontal, 20)
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
        if avance > 0 { return String(localized: "en avance de \(avance)") }
        if avance < 0 { return String(localized: "en retard de \(-avance)") }
        return String(localized: "pile dans le rythme")
    }

    // MARK: - Le mois, jour par jour

    private var bandeMois: some View {
        let jours = StatsEngine.moisCourant(sessions: sessions)
        return BandeSection(teintee: true) {
            HStack(alignment: .lastTextBaseline) {
                // Un nom de mois est déjà dans la langue du lecteur : il ne
                // passe donc pas par le catalogue, seulement par la mise en page.
                TitreSection(
                    titre: LocalizedStringKey(
                        Date.now.formatted(.dateTime.month(.wide).year()).capitalized
                    )
                )
                Spacer()
                Text("moins → plus")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7),
                spacing: 4
            ) {
                ForEach(["L", "M", "M", "J", "V", "S", "D"].indices, id: \.self) { index in
                    Text(["L", "M", "M", "J", "V", "S", "D"][index])
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                ForEach(0..<decalagePremierJour(jours), id: \.self) { _ in
                    Color.clear.frame(height: 20)
                }
                ForEach(jours) { jour in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(couleurChaleur(jour.minutes))
                        .frame(height: 20)
                        .overlay {
                            if Calendar.current.isDateInToday(jour.date) {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .strokeBorder(Couleurs.accent, lineWidth: 1.5)
                            }
                        }
                        .accessibilityLabel("\(jour.date.formatted(.dateTime.day().month())) : \(jour.minutes) minutes")
                }
            }
            .padding(.horizontal, 20)
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

    // MARK: - Genres

    private var bandeGenres: some View {
        let repartition = Array(StatsEngine.genres(oeuvres: oeuvres, series: series).prefix(5))
        let maximum = max(repartition.first?.nombre ?? 1, 1)
        return BandeSection {
            TitreSection(titre: "Vos genres", sousTitre: "Ce que racontent vos étagères")
                .padding(.horizontal, 20)
            if repartition.isEmpty {
                Text("Les genres apparaîtront avec vos premiers ajouts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
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
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Records

    private var bandeRecords: some View {
        BandeSection(teintee: true) {
            TitreSection(titre: "Records")
                .padding(.horizontal, 20)
            VStack(spacing: 8) {
                if let meilleur = StatsEngine.meilleurMois(sessions) {
                    rangee(
                        "Meilleur mois",
                        valeur: "\(meilleur.date.formatted(.dateTime.month(.wide).year())) · \(formaterHeures(meilleur.minutes))"
                    )
                }
                rangee("Plus longue session", valeur: "\(StatsEngine.plusLongueSessionMinutes(sessions)) min")
                rangee("Série de jours de lecture", valeur: "\(StatsEngine.serieMax(sessions)) jours")
            }
            .padding(.horizontal, 20)
        }
    }

    private func rangee(_ libelle: LocalizedStringKey, valeur: String) -> some View {
        HStack {
            Text(libelle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(valeur)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
        }
    }

    // MARK: - Badges

    private var bandeBadges: some View {
        let gagnes = Dictionary(uniqueKeysWithValues: badges.map { ($0.typeRaw, $0.date) })
        return BandeSection {
            TitreSection(
                titre: "Badges",
                sousTitre: "\(gagnes.count) sur \(TypeBadge.allCases.count) débloqués"
            )
            .padding(.horizontal, 20)
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
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Rétrospective (teaser)

    private var bandeRetrospective: some View {
        BandeSection(teintee: true) {
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
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Aides

    private func grandChiffre(_ valeur: String, _ libelle: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(valeur)
                .font(.chiffreSerif(30))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(libelle)
                .font(.caption2.weight(.bold))
                .textCase(.uppercase)
                .kerning(0.4)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func miniStat(_ valeur: String, _ libelle: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(valeur)
                .font(.chiffreSerif(24))
                .monospacedDigit()
            Text(libelle)
                .font(.caption2.weight(.bold))
                .textCase(.uppercase)
                .kerning(0.4)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formaterHeures(_ minutes: Int) -> String {
        let heures = minutes / 60
        let reste = minutes % 60
        if heures > 0 {
            let minutes = String(format: "%02d", reste)
            return String(localized: "\(heures) h \(minutes)")
        }
        return String(localized: "\(reste) min")
    }
}

#Preview {
    StatsView()
        .modelContainer(Apercu.conteneur)
}

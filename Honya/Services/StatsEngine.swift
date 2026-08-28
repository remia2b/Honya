import Foundation

/// Un point temporel pour les graphiques : un jour ou un mois selon la période.
struct DonneesJour: Identifiable {
    let date: Date
    let minutes: Int
    var id: Date { date }
}

/// Tous les calculs de statistiques — fonctions pures sur les données SwiftData.
enum StatsEngine {

    private static var calendrier: Calendar {
        var c = Calendar.current
        c.firstWeekday = 2 // lundi
        return c
    }

    // MARK: - Temps de lecture

    static func minutes(le jour: Date, dans sessions: [SessionLecture]) -> Int {
        let debut = calendrier.startOfDay(for: jour)
        return sessions
            .filter { calendrier.startOfDay(for: $0.debut) == debut }
            .reduce(0) { $0 + $1.dureeSecondes } / 60
    }

    static func minutesAujourdhui(_ sessions: [SessionLecture]) -> Int {
        minutes(le: .now, dans: sessions)
    }

    static func derniersJours(_ nombre: Int, sessions: [SessionLecture]) -> [DonneesJour] {
        (0..<nombre).reversed().compactMap { decalage in
            guard let jour = calendrier.date(byAdding: .day, value: -decalage, to: .now) else { return nil }
            return DonneesJour(
                date: calendrier.startOfDay(for: jour),
                minutes: minutes(le: jour, dans: sessions)
            )
        }
    }

    /// Tous les jours du mois courant, pour la heatmap calendrier.
    static func moisCourant(sessions: [SessionLecture]) -> [DonneesJour] {
        guard let intervalle = calendrier.dateInterval(of: .month, for: .now),
              let nbJours = calendrier.range(of: .day, in: .month, for: .now)?.count
        else { return [] }
        return (0..<nbJours).compactMap { decalage in
            guard let jour = calendrier.date(byAdding: .day, value: decalage, to: intervalle.start) else { return nil }
            return DonneesJour(date: jour, minutes: minutes(le: jour, dans: sessions))
        }
    }

    // MARK: - Données du graphique par période

    /// Les points du graphique principal couvrent exactement la période choisie.
    /// La semaine et le mois restent détaillés par jour ; l'année et l'historique
    /// complet sont regroupés par mois pour rester lisibles.
    static func donneesGraphique(
        periode: Periode,
        sessions: [SessionLecture],
        maintenant: Date = .now
    ) -> [DonneesJour] {
        switch periode {
        case .semaine:
            guard let intervalle = calendrier.dateInterval(of: .weekOfYear, for: maintenant)
            else { return [] }
            return pointsParJour(intervalle: intervalle, sessions: sessions)

        case .mois:
            guard let intervalle = calendrier.dateInterval(of: .month, for: maintenant)
            else { return [] }
            return pointsParJour(intervalle: intervalle, sessions: sessions)

        case .annee:
            guard let intervalle = calendrier.dateInterval(of: .year, for: maintenant)
            else { return [] }
            return pointsParMois(intervalle: intervalle, sessions: sessions)

        case .tout:
            guard let premiere = sessions.map(\.debut).min(),
                  let dernierDebut = sessions.map(\.debut).max(),
                  let debut = calendrier.dateInterval(of: .month, for: premiere)?.start,
                  let debutDernierMois = calendrier.dateInterval(
                    of: .month,
                    for: max(maintenant, dernierDebut)
                  )?.start,
                  let fin = calendrier.date(byAdding: .month, value: 1, to: debutDernierMois)
            else { return [] }
            return pointsParMois(
                intervalle: DateInterval(start: debut, end: fin),
                sessions: sessions
            )
        }
    }

    private static func pointsParJour(
        intervalle: DateInterval,
        sessions: [SessionLecture]
    ) -> [DonneesJour] {
        var secondes: [Date: Int] = [:]
        for session in sessions where intervalle.contains(session.debut) {
            secondes[calendrier.startOfDay(for: session.debut), default: 0] += session.dureeSecondes
        }

        var resultat: [DonneesJour] = []
        var date = calendrier.startOfDay(for: intervalle.start)
        while date < intervalle.end {
            resultat.append(DonneesJour(date: date, minutes: secondes[date, default: 0] / 60))
            guard let suivante = calendrier.date(byAdding: .day, value: 1, to: date)
            else { break }
            date = suivante
        }
        return resultat
    }

    private static func pointsParMois(
        intervalle: DateInterval,
        sessions: [SessionLecture]
    ) -> [DonneesJour] {
        var secondes: [Date: Int] = [:]
        for session in sessions where intervalle.contains(session.debut) {
            guard let mois = calendrier.dateInterval(of: .month, for: session.debut)?.start
            else { continue }
            secondes[mois, default: 0] += session.dureeSecondes
        }

        var resultat: [DonneesJour] = []
        var date = intervalle.start
        while date < intervalle.end {
            resultat.append(DonneesJour(date: date, minutes: secondes[date, default: 0] / 60))
            guard let suivante = calendrier.date(byAdding: .month, value: 1, to: date)
            else { break }
            date = suivante
        }
        return resultat
    }

    // MARK: - Série de jours (streak)

    static func joursActifs(_ sessions: [SessionLecture]) -> Set<Date> {
        Set(sessions.lazy
            .filter { $0.dureeSecondes > 0 }
            .map { calendrier.startOfDay(for: $0.debut) })
    }

    /// Série de jours consécutifs, avec un joker : un trou d'un jour est pardonné
    /// (une soirée ratée ne brûle pas 40 jours d'effort).
    static func serieDeJours(_ sessions: [SessionLecture]) -> Int {
        let jours = joursActifs(sessions)
        guard !jours.isEmpty else { return 0 }

        var jour = calendrier.startOfDay(for: .now)
        if !jours.contains(jour) {
            // Aujourd'hui pas (encore) lu : la série se compte depuis hier.
            guard let hier = calendrier.date(byAdding: .day, value: -1, to: jour) else { return 0 }
            jour = hier
        }
        var serie = 0
        var jokerDisponible = true
        while true {
            if jours.contains(jour) {
                serie += 1
            } else if jokerDisponible && serie > 0 {
                jokerDisponible = false
            } else {
                break
            }
            guard let veille = calendrier.date(byAdding: .day, value: -1, to: jour) else { break }
            jour = veille
        }
        return serie
    }

    /// Plus longue série jamais réalisée (stricte, sans joker).
    static func serieMax(_ sessions: [SessionLecture]) -> Int {
        let jours = joursActifs(sessions).sorted()
        guard !jours.isEmpty else { return 0 }
        var record = 1
        var courante = 1
        for index in 1..<jours.count {
            let ecart = calendrier.dateComponents([.day], from: jours[index - 1], to: jours[index]).day ?? 0
            if ecart == 1 {
                courante += 1
                record = max(record, courante)
            } else {
                courante = 1
            }
        }
        return record
    }

    // MARK: - Pages & vitesse

    static func totalPages(_ sessions: [SessionLecture]) -> Int {
        sessions.reduce(0) { $0 + $1.pagesLues }
    }

    /// Pages par heure, sur les sessions où des pages ont été saisies.
    static func vitessePagesParHeure(_ sessions: [SessionLecture]) -> Int? {
        let utiles = sessions.filter { $0.pagesLues > 0 && $0.dureeSecondes > 60 }
        let secondes = utiles.reduce(0) { $0 + $1.dureeSecondes }
        let pages = utiles.reduce(0) { $0 + $1.pagesLues }
        guard secondes > 0, pages > 0 else { return nil }
        return Int((Double(pages) / Double(secondes)) * 3600)
    }

    // MARK: - Records

    static func plusLongueSessionMinutes(_ sessions: [SessionLecture]) -> Int {
        (sessions.map(\.dureeSecondes).max() ?? 0) / 60
    }

    /// (début du mois, minutes) du meilleur mois.
    static func meilleurMois(_ sessions: [SessionLecture]) -> (date: Date, minutes: Int)? {
        let groupes = Dictionary(grouping: sessions) { session in
            calendrier.dateInterval(of: .month, for: session.debut)?.start ?? session.debut
        }
        let sommes = groupes.mapValues { $0.reduce(0) { $0 + $1.dureeSecondes } / 60 }
        guard let meilleur = sommes.max(by: { $0.value < $1.value }) else { return nil }
        return (meilleur.key, meilleur.value)
    }

    // MARK: - Livres & tomes terminés

    /// Livres finis + tomes de manga lus sur l'année (un tome compte comme une lecture).
    static func terminesDansAnnee(
        _ annee: Int,
        exemplaires: [Exemplaire],
        tomes: [Tome]
    ) -> Int {
        let livres = exemplaires.filter {
            guard let fin = $0.dateFin else { return false }
            return calendrier.component(.year, from: fin) == annee
        }.count
        let volumes = tomes.filter {
            guard let lu = $0.dateLu else { return false }
            return calendrier.component(.year, from: lu) == annee
        }.count
        return livres + volumes
    }

    static func terminesParMois(
        annee: Int,
        exemplaires: [Exemplaire],
        tomes: [Tome]
    ) -> [Int] {
        var mois = [Int](repeating: 0, count: 12)
        for exemplaire in exemplaires {
            if let fin = exemplaire.dateFin, calendrier.component(.year, from: fin) == annee {
                mois[calendrier.component(.month, from: fin) - 1] += 1
            }
        }
        for tome in tomes {
            if let lu = tome.dateLu, calendrier.component(.year, from: lu) == annee {
                mois[calendrier.component(.month, from: lu) - 1] += 1
            }
        }
        return mois
    }

    // MARK: - Genres

    /// Répartition par genre sur toute la bibliothèque (œuvres + séries), triée décroissante.
    static func genres(oeuvres: [Oeuvre], series: [Serie]) -> [(genre: String, nombre: Int)] {
        var comptes: [String: Int] = [:]
        for oeuvre in oeuvres {
            for genre in oeuvre.genres { comptes[genre, default: 0] += 1 }
        }
        for serie in series {
            for genre in serie.genres { comptes[genre, default: 0] += 1 }
        }
        return comptes
            .sorted { $0.value > $1.value }
            .map { (genre: $0.key, nombre: $0.value) }
    }

    // MARK: - Filtrage par période (pour l'écran Stats)

    enum Periode: String, CaseIterable, Identifiable {
        case semaine = "S", mois = "M", annee = "A", tout = "∞"
        var id: String { rawValue }

        var libelle: String {
            switch self {
            case .semaine: return String(localized: "Semaine")
            case .mois: return String(localized: "Mois")
            case .annee: return String(localized: "Année")
            case .tout: return String(localized: "Tout")
            }
        }

        var granulariteGraphique: Calendar.Component {
            switch self {
            case .semaine, .mois: return .day
            case .annee, .tout: return .month
            }
        }
    }

    static func filtrer(_ sessions: [SessionLecture], periode: Periode) -> [SessionLecture] {
        let composant: Calendar.Component?
        switch periode {
        case .semaine: composant = .weekOfYear
        case .mois: composant = .month
        case .annee: composant = .year
        case .tout: composant = nil
        }
        guard let composant,
              let intervalle = calendrier.dateInterval(of: composant, for: .now)
        else { return sessions }
        return sessions.filter { intervalle.contains($0.debut) }
    }
}

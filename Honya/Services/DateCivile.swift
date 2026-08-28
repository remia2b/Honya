import Foundation

/// Compare les dates éditoriales comme des jours de calendrier, jamais comme
/// des instants. Les catalogues n'annoncent pas qu'un tome sort « à midi » :
/// l'heure technique choisie pour éviter les changements de fuseau ne doit pas
/// le laisser en précommande pendant la moitié de son jour de parution.
enum DateCivile {
    private static func jour(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    static func estAVenir(_ date: Date, maintenant: Date = Date()) -> Bool {
        jour(date) > jour(maintenant)
    }

    static func estDisponible(_ date: Date, maintenant: Date = Date()) -> Bool {
        !estAVenir(date, maintenant: maintenant)
    }

    static func estAujourdhuiOuApres(_ date: Date, maintenant: Date = Date()) -> Bool {
        jour(date) >= jour(maintenant)
    }

    static func estApres(_ date: Date, que reference: Date) -> Bool {
        jour(date) > jour(reference)
    }

    /// Extrait la partie `yyyy-MM-dd` d'une date ISO annoncée par un catalogue
    /// et la matérialise à midi local, avec validation stricte du jour civil.
    static func depuisISO(_ valeur: String) -> Date? {
        let prefixe = String(valeur.prefix(10))
        let morceaux = prefixe.split(separator: "-", omittingEmptySubsequences: false)
        guard morceaux.count == 3,
              morceaux[0].count == 4,
              morceaux[1].count == 2,
              morceaux[2].count == 2,
              let annee = Int(morceaux[0]),
              let mois = Int(morceaux[1]),
              let jour = Int(morceaux[2])
        else { return nil }

        var calendrier = Calendar(identifier: .gregorian)
        calendrier.timeZone = .current
        var composants = DateComponents()
        composants.calendar = calendrier
        composants.timeZone = .current
        composants.year = annee
        composants.month = mois
        composants.day = jour
        composants.hour = 12
        guard let date = composants.date else { return nil }
        let verification = calendrier.dateComponents([.year, .month, .day], from: date)
        guard verification.year == annee,
              verification.month == mois,
              verification.day == jour
        else { return nil }
        return date
    }
}

import Foundation
import SwiftData

// MARK: - Les huit badges de Honya

enum TypeBadge: String, CaseIterable, Identifiable {
    case marathon, nyctalope, completiste, polygraphe, devoreur, grandePile, aube, fidele

    var id: String { rawValue }

    var nom: String {
        switch self {
        case .marathon: return String(localized: "Marathon")
        case .nyctalope: return String(localized: "Nyctalope")
        case .completiste: return String(localized: "Complétiste")
        case .polygraphe: return String(localized: "Polygraphe")
        case .devoreur: return String(localized: "Dévoreur")
        case .grandePile: return String(localized: "La Grande Pile")
        case .aube: return String(localized: "Aube")
        case .fidele: return String(localized: "Fidèle")
        }
    }

    var condition: String {
        switch self {
        case .marathon: return String(localized: "2 h de lecture d'affilée")
        case .nyctalope: return String(localized: "10 sessions après minuit")
        case .completiste: return String(localized: "Une série finie à 100 %")
        case .polygraphe: return String(localized: "5 genres dans le même mois")
        case .devoreur: return String(localized: "5 tomes en un week-end")
        case .grandePile: return String(localized: "50 livres non lus possédés")
        case .aube: return String(localized: "Lire avant 7 h, 5 fois")
        case .fidele: return String(localized: "Série de 30 jours")
        }
    }

    var symbole: String {
        switch self {
        case .marathon: return "bolt.fill"
        case .nyctalope: return "moon.stars.fill"
        case .completiste: return "checkmark.seal.fill"
        case .polygraphe: return "sparkles"
        case .devoreur: return "square.stack.3d.up.fill"
        case .grandePile: return "books.vertical.fill"
        case .aube: return "sunrise.fill"
        case .fidele: return "infinity"
        }
    }
}

// MARK: - Moteur d'attribution
// Appelé après chaque événement (fin de session, tome coché, statut changé).
// Un badge gagné l'est pour toujours.

@MainActor
enum BadgesEngine {

    static func evaluer(dans contexte: ModelContext) {
        let sessions = (try? contexte.fetch(FetchDescriptor<SessionLecture>())) ?? []
        let exemplaires = (try? contexte.fetch(FetchDescriptor<Exemplaire>())) ?? []
        let series = (try? contexte.fetch(FetchDescriptor<Serie>())) ?? []
        let tomes = (try? contexte.fetch(FetchDescriptor<Tome>())) ?? []
        let existants = (try? contexte.fetch(FetchDescriptor<BadgeGagne>())) ?? []

        var gagnes = Set(existants.map(\.typeRaw))
        func decerner(_ type: TypeBadge, si condition: Bool) {
            guard condition, !gagnes.contains(type.rawValue) else { return }
            contexte.insert(BadgeGagne(typeRaw: type.rawValue))
            gagnes.insert(type.rawValue)
        }

        let calendrier = Calendar.current

        // Marathon : une session ≥ 2 h.
        decerner(.marathon, si: sessions.contains { $0.dureeSecondes >= 7200 })

        // Nyctalope : 10 sessions démarrées entre minuit et 5 h.
        let nuit = sessions.filter { (0..<5).contains(calendrier.component(.hour, from: $0.debut)) }
        decerner(.nyctalope, si: nuit.count >= 10)

        // Aube : 5 sessions démarrées entre 5 h et 7 h.
        let matin = sessions.filter { (5..<7).contains(calendrier.component(.hour, from: $0.debut)) }
        decerner(.aube, si: matin.count >= 5)

        // Complétiste : une série entièrement lue.
        decerner(.completiste, si: series.contains { !$0.tomes.isEmpty && $0.nbLus == $0.tomes.count })

        // Polygraphe : 5 genres différents terminés dans un même mois.
        var genresParMois: [Date: Set<String>] = [:]
        for exemplaire in exemplaires {
            guard let fin = exemplaire.dateFin,
                  let mois = calendrier.dateInterval(of: .month, for: fin)?.start
            else { continue }
            genresParMois[mois, default: []].formUnion(exemplaire.oeuvre?.genres ?? [])
        }
        decerner(.polygraphe, si: genresParMois.values.contains { $0.count >= 5 })

        // Dévoreur : 5 tomes lus dans une fenêtre de 48 h.
        let datesLecture = tomes.compactMap(\.dateLu).sorted()
        var devoreur = false
        if datesLecture.count >= 5 {
            for index in 0...(datesLecture.count - 5) {
                if datesLecture[index + 4].timeIntervalSince(datesLecture[index]) <= 48 * 3600 {
                    devoreur = true
                    break
                }
            }
        }
        decerner(.devoreur, si: devoreur)

        // La Grande Pile : 50 livres possédés jamais lus. Assumé.
        let pile = exemplaires.filter { $0.possede && $0.statut == .aLire }
        decerner(.grandePile, si: pile.count >= 50)

        // Fidèle : une série de 30 jours (historique).
        decerner(.fidele, si: StatsEngine.serieMax(sessions) >= 30)
    }
}

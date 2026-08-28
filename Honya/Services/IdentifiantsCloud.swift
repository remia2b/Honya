import Foundation
import SwiftData

/// Prépare les identités stables nécessaires aux futures sauvegardes cloud.
///
/// Ce service ne contacte aucun serveur et n'est volontairement pas appelé au
/// lancement pour le moment. Il travaille sur les neuf modèles dans une seule
/// transaction : une erreur de lecture ou de sauvegarde remet le contexte dans
/// son état persistant précédent.
@MainActor
enum IdentifiantsCloud {
    enum Erreur: Error, LocalizedError, Sendable {
        case modificationsNonSauvegardees

        var errorDescription: String? {
            switch self {
            case .modificationsNonSauvegardees:
                return "Le contexte contient des modifications non sauvegardées."
            }
        }
    }

    struct Rapport: Equatable, Sendable {
        let inspectes: Int
        let manquantsCompletes: Int
        let doublonsRepares: Int

        var modifications: Int { manquantsCompletes + doublonsRepares }
    }

    static func reparer(dans contexte: ModelContext) throws -> Rapport {
        // `rollback()` restaure tout le ModelContext, pas uniquement les
        // cloudID. Refuser un contexte sale évite donc d'annuler une édition
        // utilisateur sans rapport si le backfill rencontre une erreur.
        guard !contexte.hasChanges else {
            throw Erreur.modificationsNonSauvegardees
        }

        var vus = Set<UUID>()
        var inspectes = 0
        var manquants = 0
        var doublons = 0

        do {
            try contexte.transaction {
                try normaliser(
                    contexte.fetch(FetchDescriptor<Oeuvre>()),
                    lire: { $0.cloudID }, ecrire: { $0.cloudID = $1 },
                    vus: &vus, inspectes: &inspectes,
                    manquants: &manquants, doublons: &doublons
                )
                try normaliser(
                    contexte.fetch(FetchDescriptor<Exemplaire>()),
                    lire: { $0.cloudID }, ecrire: { $0.cloudID = $1 },
                    vus: &vus, inspectes: &inspectes,
                    manquants: &manquants, doublons: &doublons
                )
                try normaliser(
                    contexte.fetch(FetchDescriptor<Serie>()),
                    lire: { $0.cloudID }, ecrire: { $0.cloudID = $1 },
                    vus: &vus, inspectes: &inspectes,
                    manquants: &manquants, doublons: &doublons
                )
                try normaliser(
                    contexte.fetch(FetchDescriptor<Tome>()),
                    lire: { $0.cloudID }, ecrire: { $0.cloudID = $1 },
                    vus: &vus, inspectes: &inspectes,
                    manquants: &manquants, doublons: &doublons
                )
                try normaliser(
                    contexte.fetch(FetchDescriptor<SessionLecture>()),
                    lire: { $0.cloudID }, ecrire: { $0.cloudID = $1 },
                    vus: &vus, inspectes: &inspectes,
                    manquants: &manquants, doublons: &doublons
                )
                try normaliser(
                    contexte.fetch(FetchDescriptor<Citation>()),
                    lire: { $0.cloudID }, ecrire: { $0.cloudID = $1 },
                    vus: &vus, inspectes: &inspectes,
                    manquants: &manquants, doublons: &doublons
                )
                try normaliser(
                    contexte.fetch(FetchDescriptor<Objectif>()),
                    lire: { $0.cloudID }, ecrire: { $0.cloudID = $1 },
                    vus: &vus, inspectes: &inspectes,
                    manquants: &manquants, doublons: &doublons
                )
                try normaliser(
                    contexte.fetch(FetchDescriptor<Collection>()),
                    lire: { $0.cloudID }, ecrire: { $0.cloudID = $1 },
                    vus: &vus, inspectes: &inspectes,
                    manquants: &manquants, doublons: &doublons
                )
                try normaliser(
                    contexte.fetch(FetchDescriptor<BadgeGagne>()),
                    lire: { $0.cloudID }, ecrire: { $0.cloudID = $1 },
                    vus: &vus, inspectes: &inspectes,
                    manquants: &manquants, doublons: &doublons
                )
            }
        } catch {
            contexte.rollback()
            throw error
        }

        return Rapport(
            inspectes: inspectes,
            manquantsCompletes: manquants,
            doublonsRepares: doublons
        )
    }

    private static func normaliser<Modele>(
        _ modeles: [Modele],
        lire: (Modele) -> UUID?,
        ecrire: (Modele, UUID) -> Void,
        vus: inout Set<UUID>,
        inspectes: inout Int,
        manquants: inout Int,
        doublons: inout Int
    ) throws {
        for modele in modeles {
            inspectes += 1
            if let identifiant = lire(modele), vus.insert(identifiant).inserted {
                continue
            }

            if lire(modele) == nil {
                manquants += 1
            } else {
                doublons += 1
            }
            ecrire(modele, nouvelIdentifiant(absentDe: &vus))
        }
    }

    private static func nouvelIdentifiant(absentDe vus: inout Set<UUID>) -> UUID {
        while true {
            let candidat = UUID()
            if vus.insert(candidat).inserted { return candidat }
        }
    }
}

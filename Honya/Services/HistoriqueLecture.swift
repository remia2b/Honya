import Foundation

/// Applique le droit d'accès à l'historique de lecture de façon uniforme.
///
/// Les sessions anciennes ne sont jamais supprimées pour un compte gratuit :
/// elles redeviennent visibles dès que Honya+ est actif. La fenêtre gratuite
/// couvre aujourd'hui et les six jours civils précédents.
enum HistoriqueLecture {
    static func sessionsAutorisees(
        _ sessions: [SessionLecture],
        plus: Bool,
        maintenant: Date = .now,
        calendrier: Calendar = .current
    ) -> [SessionLecture] {
        guard !plus else { return sessions }

        let debutAujourdhui = calendrier.startOfDay(for: maintenant)
        let joursPrecedents = max(0, Limites.joursHistorique - 1)
        guard let debut = calendrier.date(
            byAdding: .day,
            value: -joursPrecedents,
            to: debutAujourdhui
        ) else { return [] }

        return sessions.filter { $0.debut >= debut }
    }
}

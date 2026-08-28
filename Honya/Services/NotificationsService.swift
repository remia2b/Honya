import Foundation
import UserNotifications

/// Rappels de sorties de tomes (planification locale, le matin du jour J).
@MainActor
enum NotificationsService {

    private static let prefixeRappelSortie = "sortie-"
    /// Invalide les reconciliations encore suspendues dans le centre de
    /// notifications lorsqu'un compte est ferme ou remplace par un autre.
    private static var generationReconciliation = 0

    struct CibleAnnulation: Sendable {
        let identifiants: [String]
        let prefixeHistorique: String?
    }

    static func demanderAutorisation() async -> Bool {
        let centre = UNUserNotificationCenter.current()
        return (try? await centre.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func identifiant(pour serie: Serie) -> String {
        if let identifiant = serie.identifiantRappelSortie, !identifiant.isEmpty {
            return prefixeRappelSortie + identifiant
        }
        let identifiant = UUID().uuidString.lowercased()
        serie.identifiantRappelSortie = identifiant
        return prefixeRappelSortie + identifiant
    }

    @discardableResult
    static func planifierRappelSortie(pour serie: Serie, langue: String) async -> Bool {
        let generation = generationReconciliation
        guard appartientAuCompteActif(serie) else { return false }
        // Retire aussi l'ancien identifiant des versions précédentes avant de
        // remplacer la requête. Une modification de date/numéro ne peut ainsi
        // jamais laisser deux alertes en attente.
        annulerRappel(pour: serie)
        guard let date = serie.prochaineSortieDate else { return false }
        let identifiant = identifiant(pour: serie)
        // La requête système peut survivre à l'application : son UUID doit
        // donc être enregistré avant elle, y compris si l'app est quittée juste après.
        do {
            try serie.modelContext?.save()
        } catch {
            return false
        }

        let contenu = UNMutableNotificationContent()
        contenu.title = String(localized: "Sortie aujourd'hui")
        let disponibilite = String(localized: "Disponible aujourd'hui")
        if let numero = serie.prochaineSortieNumero {
            let tome = String(localized: "Tome \(numero)")
            contenu.body = "\(serie.nomAffiche(langue)) — \(tome) · \(disponibilite)"
        } else {
            contenu.body = "\(serie.nomAffiche(langue)) — \(disponibilite)"
        }
        contenu.sound = .default

        let calendrier = Calendar.current
        let aujourdHui = calendrier.startOfDay(for: Date())
        let jourSortie = calendrier.startOfDay(for: date)
        guard jourSortie >= aujourdHui else { return false }

        var moment = calendrier.date(bySettingHour: 9, minute: 0, second: 0, of: date)
            ?? date
        // Si le rappel est activé le jour même après 9 h, il sonne quelques
        // secondes plus tard au lieu de créer un déclencheur déjà passé.
        if moment <= Date(), jourSortie == aujourdHui {
            moment = Date().addingTimeInterval(5)
        }
        let composants = calendrier.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: moment
        )

        let declencheur = UNCalendarNotificationTrigger(dateMatching: composants, repeats: false)
        let requete = UNNotificationRequest(
            identifier: identifiant,
            content: contenu,
            trigger: declencheur
        )
        do {
            guard generation == generationReconciliation,
                  appartientAuCompteActif(serie), !Task.isCancelled else {
                return false
            }
            try await UNUserNotificationCenter.current().add(requete)
            guard generation == generationReconciliation,
                  appartientAuCompteActif(serie), !Task.isCancelled else {
                UNUserNotificationCenter.current()
                    .removePendingNotificationRequests(withIdentifiers: [identifiant])
                return false
            }
            return true
        } catch {
            annulerRappel(pour: serie)
            return false
        }
    }

    /// Capture tout ce qui est nécessaire tant que l'objet SwiftData est
    /// encore vivant. Une suppression peut ensuite être sauvegardée avant de
    /// toucher au centre de notifications, sans relire un modèle invalidé.
    static func cibleAnnulation(pour serie: Serie) -> CibleAnnulation {
        let identifiantStable = identifiant(pour: serie)
        let identifiants = [identifiantStable, identifiantHistorique(pour: serie)]
        let prefixe = serie.idAniList.map { "\(prefixeRappelSortie)\($0)-" }
        return CibleAnnulation(identifiants: identifiants, prefixeHistorique: prefixe)
    }

    static func annulerRappel(pour serie: Serie) {
        annulerRappel(cibleAnnulation(pour: serie))
    }

    static func annulerRappel(_ cible: CibleAnnulation) {
        let generation = generationReconciliation
        let centre = UNUserNotificationCenter.current()
        centre.removePendingNotificationRequests(withIdentifiers: cible.identifiants)
        centre.removeDeliveredNotifications(withIdentifiers: cible.identifiants)

        // Pour une série AniList, l'identifiant numérique permet aussi de
        // retrouver sans ambiguïté une ancienne variante portant un autre
        // numéro de tome. Pour les autres, l'écran d'édition annule l'ancien
        // identifiant exact avant de modifier le numéro.
        guard let prefixeHistorique = cible.prefixeHistorique else { return }
        centre.getPendingNotificationRequests { requetes in
            Task { @MainActor in
                guard generation == generationReconciliation else { return }
                let identifiants = requetes.lazy
                    .map(\.identifier)
                    .filter { identifiant in
                        !cible.identifiants.contains(identifiant)
                            && identifiant.hasPrefix(prefixeHistorique)
                    }
                centre.removePendingNotificationRequests(
                    withIdentifiers: Array(identifiants)
                )
            }
        }
        centre.getDeliveredNotifications { notifications in
            Task { @MainActor in
                guard generation == generationReconciliation else { return }
                let identifiants = notifications.lazy
                    .map(\.request.identifier)
                    .filter { identifiant in
                        !cible.identifiants.contains(identifiant)
                            && identifiant.hasPrefix(prefixeHistorique)
                    }
                centre.removeDeliveredNotifications(
                    withIdentifiers: Array(identifiants)
                )
            }
        }
    }

    /// Nettoyage global utilisé avant d'effacer la bibliothèque ou le compte.
    /// Il couvre les identifiants actuels et ceux créés par les anciennes versions.
    static func annulerTousLesRappelsSortie() {
        generationReconciliation &+= 1
        let centre = UNUserNotificationCenter.current()
        // Honya ne programme actuellement que des rappels de sortie. Ces deux
        // appels synchrones evitent la course d'une enumeration asynchrone qui
        // pourrait supprimer les nouveaux rappels du compte suivant.
        centre.removeAllPendingNotificationRequests()
        centre.removeAllDeliveredNotifications()
    }

    /// Remonte exactement les rappels appartenant au store SwiftData actif.
    /// En Free, la date la plus proche est conservee ; Honya+ les conserve
    /// toutes. Les dates passees et les requetes d'un ancien compte sont
    /// retirees du modele comme du centre de notifications.
    static func reconcilierRappelsSortie(
        series: [Serie],
        plus: Bool,
        langue: String
    ) async {
        generationReconciliation &+= 1
        let generation = generationReconciliation
        let centre = UNUserNotificationCenter.current()
        centre.removeAllPendingNotificationRequests()
        centre.removeAllDeliveredNotifications()

        await Task.yield()
        guard generation == generationReconciliation, !Task.isCancelled else { return }

        let aujourdHui = Calendar.current.startOfDay(for: Date())
        let candidates = series
            .filter { serie in
                guard serie.rappelActive, let date = serie.prochaineSortieDate else {
                    return false
                }
                return Calendar.current.startOfDay(for: date) >= aujourdHui
            }
            .sorted {
                ($0.prochaineSortieDate ?? .distantFuture)
                    < ($1.prochaineSortieDate ?? .distantFuture)
            }
        let retenues = plus ? candidates : Array(candidates.prefix(Limites.alertesSortie))
        let identifiantsRetenus = Set(retenues.map(ObjectIdentifier.init))

        for serie in series where serie.rappelActive
            && !identifiantsRetenus.contains(ObjectIdentifier(serie)) {
            serie.rappelActive = false
        }
        try? series.first?.modelContext?.save()

        for serie in retenues {
            guard generation == generationReconciliation, !Task.isCancelled else { return }
            let planifie = await planifierRappelSortie(pour: serie, langue: langue)
            guard generation == generationReconciliation, !Task.isCancelled else {
                if planifie { annulerRappel(pour: serie) }
                return
            }
            serie.rappelActive = planifie
        }
        try? series.first?.modelContext?.save()
    }

    private static func identifiantHistorique(pour serie: Serie) -> String {
        "\(prefixeRappelSortie)\(serie.idAniList.map(String.init) ?? serie.nom)-\(serie.prochaineSortieNumero ?? 0)"
    }

    private static func appartientAuCompteActif(_ serie: Serie) -> Bool {
        guard let contexte = serie.modelContext,
              let actif = StockageCompte.partage.conteneurActif?.mainContext
        else { return false }
        return contexte === actif
    }
}

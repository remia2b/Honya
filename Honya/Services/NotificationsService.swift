import Foundation
import UserNotifications

/// Rappels de sorties de tomes (planification locale, le matin du jour J).
enum NotificationsService {

    static func demanderAutorisation() async -> Bool {
        let centre = UNUserNotificationCenter.current()
        return (try? await centre.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func identifiant(pour serie: Serie) -> String {
        "sortie-\(serie.idAniList.map(String.init) ?? serie.nom)-\(serie.prochaineSortieNumero ?? 0)"
    }

    static func planifierRappelSortie(pour serie: Serie, langue: String) async {
        guard let date = serie.prochaineSortieDate else { return }

        let contenu = UNMutableNotificationContent()
        contenu.title = "Sortie aujourd'hui"
        if let numero = serie.prochaineSortieNumero {
            contenu.body = "\(serie.nomAffiche(langue)) — le tome \(numero) sort aujourd'hui."
        } else {
            contenu.body = "\(serie.nomAffiche(langue)) — un nouveau tome sort aujourd'hui."
        }
        contenu.sound = .default

        var composants = Calendar.current.dateComponents([.year, .month, .day], from: date)
        composants.hour = 9

        let declencheur = UNCalendarNotificationTrigger(dateMatching: composants, repeats: false)
        let requete = UNNotificationRequest(
            identifier: identifiant(pour: serie),
            content: contenu,
            trigger: declencheur
        )
        try? await UNUserNotificationCenter.current().add(requete)
    }

    static func annulerRappel(pour serie: Serie) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [identifiant(pour: serie)])
    }
}

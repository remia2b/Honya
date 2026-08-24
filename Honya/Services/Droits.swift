import Foundation
import Observation

/// Ce que ce compte a le droit d'utiliser.
///
/// Aujourd'hui, un simple drapeau : l'écran Honya+ l'active pour la période
/// TestFlight, le temps que les abonnements existent. En v0.27, StoreKit 2
/// remplira `plus` depuis les vrais achats — les vues, elles, ne changeront
/// pas, elles ne connaissent que cette classe.
@Observable
@MainActor
final class Droits {
    static let partage = Droits()

    private(set) var plus: Bool

    private init() {
        plus = UserDefaults.standard.bool(forKey: "honyaPlus")
    }

    /// L'essai TestFlight : un déblocage local, clairement nommé, que la
    /// version App Store remplacera par les achats.
    func activerEssai() {
        plus = true
        UserDefaults.standard.set(true, forKey: "honyaPlus")
    }
}

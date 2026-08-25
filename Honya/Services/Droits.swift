import Foundation
import Observation

/// Ce que ce compte a le droit d'utiliser.
///
/// Les vues ne connaissent que cette classe et son unique drapeau. Elles
/// ignorent d'où il vient — un achat App Store, ou le déblocage local des
/// versions de test — et c'est voulu : le jour où la source change, aucune vue
/// ne bouge.
@Observable
@MainActor
final class Droits {
    static let partage = Droits()

    /// Honya+ est-il ouvert.
    var plus: Bool { achat || essai }

    /// Ce qu'Apple reconnaît. Jamais enregistré sur l'appareil : un abonnement
    /// expire, se résilie, se rembourse. On le redemande à chaque lancement.
    private(set) var achat = false

    /// Le déblocage des versions de test, en attendant que les articles
    /// existent dans App Store Connect. Il disparaîtra à la sortie publique.
    private(set) var essai: Bool

    private init() {
        essai = UserDefaults.standard.bool(forKey: Self.cleEssai)
    }

    private static let cleEssai = "honyaPlus"

    /// Appelé par la boutique, et par elle seule.
    func appliquer(plus actif: Bool) {
        achat = actif
    }

    /// Le déblocage local des versions de test, clairement nommé.
    func activerEssai() {
        essai = true
        UserDefaults.standard.set(true, forKey: Self.cleEssai)
    }

    /// Utile pour revoir les écrans d'abonnement une fois l'essai activé.
    func annulerEssai() {
        essai = false
        UserDefaults.standard.set(false, forKey: Self.cleEssai)
    }
}

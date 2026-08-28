import Foundation
import Observation

/// Ce que ce compte a le droit d'utiliser.
///
/// Les vues ne connaissent que cette classe et son unique drapeau. Elles
/// ignorent d'où il vient. En production, seul un droit vérifié par StoreKit
/// peut ouvrir Honya+. Les aperçus de développement gardent un interrupteur
/// local, compilé hors des versions distribuées.
@Observable
@MainActor
final class Droits {
    static let partage = Droits()

    /// Honya+ est-il ouvert.
    var plus: Bool {
#if DEBUG
        return achat || essai
#else
        return achat
#endif
    }

    /// Ce qu'Apple reconnaît. Jamais enregistré sur l'appareil : un abonnement
    /// expire, se résilie, se rembourse. On le redemande à chaque lancement.
    private(set) var achat = false

    /// Déblocage réservé aux aperçus et tests locaux.
    private(set) var essai: Bool

    private init() {
#if DEBUG
        essai = UserDefaults.standard.bool(forKey: Self.cleEssai)
#else
        essai = false
        // Nettoie les installations TestFlight qui auraient reçu l'ancien
        // déblocage de secours avant sa suppression.
        UserDefaults.standard.removeObject(forKey: Self.cleEssai)
#endif
    }

    private static let cleEssai = "honyaPlus"

    /// Appelé par la boutique, et par elle seule.
    func appliquer(plus actif: Bool) {
        achat = actif
    }

    /// Le déblocage local des versions de test, clairement nommé.
    func activerEssai() {
#if DEBUG
        essai = true
        UserDefaults.standard.set(true, forKey: Self.cleEssai)
#endif
    }

    /// Utile pour revoir les écrans d'abonnement une fois l'essai activé.
    func annulerEssai() {
#if DEBUG
        essai = false
        UserDefaults.standard.set(false, forKey: Self.cleEssai)
#endif
    }
}

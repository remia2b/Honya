import Foundation
import Security

/// Les jetons de session sont des identifiants : ils vont dans le Trousseau,
/// jamais dans les préférences. Chiffrés par le système, jamais sauvegardés
/// vers un autre appareil.
enum Trousseau {
    private static let service = "com.remiabbou.honya.session"

    static func ecrire(_ valeur: String, cle: String) {
        let donnees = Data(valeur.utf8)
        let requete: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: cle,
        ]
        SecItemDelete(requete as CFDictionary)

        var ajout = requete
        ajout[kSecValueData as String] = donnees
        ajout[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(ajout as CFDictionary, nil)
    }

    static func lire(_ cle: String) -> String? {
        let requete: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: cle,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var resultat: CFTypeRef?
        guard SecItemCopyMatching(requete as CFDictionary, &resultat) == errSecSuccess,
              let donnees = resultat as? Data
        else { return nil }
        return String(data: donnees, encoding: .utf8)
    }

    static func effacer(_ cle: String) {
        let requete: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: cle,
        ]
        SecItemDelete(requete as CFDictionary)
    }
}

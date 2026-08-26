import Foundation

/// La session réservée aux catalogues.
///
/// `URLSession.shared` attend soixante secondes avant d'abandonner. C'est le
/// bon réglage pour un téléversement, le pire pour une recherche : un serveur
/// muet — quota épuisé, panne, réseau capricieux — figeait le scanner une
/// minute entière sur un livre déjà sous les yeux du lecteur. Un catalogue
/// répond en moins d'une seconde ou ne répond pas ; six secondes sont déjà
/// une politesse.
enum Reseau {
    static let catalogues: URLSession = {
        let reglages = URLSessionConfiguration.default
        reglages.timeoutIntervalForRequest = 6
        reglages.timeoutIntervalForResource = 10
        // Sans réseau, on le dit tout de suite au lieu d'attendre qu'il
        // revienne : le lecteur préfère « introuvable » à un écran qui tourne.
        reglages.waitsForConnectivity = false
        // Scanner deux fois le même rayon ne doit pas repayer le trajet.
        reglages.requestCachePolicy = .returnCacheDataElseLoad
        reglages.httpMaximumConnectionsPerHost = 6
        return URLSession(configuration: reglages)
    }()
}

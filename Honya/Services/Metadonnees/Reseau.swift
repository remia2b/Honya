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
        // Le plafond total : il doit rester au-dessus du délai que les
        // bibliothèques nationales s'accordent, sinon il les coupe en plein
        // vol sans que leur propre réglage serve à rien.
        reglages.timeoutIntervalForResource = 20
        // Sans réseau, on le dit tout de suite au lieu d'attendre qu'il
        // revienne : le lecteur préfère « introuvable » à un écran qui tourne.
        reglages.waitsForConnectivity = false
        // Une absence vieille de plusieurs semaines ne doit jamais condamner
        // un livre qui vient d'entrer au catalogue. On revalide le cache auprès
        // du fournisseur (ETag/Last-Modified) au lieu de resservir une réponse
        // périmée indéfiniment.
        reglages.requestCachePolicy = .reloadRevalidatingCacheData
        // Open Library et les bibliothèques demandent aux applications de
        // s'identifier ; cela évite aussi que les appels anonymes soient pris
        // pour du trafic automatisé indésirable.
        reglages.httpAdditionalHeaders = [
            // Open Library accorde son plafond identifié uniquement à un
            // nom d'application accompagné d'un vrai contact joignable.
            "User-Agent": "Honya/1.0 (contact@honya.app)",
            "From": "contact@honya.app",
        ]
        reglages.httpMaximumConnectionsPerHost = 6
        return URLSession(configuration: reglages)
    }()
}

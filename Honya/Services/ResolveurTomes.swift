import Foundation
import SwiftData

/// Chaque tome est un livre à part entière : ce résolveur va chercher, à la
/// demande, l'édition locale du tome — sa couverture (Kana, Glénat… pour un
/// lecteur français), son titre exact, ses pages et son ISBN.
///
/// L'appel se fait au moment où le tome apparaît à l'écran, une seule fois :
/// le résultat est stocké dans le modèle, donc disponible hors ligne ensuite.
@MainActor
enum ResolveurTomes {

    /// Tomes déjà tentés dans cette session (évite de marteler l'API si
    /// aucune édition n'existe pour ce tome).
    private static var tentes: Set<PersistentIdentifier> = []

    static func completer(_ tome: Tome, de serie: Serie, langue: String) async {
        guard tome.couvertureURL == nil,
              !tentes.contains(tome.persistentModelID) else { return }
        tentes.insert(tome.persistentModelID)

        let nom = serie.nomAffiche(langue)
        let resultats = await AgregateurMetadonnees.partage
            .rechercherLivres("\(nom) \(tome.numero)", langue: langue)

        // Le bon candidat : une couverture, un titre qui cite la série,
        // et idéalement le numéro du tome.
        let numero = String(tome.numero)
        let candidat = resultats.first {
            $0.couvertureURL != nil
                && TexteUtil.contient([$0.titre], nom)
                && $0.titre.contains(numero)
        } ?? resultats.first {
            $0.couvertureURL != nil && TexteUtil.contient([$0.titre], nom)
        }

        guard let candidat else { return }
        tome.couvertureURL = candidat.couvertureURL
        if tome.titre == nil { tome.titre = candidat.titre }
        if tome.pages == nil { tome.pages = candidat.pages }
        if tome.isbn == nil { tome.isbn = candidat.isbn }
    }
}

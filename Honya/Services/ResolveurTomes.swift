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

        // Le nom de série NETTOYÉ : chercher « Kagurabachi 3 », jamais
        // « Kagurabachi, Vol. 1 3 » — c'est ce qui collait la couverture du
        // tome 1 sur tous les tomes.
        let base = Tomaison.decomposer(serie.nomAffiche(langue)).base

        var candidat: ResultatRecherche?
        for requete in ["\(base) T\(tome.numero)", "\(base) \(tome.numero)"] {
            let resultats = await AgregateurMetadonnees.partage
                .rechercherLivres(requete, langue: langue)
            // Correspondance STRICTE : même série ET même numéro de tome.
            candidat = resultats.first { resultat in
                guard resultat.couvertureURL != nil else { return false }
                let (candidatBase, candidatNumero) = Tomaison.decomposer(resultat.titre)
                return candidatNumero == tome.numero
                    && Tomaison.memeSerie(candidatBase, base)
            }
            if candidat != nil { break }
        }

        guard let candidat else { return }
        tome.couvertureURL = candidat.couvertureURL
        if tome.titre == nil { tome.titre = candidat.titre }
        if tome.pages == nil { tome.pages = candidat.pages }
        if tome.isbn == nil { tome.isbn = candidat.isbn }
        // Le tome 1 peut offrir sa couverture à la série.
        if tome.numero == 1, serie.couvertureLocaleURL == nil {
            serie.couvertureLocaleURL = candidat.couvertureURL
        }
    }
}

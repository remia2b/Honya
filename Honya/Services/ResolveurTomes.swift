import Foundation
import SwiftData

/// Complète les tomes affichés à l'écran. Stratégie en deux temps :
/// 1. La PASSE SÉRIE — une seule requête au catalogue Apple Books du pays
///    remplit d'un coup toutes les couvertures de la série (EditionsLocales).
/// 2. Pour les tomes encore vides (absents du catalogue local), un repli
///    individuel via Google Books, strict et espacé.
@MainActor
enum ResolveurTomes {

    private static var seriesTraitees = Set<PersistentIdentifier>()
    private static var tomesTentes = Set<PersistentIdentifier>()
    private static var prochainDepart = Date.distantPast

    /// Permet de tout retenter (après « Actualiser les informations »).
    static func reinitialiser(_ serie: Serie) {
        seriesTraitees.remove(serie.persistentModelID)
        for tome in serie.tomes {
            tomesTentes.remove(tome.persistentModelID)
        }
    }

    static func completer(_ tome: Tome, de serie: Serie, langue: String) async {
        // 1) Une seule fois par série : la passe catalogue qui remplit tout.
        if !seriesTraitees.contains(serie.persistentModelID) {
            seriesTraitees.insert(serie.persistentModelID)
            await EditionsLocales.rafraichirSerieComplete(serie, langue: langue)
        }

        // 2) Ce tome est-il encore vide ? Repli individuel prudent.
        guard tome.couvertureURL == nil,
              !tomesTentes.contains(tome.persistentModelID) else { return }
        tomesTentes.insert(tome.persistentModelID)

        // Espacement : jamais de rafale sur les API.
        let depart = max(prochainDepart, Date())
        prochainDepart = depart.addingTimeInterval(1.2)
        let attente = depart.timeIntervalSinceNow
        if attente > 0 {
            try? await Task.sleep(for: .seconds(attente))
        }

        let base = Tomaison.decomposer(serie.nomAffiche(langue)).base

        var candidat: ResultatRecherche?
        for requete in ["\(base) T\(tome.numero)", "\(base) \(tome.numero)"] {
            let resultats = await AgregateurMetadonnees.partage
                .rechercherLivres(requete, langue: langue)
            // Correspondance STRICTE : même série ET même numéro — et parmi
            // les éditions valables, celle de la langue du lecteur d'abord.
            let valables = resultats.filter { resultat in
                guard resultat.couvertureURL != nil else { return false }
                let (candidatBase, candidatNumero) = Tomaison.decomposer(resultat.titre)
                return candidatNumero == tome.numero
                    && Tomaison.memeSerie(candidatBase, base)
            }
            candidat = valables.first { $0.langue == langue } ?? valables.first
            if candidat != nil { break }
        }

        guard let candidat else {
            // Aucun résultat ? Probable quota : on redonnera sa chance plus tard.
            tomesTentes.remove(tome.persistentModelID)
            return
        }
        tome.couvertureURL = candidat.couvertureURL
        if tome.titre == nil { tome.titre = candidat.titre }
        if tome.pages == nil { tome.pages = candidat.pages }
        if tome.isbn == nil { tome.isbn = candidat.isbn }
    }
}

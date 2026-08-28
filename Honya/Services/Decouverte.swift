import Foundation

/// L'étal du libraire : rayons thématiques issus des sources autorisées et,
/// uniquement si son parcours promotionnel a été déclaré conforme, classements
/// Apple. Tout arrive dans la langue du lecteur, comme le reste de l'app.
@MainActor
enum Decouverte {

    // MARK: - Classements (flux RSS Apple, instantanés)

    /// Le top des livres du pays — payants ou gratuits.
    ///
    /// Le flux RSS Apple ne déclare pas la langue de chaque édition. Un
    /// storefront français contient aussi des titres anglais ; l'assimiler à
    /// `fr` briserait la garantie titre/couverture locale. Les classements
    /// restent donc vides jusqu'à une source sous licence qui expose cette
    /// donnée édition par édition.
    static func classement(gratuits: Bool, langue: String) async -> [ResultatRecherche] {
        _ = gratuits
        _ = langue
        return []
    }

    // MARK: - Rayons thématiques (recherche catalogue)

    /// Les résultats bruts d'un rayon — mêmes requêtes que la recherche, donc
    /// même cache et même file d'attente.
    static func rayonBrut(_ terme: String, langue: String) async -> [ResultatRecherche] {
        await AgregateurMetadonnees.partage.rechercherLivres(terme, langue: langue)
    }

    /// Un rayon présentable : un seul représentant par série (pas dix tomes du
    /// même titre), couverture obligatoire.
    static func parSerie(_ resultats: [ResultatRecherche]) -> [ResultatRecherche] {
        var vues = Set<String>()
        return resultats.filter { resultat in
            guard resultat.couvertureURL != nil else { return false }
            let base = TexteUtil.normaliser(Tomaison.decomposer(resultat.titre).base)
            guard !base.isEmpty else { return false }
            return vues.insert(base).inserted
        }
    }

    /// Les parutions à venir parmi des résultats déjà chargés (précommandes).
    static func aParaitre(_ resultats: [ResultatRecherche]) -> [ResultatRecherche] {
        resultats
            .filter {
                $0.couvertureURL != nil
                    && $0.dateSortie.map { DateCivile.estAVenir($0) } == true
            }
            .sorted { ($0.dateSortie ?? .distantFuture) < ($1.dateSortie ?? .distantFuture) }
    }

}

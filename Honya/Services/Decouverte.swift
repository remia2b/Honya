import Foundation

/// L'étal du libraire : les classements réels du catalogue Apple Books du pays
/// (flux RSS marketing — hors quota de l'iTunes Search API) et des rayons
/// thématiques servis par la recherche catalogue habituelle (cache + file
/// d'attente). Tout arrive dans la langue du lecteur, comme le reste de l'app.
@MainActor
enum Decouverte {

    // MARK: - Classements (flux RSS Apple, instantanés)

    /// Le top des livres du pays — payants ou gratuits.
    static func classement(gratuits: Bool, langue: String) async -> [ResultatRecherche] {
        let cle = "rss|\(gratuits ? "free" : "paid")|\(langue)"
        if let connu = cacheRSS[cle] { return connu }

        let pays = Langues.storefront(pourLangue: langue).lowercased()
        let flux = gratuits ? "top-free" : "top-paid"
        guard let url = URL(
            string: "https://rss.applemarketingtools.com/api/v2/\(pays)/books/\(flux)/40/books.json"
        ) else { return [] }

        guard let (donnees, _) = try? await URLSession.shared.data(from: url),
              let reponse = try? JSONDecoder().decode(ReponseRSS.self, from: donnees)
        else { return [] }

        let resultats = (reponse.feed?.results ?? []).compactMap { $0.enResultat(langue: langue) }
        if !resultats.isEmpty { cacheRSS[cle] = resultats }
        return resultats
    }

    private static var cacheRSS: [String: [ResultatRecherche]] = [:]

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
            .filter { $0.couvertureURL != nil && ($0.dateSortie ?? .distantPast) > Date() }
            .sorted { ($0.dateSortie ?? .distantFuture) < ($1.dateSortie ?? .distantFuture) }
    }

    // MARK: - Décodage du flux RSS

    private struct ReponseRSS: Decodable {
        let feed: Flux?

        struct Flux: Decodable {
            let results: [Entree]?
        }

        struct Entree: Decodable {
            let id: String?
            let name: String?
            let artistName: String?
            let artworkUrl100: String?
            let genres: [Genre]?

            struct Genre: Decodable {
                let name: String?
            }

            func enResultat(langue: String) -> ResultatRecherche? {
                guard let name, !name.isEmpty else { return nil }
                var resultat = ResultatRecherche(
                    id: "applebooks:\(id ?? name)",
                    titre: name,
                    source: "Apple Books"
                )
                if let artistName, !artistName.isEmpty {
                    resultat.auteurs = [artistName]
                }
                // Le flux du pays = l'édition locale, comme le storefront.
                resultat.langue = langue
                resultat.couvertureURL = artworkUrl100.map { ArtworkApple.nette($0) }

                let noms = (genres ?? []).compactMap(\.name)
                    .filter { $0 != "Livres" && $0 != "Books" }
                resultat.genres = noms
                let tous = noms.joined(separator: " ").lowercased()
                if tous.contains("manga") {
                    resultat.type = .manga
                } else if tous.contains("bd") || tous.contains("comic")
                    || tous.contains("graphic") {
                    resultat.type = .bd
                }
                return resultat
            }
        }
    }
}

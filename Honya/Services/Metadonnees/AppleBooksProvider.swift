import Foundation

/// La source primaire de Honya : le catalogue d'Apple Books lui-même, via
/// l'iTunes Search API (officielle, publique, par pays). Un lecteur français
/// reçoit les éditions Kana/Glénat, un américain les VIZ — exactement ce que
/// montre l'app Apple Books de son iPhone : couvertures HD, descriptions
/// localisées, tri d'Apple.
///
/// Contrainte assumée : ~20 requêtes/minute. La conception la neutralise :
/// UNE requête ramène toute une série, tout est mis en cache puis persisté,
/// et la file d'attente globale espace les appels.
struct AppleBooksProvider: Sendable {

    func rechercher(
        _ requete: String,
        pays: String,
        langue: String,
        // 200 est le maximum d'iTunes, et il en faut : sur une longue série,
        // cinquante résultats partent en éditions étrangères et hors-séries
        // avant qu'on ait vu tous les tomes. Même requête, même coût.
        limite: Int = 200
    ) async throws -> [ResultatRecherche] {
        var composants = URLComponents(string: "https://itunes.apple.com/search")!
        composants.queryItems = [
            URLQueryItem(name: "term", value: requete),
            URLQueryItem(name: "country", value: pays),
            URLQueryItem(name: "media", value: "ebook"),
            URLQueryItem(name: "limit", value: String(limite)),
        ]
        guard let url = composants.url else { return [] }

        guard await FileAttenteApple.partage.attendre() else { return [] }
        let (donnees, _) = try await Reseau.catalogues.data(from: url)
        let reponse = try JSONDecoder().decode(Reponse.self, from: donnees)
        return (reponse.results ?? []).compactMap { $0.enResultat() }
    }

    /// Recherche par ISBN dans le catalogue du pays (les ebooks seulement).
    ///
    /// `lookup` est la seule porte utilisée ici : elle garantit que la réponse
    /// est rattachée à l'identifiant demandé. Une recherche libre du nombre
    /// pouvait renvoyer un ebook voisin puis lui attribuer à tort l'ISBN papier.
    func parISBN(_ isbn: String, pays: String, langue: String) async -> ResultatRecherche? {
        guard let propre = ISBNUtil.canonique(isbn),
              var trouve = await parIdentifiant(propre, pays: pays, langue: langue)
        else { return nil }
        trouve.isbn = propre
        return trouve
    }

    private func parIdentifiant(
        _ isbn: String, pays: String, langue: String
    ) async -> ResultatRecherche? {
        var composants = URLComponents(string: "https://itunes.apple.com/lookup")!
        composants.queryItems = [
            URLQueryItem(name: "isbn", value: isbn),
            URLQueryItem(name: "country", value: pays),
        ]
        guard let url = composants.url else { return nil }

        guard await FileAttenteApple.partage.attendre() else { return nil }
        guard let (donnees, _) = try? await Reseau.catalogues.data(from: url),
              let reponse = try? JSONDecoder().decode(Reponse.self, from: donnees)
        else { return nil }
        return (reponse.results ?? []).first?.enResultat()
    }

    // MARK: - Décodage

    private struct Reponse: Decodable {
        let results: [Element]?
    }

    private struct Element: Decodable {
        let trackId: Int?
        let trackName: String?
        let artistName: String?
        let artworkUrl100: String?
        let description: String?
        let releaseDate: String?
        let genres: [String]?

        func enResultat() -> ResultatRecherche? {
            guard let titre = trackName, !titre.isEmpty else { return nil }

            var resultat = ResultatRecherche(
                id: "applebooks:\(trackId.map(String.init) ?? titre)",
                titre: titre,
                source: "Apple Books"
            )
            if let artistName, !artistName.isEmpty {
                resultat.auteurs = [artistName]
            }
            // L'API garantit un storefront, pas la langue de chaque livre.
            // Un résultat du store français peut être anglais : on ne lui
            // attribue donc jamais la langue demandée sans donnée explicite.
            resultat.resume = description.map(TexteUtil.sansHTML)
            resultat.annee = TexteUtil.annee(releaseDate)
            if let releaseDate {
                resultat.dateSortie = DateCivile.depuisISO(releaseDate)
            }
            resultat.couvertureURL = artworkUrl100.map(Self.hauteResolution)

            let genresUtiles = (genres ?? []).filter { $0 != "Livres" && $0 != "Books" }
            resultat.genres = genresUtiles
            let tousGenres = genresUtiles.joined(separator: " ").lowercased()
            if tousGenres.contains("manga") {
                resultat.type = .manga
            } else if tousGenres.contains("bd") || tousGenres.contains("comic")
                || tousGenres.contains("graphic") {
                resultat.type = .bd
            }
            return resultat
        }

        /// Les vignettes mzstatic acceptent la taille demandée dans l'URL.
        private static func hauteResolution(_ url: String) -> String {
            ArtworkApple.nette(url)
        }
    }
}

/// Espacement global des appels au catalogue Apple (~20/minute autorisées) :
/// 3,2 s entre deux requêtes, pour ne jamais être rationné.
actor FileAttenteApple {
    static let partage = FileAttenteApple()

    /// Vingt appels par minute, avec un seul départ immédiat. Une capacité de
    /// huit autorisait en pratique 27 appels dans la première minute ; Apple
    /// documente une limite d'environ vingt, rafale comprise.
    private static let capacite = 1.0
    private static let parSeconde = 20.0 / 60.0

    private var jetons = capacite
    private var derniereMesure = Date()

    /// `false` signifie que la recherche a été remplacée pendant son
    /// attente. Sans ce test, `Task.sleep` annulé échouait immédiatement et
    /// la boucle tournait à vide jusqu'au prochain jeton.
    func attendre() async -> Bool {
        while true {
            guard !Task.isCancelled else { return false }
            recharger()
            if jetons >= 1 {
                jetons -= 1
                return true
            }
            // Le temps qu'il manque pour qu'un jeton retombe dans le seau.
            let manque = (1 - jetons) / Self.parSeconde
            do {
                try await Task.sleep(for: .seconds(min(manque, 3)))
            } catch {
                return false
            }
        }
    }

    private func recharger() {
        let maintenant = Date()
        let ecoule = maintenant.timeIntervalSince(derniereMesure)
        jetons = min(Self.capacite, jetons + ecoule * Self.parSeconde)
        derniereMesure = maintenant
    }
}

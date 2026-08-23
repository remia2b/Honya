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
        limite: Int = 50
    ) async throws -> [ResultatRecherche] {
        var composants = URLComponents(string: "https://itunes.apple.com/search")!
        composants.queryItems = [
            URLQueryItem(name: "term", value: requete),
            URLQueryItem(name: "country", value: pays),
            URLQueryItem(name: "media", value: "ebook"),
            URLQueryItem(name: "limit", value: String(limite)),
        ]
        guard let url = composants.url else { return [] }

        await FileAttenteApple.partage.attendre()
        let (donnees, _) = try await URLSession.shared.data(from: url)
        let reponse = try JSONDecoder().decode(Reponse.self, from: donnees)
        return (reponse.results ?? []).compactMap { $0.enResultat(langue: langue) }
    }

    /// Recherche par ISBN dans le catalogue du pays (les ebooks seulement).
    func parISBN(_ isbn: String, pays: String, langue: String) async -> ResultatRecherche? {
        var composants = URLComponents(string: "https://itunes.apple.com/lookup")!
        composants.queryItems = [
            URLQueryItem(name: "isbn", value: ISBNUtil.normaliser(isbn)),
            URLQueryItem(name: "country", value: pays),
        ]
        guard let url = composants.url else { return nil }

        await FileAttenteApple.partage.attendre()
        guard let (donnees, _) = try? await URLSession.shared.data(from: url),
              let reponse = try? JSONDecoder().decode(Reponse.self, from: donnees)
        else { return nil }
        return (reponse.results ?? []).first?.enResultat(langue: langue)
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

        func enResultat(langue: String) -> ResultatRecherche? {
            guard let titre = trackName, !titre.isEmpty else { return nil }

            var resultat = ResultatRecherche(
                id: "applebooks:\(trackId.map(String.init) ?? titre)",
                titre: titre,
                source: "Apple Books"
            )
            if let artistName, !artistName.isEmpty {
                resultat.auteurs = [artistName]
            }
            // Le storefront EST l'édition locale : ces résultats sont dans la
            // langue du pays du lecteur.
            resultat.langue = langue
            resultat.resume = description.map(TexteUtil.sansHTML)
            resultat.annee = TexteUtil.annee(releaseDate)
            if let releaseDate {
                resultat.dateSortie = ISO8601DateFormatter().date(from: releaseDate)
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

        /// Les vignettes mzstatic acceptent la taille dans l'URL : 100 → 600 px.
        private static func hauteResolution(_ url: String) -> String {
            url.replacingOccurrences(of: "100x100", with: "600x600")
        }
    }
}

/// Espacement global des appels au catalogue Apple (~20/minute autorisées) :
/// 3,2 s entre deux requêtes, pour ne jamais être rationné.
actor FileAttenteApple {
    static let partage = FileAttenteApple()
    private var prochainDepart = Date.distantPast

    func attendre() async {
        let depart = max(prochainDepart, Date())
        prochainDepart = depart.addingTimeInterval(3.2)
        let attente = depart.timeIntervalSinceNow
        if attente > 0 {
            try? await Task.sleep(for: .seconds(attente))
        }
    }
}

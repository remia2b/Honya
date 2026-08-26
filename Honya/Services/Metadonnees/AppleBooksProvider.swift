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

        await FileAttenteApple.partage.attendre()
        let (donnees, _) = try await Reseau.catalogues.data(from: url)
        let reponse = try JSONDecoder().decode(Reponse.self, from: donnees)
        return (reponse.results ?? []).compactMap { $0.enResultat(langue: langue) }
    }

    /// Recherche par ISBN dans le catalogue du pays (les ebooks seulement).
    ///
    /// Deux portes, car elles ne mènent pas au même index : `lookup` interroge
    /// la table des identifiants, la recherche interroge le catalogue. Des
    /// éditions absentes de la première se trouvent dans la seconde. Un
    /// code-barres inconnu n'y ramène rien — vérifié — donc la seconde porte
    /// n'invente jamais de livre.
    func parISBN(_ isbn: String, pays: String, langue: String) async -> ResultatRecherche? {
        let propre = ISBNUtil.normaliser(isbn)
        if let trouve = await parIdentifiant(propre, pays: pays, langue: langue) {
            return trouve
        }
        return (try? await rechercher(propre, pays: pays, langue: langue, limite: 3))?.first
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

        await FileAttenteApple.partage.attendre()
        guard let (donnees, _) = try? await Reseau.catalogues.data(from: url),
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

    /// Vingt appels par minute — mais pas un toutes les trois secondes.
    ///
    /// L'espacement rigide faisait payer trois secondes pleines au lecteur qui
    /// scanne UN livre : la fiche partait aussitôt, puis la recherche de
    /// couverture attendait son tour derrière elle. Or iTunes accepte très
    /// bien une rafale tant que la moyenne tient. Le seau de jetons rend la
    /// première poignée d'appels immédiate et ne fait patienter que celui qui
    /// balaye une étagère entière — exactement l'inverse de ce qu'on avait.
    private static let capacite = 8.0
    private static let parSeconde = 20.0 / 60.0

    private var jetons = capacite
    private var derniereMesure = Date()

    func attendre() async {
        while true {
            recharger()
            if jetons >= 1 {
                jetons -= 1
                return
            }
            // Le temps qu'il manque pour qu'un jeton retombe dans le seau.
            let manque = (1 - jetons) / Self.parSeconde
            try? await Task.sleep(for: .seconds(min(manque, 3)))
        }
    }

    private func recharger() {
        let maintenant = Date()
        let ecoule = maintenant.timeIntervalSince(derniereMesure)
        jetons = min(Self.capacite, jetons + ecoule * Self.parSeconde)
        derniereMesure = maintenant
    }
}

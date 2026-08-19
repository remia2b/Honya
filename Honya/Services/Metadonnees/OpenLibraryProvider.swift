import Foundation

/// Repli ouvert et sans clé : catalogue Internet Archive,
/// couvertures directes par identifiant (covers.openlibrary.org).
struct OpenLibraryProvider: MetadataProvider {

    func rechercher(_ requete: String, langue: String?) async throws -> [ResultatRecherche] {
        var composants = URLComponents(string: "https://openlibrary.org/search.json")!
        var parametres = [
            URLQueryItem(name: "q", value: requete),
            URLQueryItem(name: "limit", value: "20"),
            URLQueryItem(
                name: "fields",
                value: "key,title,author_name,first_publish_year,cover_i,number_of_pages_median,language"
            ),
        ]
        if let langue, let marc = Self.versMARC[langue] {
            parametres.append(URLQueryItem(name: "lang", value: marc))
        }
        composants.queryItems = parametres
        guard let url = composants.url else { return [] }

        let (donnees, _) = try await URLSession.shared.data(from: url)
        let reponse = try JSONDecoder().decode(ReponseRecherche.self, from: donnees)
        return (reponse.docs ?? []).compactMap { $0.enResultat() }
    }

    func parISBN(_ isbn: String) async throws -> ResultatRecherche? {
        let propre = ISBNUtil.normaliser(isbn)
        guard let url = URL(string: "https://openlibrary.org/isbn/\(propre).json") else { return nil }
        let (donnees, reponseHTTP) = try await URLSession.shared.data(from: url)
        guard (reponseHTTP as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let edition = try JSONDecoder().decode(Edition.self, from: donnees)
        guard let titre = edition.title else { return nil }

        var resultat = ResultatRecherche(
            id: "openlibrary:\(propre)",
            titre: titre,
            source: "Open Library"
        )
        resultat.pages = edition.number_of_pages
        resultat.isbn = propre
        resultat.langue = ISBNUtil.langueProbable(propre)
        if let coverId = edition.covers?.first {
            resultat.couvertureURL = "https://covers.openlibrary.org/b/id/\(coverId)-L.jpg"
        } else {
            resultat.couvertureURL = "https://covers.openlibrary.org/b/isbn/\(propre)-L.jpg"
        }
        if let langue = resultat.langue {
            resultat.titresParLangue[langue] = titre
        }
        return resultat
    }

    /// Codes MARC utilisés par Open Library.
    private static let versMARC: [String: String] = [
        "fr": "fre", "en": "eng", "de": "ger", "ja": "jpn",
        "es": "spa", "it": "ita", "pt": "por", "ru": "rus", "zh": "chi",
    ]

    private static let depuisMARC: [String: String] = [
        "fre": "fr", "eng": "en", "ger": "de", "deu": "de", "jpn": "ja",
        "spa": "es", "ita": "it", "por": "pt", "rus": "ru", "chi": "zh",
    ]

    // MARK: - Décodage

    private struct ReponseRecherche: Decodable {
        let docs: [Doc]?
    }

    private struct Doc: Decodable {
        let key: String?
        let title: String?
        let author_name: [String]?
        let first_publish_year: Int?
        let cover_i: Int?
        let number_of_pages_median: Int?
        let language: [String]?

        func enResultat() -> ResultatRecherche? {
            guard let titre = title, !titre.isEmpty else { return nil }
            var resultat = ResultatRecherche(
                id: "openlibrary:\(key ?? titre)",
                titre: titre,
                source: "Open Library"
            )
            resultat.auteurs = author_name ?? []
            resultat.annee = first_publish_year
            resultat.pages = number_of_pages_median
            if let coverId = cover_i {
                resultat.couvertureURL = "https://covers.openlibrary.org/b/id/\(coverId)-L.jpg"
            }
            if let marc = language?.first {
                resultat.langue = OpenLibraryProvider.depuisMARC[marc]
            }
            return resultat
        }
    }

    private struct Edition: Decodable {
        let title: String?
        let number_of_pages: Int?
        let covers: [Int]?
    }
}

import Foundation

/// Source principale pour les livres : bonne couverture générale, bon français,
/// paramètre `langRestrict` pour chercher dans la langue de l'utilisateur.
struct GoogleBooksProvider: MetadataProvider {
    /// Clé API Google Books, saisie dans les réglages. Sans elle, Google rationne
    /// sévèrement les requêtes anonymes : les recherches retombent alors sur
    /// Open Library, bien plus pauvre en éditions françaises.
    var cleAPI: String? {
        let cle = UserDefaults.standard.string(forKey: "cleGoogleBooks")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (cle?.isEmpty ?? true) ? nil : cle
    }

    func rechercher(_ requete: String, langue: String?) async throws -> [ResultatRecherche] {
        var composants = URLComponents(string: "https://www.googleapis.com/books/v1/volumes")!
        var parametres = [
            URLQueryItem(name: "q", value: requete),
            URLQueryItem(name: "maxResults", value: "20"),
            URLQueryItem(name: "printType", value: "books"),
        ]
        if let langue {
            parametres.append(URLQueryItem(name: "langRestrict", value: langue))
        }
        if let cleAPI {
            parametres.append(URLQueryItem(name: "key", value: cleAPI))
        }
        composants.queryItems = parametres
        guard let url = composants.url else { return [] }

        let (donnees, _) = try await URLSession.shared.data(from: url)
        let reponse = try JSONDecoder().decode(ReponseVolumes.self, from: donnees)
        return (reponse.items ?? []).compactMap { $0.enResultat() }
    }

    func parISBN(_ isbn: String) async throws -> ResultatRecherche? {
        try await rechercher("isbn:\(ISBNUtil.normaliser(isbn))", langue: nil).first
    }
}

// MARK: - Décodage

private struct ReponseVolumes: Decodable {
    let items: [Volume]?
}

private struct Volume: Decodable {
    let id: String
    let volumeInfo: Info

    struct Info: Decodable {
        let title: String?
        let authors: [String]?
        let publishedDate: String?
        let description: String?
        let pageCount: Int?
        let categories: [String]?
        let language: String?
        let imageLinks: Images?
        let industryIdentifiers: [Identifiant]?

        struct Images: Decodable {
            let thumbnail: String?
            let smallThumbnail: String?
        }

        struct Identifiant: Decodable {
            let type: String?
            let identifier: String?
        }
    }

    func enResultat() -> ResultatRecherche? {
        guard let titre = volumeInfo.title, !titre.isEmpty else { return nil }

        let isbn13 = volumeInfo.industryIdentifiers?
            .first(where: { $0.type == "ISBN_13" })?.identifier
        let categories = volumeInfo.categories ?? []
        let estBD = categories.contains { $0.localizedCaseInsensitiveContains("comic") || $0.localizedCaseInsensitiveContains("graphic") }

        var resultat = ResultatRecherche(
            id: "google:\(id)",
            titre: titre,
            source: "Google Books"
        )
        resultat.auteurs = volumeInfo.authors ?? []
        resultat.type = estBD ? .bd : .livre
        resultat.resume = volumeInfo.description
        resultat.pages = volumeInfo.pageCount
        resultat.annee = TexteUtil.annee(volumeInfo.publishedDate)
        resultat.genres = categories
        resultat.couvertureURL = volumeInfo.imageLinks?.thumbnail ?? volumeInfo.imageLinks?.smallThumbnail
        resultat.isbn = isbn13
        resultat.langue = volumeInfo.language
        if let langue = volumeInfo.language {
            resultat.titresParLangue[langue] = titre
        }
        return resultat
    }
}

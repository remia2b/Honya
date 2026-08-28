import Foundation

/// Source principale pour les livres : bonne couverture générale, bon français,
/// paramètre `langRestrict` pour chercher dans la langue de l'utilisateur.
struct GoogleBooksProvider: MetadataProvider {
    /// Clé API Google Books, injectée par la CI au moment du build (jamais dans
    /// le dépôt ni dans l'interface). Sans elle, Google rationne les requêtes
    /// anonymes et les recherches retombent sur Open Library.
    var cleAPI: String? {
        Secrets.cleGoogleBooks.isEmpty ? nil : Secrets.cleGoogleBooks
    }

    func rechercher(_ requete: String, langue: String?) async throws -> [ResultatRecherche] {
        let reponse = try await rechercherPage(
            requete, langue: langue, depart: 0
        )
        return (reponse.items ?? []).compactMap { $0.enResultat() }
    }

    /// Une grille de série ne peut pas s'arrêter aux 40 premiers résultats.
    /// Google documente `startIndex` pour parcourir la collection : on continue
    /// tant qu'une page est pleine, avec une borne de sécurité à 200 notices.
    /// Une série courte ne paie donc toujours qu'une requête.
    func rechercherSerie(
        _ requete: String, langue: String?
    ) async throws -> [ResultatRecherche] {
        let taille = 40
        let plafond = 200
        var depart = 0
        var resultats: [ResultatRecherche] = []

        while depart < plafond {
            try Task.checkCancellation()
            let reponse = try await rechercherPage(
                requete, langue: langue, depart: depart
            )
            let volumes = reponse.items ?? []
            resultats.append(contentsOf: volumes.compactMap { $0.enResultat() })

            depart += taille
            let total = min(reponse.totalItems ?? depart, plafond)
            if volumes.count < taille || depart >= total { break }
        }
        return resultats
    }

    private func rechercherPage(
        _ texte: String, langue: String?, depart: Int
    ) async throws -> ReponseVolumes {
        var composants = URLComponents(string: "https://www.googleapis.com/books/v1/volumes")!
        var parametres = [
            URLQueryItem(name: "q", value: texte),
            // Le maximum accepté par Google. Cette source ne sert qu'en secours,
            // mais elle sert alors pour des séries entières.
            URLQueryItem(name: "maxResults", value: "40"),
            URLQueryItem(name: "startIndex", value: String(depart)),
            URLQueryItem(name: "printType", value: "books"),
            // Les fiches de précommande alimentent les prochaines sorties.
            URLQueryItem(name: "showPreorders", value: "true"),
        ]
        if let langue {
            parametres.append(URLQueryItem(name: "langRestrict", value: langue))
        }
        if let cleAPI {
            parametres.append(URLQueryItem(name: "key", value: cleAPI))
        }
        composants.queryItems = parametres
        guard let url = composants.url else {
            return ReponseVolumes(totalItems: 0, items: [])
        }

        // La clé est restreinte à l'app iOS côté Google : cet en-tête prouve
        // que l'appel vient bien de Honya (une clé volée ne sert à rien ailleurs).
        var demande = URLRequest(url: url)
        if let bundle = Bundle.main.bundleIdentifier {
            demande.setValue(bundle, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        }
        let (donnees, _) = try await Reseau.catalogues.data(for: demande)
        return try JSONDecoder().decode(ReponseVolumes.self, from: donnees)
    }

    func parISBN(_ isbn: String) async throws -> ResultatRecherche? {
        guard let propre = ISBNUtil.canonique(isbn) else { return nil }
        let resultats = try await rechercher("isbn:\(propre)", langue: nil)
        return resultats.first {
            guard let isbnTrouve = $0.isbn else { return false }
            return ISBNUtil.canonique(isbnTrouve) == propre
        }
    }
}

// MARK: - Décodage

private struct ReponseVolumes: Decodable {
    let totalItems: Int?
    let items: [Volume]?
}

private struct Volume: Decodable {
    let id: String
    let volumeInfo: Info

    struct Info: Decodable {
        let title: String?
        let subtitle: String?
        let authors: [String]?
        let publishedDate: String?
        let description: String?
        let pageCount: Int?
        let categories: [String]?
        let language: String?
        let imageLinks: Images?
        let industryIdentifiers: [Identifiant]?

        struct Images: Decodable {
            let smallThumbnail: String?
            let thumbnail: String?
            let small: String?
            let medium: String?
            let large: String?
            let extraLarge: String?

            /// Google fournit jusqu'a six calibres pour une meme couverture.
            /// Une fiche plein ecran ne doit jamais partir de la vignette de
            /// 80/128 px si une image de 300 a 1 280 px est disponible.
            var meilleureDisponible: String? {
                extraLarge ?? large ?? medium ?? small ?? thumbnail ?? smallThumbnail
            }
        }

        struct Identifiant: Decodable {
            let type: String?
            let identifier: String?
        }
    }

    func enResultat() -> ResultatRecherche? {
        guard let titreBrut = volumeInfo.title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !titreBrut.isEmpty
        else { return nil }

        let sousTitre = volumeInfo.subtitle?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let titre: String
        if let sousTitre, !sousTitre.isEmpty,
           !TexteUtil.normaliser(titreBrut).contains(TexteUtil.normaliser(sousTitre)) {
            // Google place fréquemment « Tome 2 » ou « Vol. 7 » dans
            // `subtitle`. Le conserver est indispensable au rangement dans la
            // bonne série ; les autres sous-titres appartiennent eux aussi au
            // titre officiel de cette édition.
            titre = "\(titreBrut): \(sousTitre)"
        } else {
            titre = titreBrut
        }

        // Certaines notices anciennes n'exposent que l'ISBN-10. Honya stocke
        // toujours son équivalent ISBN-13 canonique pour comparer sans ambiguïté
        // un scan EAN et une notice Google.
        let isbn13 = volumeInfo.industryIdentifiers?
            .filter { $0.type == "ISBN_13" || $0.type == "ISBN_10" }
            .compactMap(\.identifier)
            .compactMap(ISBNUtil.canonique)
            .first
        let categories = volumeInfo.categories ?? []
        let categoriesNormalisees = categories.map(TexteUtil.normaliser)
        let estManga = categoriesNormalisees.contains {
            $0.contains("manga") || $0.contains("manhwa") || $0.contains("manhua")
        }
        let estBD = categoriesNormalisees.contains {
            $0.contains("comic") || $0.contains("graphic")
                || $0.contains("bande dessinee") || $0.contains("fumetti")
                || $0.contains("tebeo") || $0.contains("stripverhaal")
        }

        var resultat = ResultatRecherche(
            id: "google:\(id)",
            titre: titre,
            source: "Google Books"
        )
        resultat.auteurs = volumeInfo.authors ?? []
        resultat.type = estManga ? .manga : (estBD ? .bd : .livre)
        resultat.resume = volumeInfo.description.map(TexteUtil.sansHTML)
        resultat.pages = volumeInfo.pageCount
        resultat.annee = TexteUtil.annee(volumeInfo.publishedDate)
        resultat.dateSortie = Self.dateComplete(volumeInfo.publishedDate)
        resultat.genres = categories
        resultat.couvertureURL = Self.couvertureHTTPS(
            volumeInfo.imageLinks?.meilleureDisponible
        )
        resultat.isbn = isbn13
        resultat.langue = volumeInfo.language
        if let langue = volumeInfo.language {
            resultat.titresParLangue[langue] = titre
        }
        return resultat
    }

    /// Google renvoie selon les notices `yyyy`, `yyyy-MM` ou `yyyy-MM-dd`.
    /// Seule la dernière forme permet une date de sortie honnête : fabriquer le
    /// premier jour d'une année ou d'un mois créerait de fausses sorties.
    private static func dateComplete(_ valeur: String?) -> Date? {
        guard let valeur else { return nil }
        let morceau = String(valeur.prefix(10))
        guard morceau.range(
            of: #"^\d{4}-\d{2}-\d{2}$"#,
            options: .regularExpression
        ) != nil else { return nil }

        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.calendar = Calendar(identifier: .gregorian)
        format.timeZone = .current
        format.dateFormat = "yyyy-MM-dd"
        format.isLenient = false
        guard let minuit = format.date(from: morceau) else { return nil }
        // Une date civile n'est pas un instant UTC. La garder à midi local
        // évite qu'un simple formatage la fasse reculer d'un jour dans les
        // fuseaux américains.
        return Calendar.current.date(byAdding: .hour, value: 12, to: minuit)
    }

    /// L'API Google Books renvoie encore certaines vignettes en `http://`.
    /// Elles sont disponibles en TLS au même emplacement ; enregistrer l'URL
    /// HTTPS évite leur blocage par App Transport Security sur iOS.
    private static func couvertureHTTPS(_ valeur: String?) -> String? {
        guard let valeur, var composants = URLComponents(string: valeur) else {
            return nil
        }
        if composants.scheme?.lowercased() == "http" {
            composants.scheme = "https"
        }
        return composants.url?.absoluteString
    }
}

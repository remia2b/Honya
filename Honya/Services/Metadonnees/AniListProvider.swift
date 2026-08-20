import Foundation

/// LA source pour les séries manga : titres officiels (natif / romaji / anglais),
/// couvertures HD, nombre de tomes/chapitres, statut de parution.
/// GraphQL public, sans clé (~90 requêtes/minute).
struct AniListProvider: MetadataProvider {

    func rechercher(_ requete: String, langue: String?) async throws -> [ResultatRecherche] {
        let corps: [String: Any] = [
            "query": Self.requeteGraphQL,
            "variables": ["recherche": requete],
        ]
        var demande = URLRequest(url: URL(string: "https://graphql.anilist.co")!)
        demande.httpMethod = "POST"
        demande.setValue("application/json", forHTTPHeaderField: "Content-Type")
        demande.setValue("application/json", forHTTPHeaderField: "Accept")
        demande.httpBody = try JSONSerialization.data(withJSONObject: corps)

        let (donnees, _) = try await URLSession.shared.data(for: demande)
        let reponse = try JSONDecoder().decode(Reponse.self, from: donnees)
        return (reponse.data?.Page?.media ?? []).map { $0.enResultat() }
    }

    /// AniList n'indexe pas les ISBN : la résolution d'un tome physique passe par Google Books/Open Library.
    func parISBN(_ isbn: String) async throws -> ResultatRecherche? { nil }

    private static let requeteGraphQL = """
    query ($recherche: String) {
      Page(perPage: 12) {
        media(search: $recherche, type: MANGA, sort: SEARCH_MATCH) {
          id
          title { romaji english native }
          coverImage { extraLarge large }
          volumes
          chapters
          status
          genres
          description(asHtml: false)
          startDate { year }
          staff(perPage: 2) { nodes { name { full } } }
        }
      }
    }
    """

    // MARK: - Décodage

    private struct Reponse: Decodable {
        let data: Donnees?
        struct Donnees: Decodable {
            let Page: Page?
        }
        struct Page: Decodable {
            let media: [Media]?
        }
    }

    private struct Media: Decodable {
        let id: Int
        let title: Titre?
        let coverImage: Couverture?
        let volumes: Int?
        let chapters: Int?
        let status: String?
        let genres: [String]?
        let description: String?
        let startDate: DateDebut?
        let staff: Staff?

        struct Titre: Decodable { let romaji: String?; let english: String?; let native: String? }
        struct Couverture: Decodable { let extraLarge: String?; let large: String? }
        struct DateDebut: Decodable { let year: Int? }
        struct Staff: Decodable {
            let nodes: [Noeud]?
            struct Noeud: Decodable {
                let name: Nom?
                struct Nom: Decodable { let full: String? }
            }
        }

        func enResultat() -> ResultatRecherche {
            let romaji = title?.romaji
            let anglais = title?.english
            let natif = title?.native

            var resultat = ResultatRecherche(
                id: "anilist:\(id)",
                titre: anglais ?? romaji ?? natif ?? "Sans titre",
                source: "AniList"
            )
            resultat.titreOriginal = natif ?? romaji
            resultat.romaji = romaji
            if let anglais { resultat.titresParLangue["en"] = anglais }
            else if let romaji { resultat.titresParLangue["en"] = romaji }
            if let natif { resultat.titresParLangue["ja"] = natif }
            resultat.auteurs = (staff?.nodes ?? []).compactMap { $0.name?.full }
            resultat.type = .manga
            resultat.estSerie = true
            resultat.resume = description.map(TexteUtil.sansHTML)
            resultat.annee = startDate?.year
            resultat.genres = genres ?? []
            resultat.couvertureURL = coverImage?.extraLarge ?? coverImage?.large
            resultat.tomesTotal = volumes
            resultat.chapitresTotal = chapters
            resultat.idAniList = id
            switch status {
            case "FINISHED": resultat.statutParution = .terminee
            case "RELEASING": resultat.statutParution = .enCours
            default: resultat.statutParution = .inconnue
            }
            return resultat
        }
    }
}

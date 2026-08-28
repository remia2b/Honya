import Foundation

/// LA source pour les séries manga : titres officiels (natif / romaji / anglais),
/// couvertures HD, nombre de tomes/chapitres, statut de parution.
/// GraphQL public, sans clé (30 requêtes/minute pendant la limitation
/// temporaire annoncée par AniList).
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

        try await CadenceAniList.partage.attendre()
        let (donnees, reponseHTTP) = try await Reseau.catalogues.data(for: demande)
        if let http = reponseHTTP as? HTTPURLResponse, http.statusCode == 429 {
            let secondes = http.value(forHTTPHeaderField: "Retry-After")
                .flatMap(Double.init) ?? 60
            await CadenceAniList.partage.bloquer(pendant: secondes)
            throw URLError(.resourceUnavailable)
        }
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
          synonyms
          coverImage { extraLarge large }
          volumes
          chapters
          status
          countryOfOrigin
          genres
          description(asHtml: false)
          startDate { year }
          staff(perPage: 6) { edges { role node { name { full } } } }
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
        let synonyms: [String]?
        let coverImage: Couverture?
        let volumes: Int?
        let chapters: Int?
        let status: String?
        let countryOfOrigin: String?
        let genres: [String]?
        let description: String?
        let startDate: DateDebut?
        let staff: Staff?

        struct Titre: Decodable { let romaji: String?; let english: String?; let native: String? }
        struct Couverture: Decodable { let extraLarge: String?; let large: String? }
        struct DateDebut: Decodable { let year: Int? }
        struct Staff: Decodable {
            let edges: [Arete]?
            struct Arete: Decodable {
                let role: String?
                let node: Noeud?
            }
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
            resultat.titresAlternatifs = synonyms ?? []
            if let anglais { resultat.titresParLangue["en"] = anglais }
            else if let romaji { resultat.titresParLangue["en"] = romaji }
            if let natif {
                let langueNative: String?
                switch countryOfOrigin {
                case "JP": langueNative = "ja"
                case "KR": langueNative = "ko"
                case "CN", "TW": langueNative = "zh"
                default: langueNative = nil
                }
                if let langueNative { resultat.titresParLangue[langueNative] = natif }
            }
            // Les crédits AniList mêlent mangaka et traducteurs : on ne garde
            // que la plume et le trait (Story / Art), jamais la traduction.
            let aretes = staff?.edges ?? []
            let auteurs = aretes
                .filter { arete in
                    let role = (arete.role ?? "").lowercased()
                    return role.contains("story") || role.contains("art") || role.contains("original")
                }
                .compactMap { $0.node?.name?.full }
            resultat.auteurs = auteurs.isEmpty
                ? aretes.compactMap { $0.node?.name?.full }
                : Array(NSOrderedSet(array: auteurs)) as? [String] ?? auteurs
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

/// Une cadence globale évite le burst limiter et le plafond temporaire de
/// 30 appels/minute. `Task.sleep` propage l'annulation : une ancienne frappe
/// ne consomme jamais un appel après avoir été remplacée.
private actor CadenceAniList {
    static let partage = CadenceAniList()
    private static let capacite = 1.0
    private static let parSeconde = 30.0 / 60.0
    private var jetons = capacite
    private var derniereMesure = Date()

    func attendre() async throws {
        while true {
            try Task.checkCancellation()
            recharger()
            if jetons >= 1 {
                jetons -= 1
                return
            }
            let manque = (1 - jetons) / Self.parSeconde
            try await Task.sleep(for: .seconds(manque))
        }
    }

    func bloquer(pendant secondes: TimeInterval) {
        jetons = 0
        derniereMesure = max(
            derniereMesure,
            Date().addingTimeInterval(max(0, secondes))
        )
    }

    private func recharger() {
        let maintenant = Date()
        let ecoule = maintenant.timeIntervalSince(derniereMesure)
        if ecoule > 0 {
            jetons = min(Self.capacite, jetons + ecoule * Self.parSeconde)
            derniereMesure = maintenant
        }
    }
}

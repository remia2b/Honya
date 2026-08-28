import Foundation

/// Repli ouvert et sans clé : catalogue Internet Archive,
/// couvertures directes par identifiant (covers.openlibrary.org).
///
/// La Search API décrit d'abord une œuvre, puis ses éditions. Honya ne reprend
/// jamais le titre, la langue ou la couverture du niveau « œuvre » : ces trois
/// données doivent provenir de la même édition publiée.
struct OpenLibraryProvider: MetadataProvider {

    func rechercher(_ requete: String, langue: String?) async throws -> [ResultatRecherche] {
        let langueDemandee = langue.map(Self.codeLangueBase)
        var requeteFiltree = requete
        if let langueDemandee,
           let marc = Self.versMARC[langueDemandee] {
            // `language:` filtre réellement les notices. Le paramètre `lang`
            // seul ne fait qu'influencer leur ordre dans la Search API.
            requeteFiltree += " language:\(marc)"
        }

        let reponse = try await rechercherAPI(
            requeteFiltree,
            langueInterface: langueDemandee,
            limite: 20
        )
        return Self.resultats(
            de: reponse, langueDemandee: langueDemandee
        )
    }

    /// Recherche de fond pour un rayon complet. Une seule requête groupée
    /// vaut mieux que cent appels ISBN et respecte la politique Open Library.
    func rechercherSerie(
        _ requete: String, langue: String?
    ) async throws -> [ResultatRecherche] {
        let langueDemandee = langue.map(Self.codeLangueBase)
        var requeteFiltree = requete
        if let langueDemandee,
           let marc = Self.versMARC[langueDemandee] {
            requeteFiltree += " language:\(marc)"
        }
        // Les séries longues dépassent réellement cent volumes. On poursuit
        // tant que la page est pleine, avec un plafond de cinq pages pour
        // rester dans l'usage humain/ponctuel attendu par Open Library.
        var resultats: [ResultatRecherche] = []
        var ids = Set<String>()
        for page in 1...5 {
            try Task.checkCancellation()
            let reponse = try await rechercherAPI(
                requeteFiltree,
                langueInterface: langueDemandee,
                limite: 100,
                page: page
            )
            let pageResultats = Self.resultats(
                de: reponse, langueDemandee: langueDemandee
            )
            for resultat in pageResultats where ids.insert(resultat.id).inserted {
                resultats.append(resultat)
            }
            if (reponse.docs?.count ?? 0) < 100 { break }
        }
        return resultats
    }

    private static func resultats(
        de reponse: ReponseRecherche,
        langueDemandee: String?
    ) -> [ResultatRecherche] {
        return (reponse.docs ?? []).compactMap { document in
            guard let edition = Self.choisirEdition(
                document.editions?.docs ?? [],
                langue: langueDemandee,
                isbnExact: nil
            ) else { return nil }
            return enResultat(
                document: document,
                edition: edition,
                langueDemandee: langueDemandee,
                isbnExact: nil
            )
        }
    }

    func parISBN(_ isbn: String) async throws -> ResultatRecherche? {
        guard let propre = ISBNUtil.canonique(isbn) else { return nil }

        // La recherche ISBN permet de demander `editions.*`. La route
        // `/isbn/{isbn}.json` ne fournit pas toujours la langue et obligeait
        // auparavant à la deviner depuis le préfixe du code-barres.
        let reponse = try await rechercherAPI(
            "isbn:\(propre)",
            langueInterface: nil,
            limite: 5
        )
        for document in reponse.docs ?? [] {
            guard let edition = Self.choisirEdition(
                document.editions?.docs ?? [],
                langue: nil,
                isbnExact: propre
            ) else { continue }
            if let resultat = Self.enResultat(
                document: document,
                edition: edition,
                langueDemandee: nil,
                isbnExact: propre
            ) {
                return resultat
            }
        }
        return nil
    }

    private func rechercherAPI(
        _ requete: String,
        langueInterface: String?,
        limite: Int,
        page: Int = 1
    ) async throws -> ReponseRecherche {
        var composants = URLComponents(string: "https://openlibrary.org/search.json")!
        var parametres = [
            URLQueryItem(name: "q", value: requete),
            URLQueryItem(name: "limit", value: String(limite)),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(
                name: "fields",
                value: [
                    "key", "author_name", "subject", "editions",
                    "editions.key", "editions.title", "editions.subtitle",
                    "editions.cover_i", "editions.number_of_pages",
                    "editions.language", "editions.isbn",
                    "editions.publish_year", "editions.publish_date",
                ].joined(separator: ",")
            ),
        ]
        if let langueInterface {
            // Deux lettres ici, conformément à la Search API. Ce paramètre ne
            // remplace jamais le filtre MARC ajouté à `q` ci-dessus.
            parametres.append(URLQueryItem(name: "lang", value: langueInterface))
        }
        composants.queryItems = parametres
        guard let url = composants.url else { return ReponseRecherche(docs: []) }

        try await CadenceOpenLibrary.partage.attendre()
        let (donnees, reponse) = try await Reseau.catalogues.data(from: url)
        if let http = reponse as? HTTPURLResponse, http.statusCode == 429 {
            let secondes = http.value(forHTTPHeaderField: "Retry-After")
                .flatMap(Double.init) ?? 1
            await CadenceOpenLibrary.partage.bloquer(pendant: secondes)
            throw URLError(.resourceUnavailable)
        }
        return try JSONDecoder().decode(ReponseRecherche.self, from: donnees)
    }

    // MARK: - Sélection d'une édition cohérente

    private static func choisirEdition(
        _ editions: [EditionRecherche],
        langue: String?,
        isbnExact: String?
    ) -> EditionRecherche? {
        var candidates = editions

        if let isbnExact {
            candidates = candidates.filter { edition in
                edition.isbn?.contains(where: {
                    ISBNUtil.canonique($0) == isbnExact
                }) == true
            }
        }

        if let langue {
            let codesAcceptes = variantesMARC(pour: langue)
            candidates = candidates.filter { edition in
                guard let codes = edition.language, !codes.isEmpty else { return false }
                return codes.contains { codesAcceptes.contains($0.lowercased()) }
            }
        }

        // Une fiche sans titre d'édition ne doit jamais emprunter celui du work.
        candidates = candidates.filter {
            $0.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }

        return candidates.enumerated().max { gauche, droite in
            let scoreGauche = scoreEdition(gauche.element)
            let scoreDroite = scoreEdition(droite.element)
            if scoreGauche == scoreDroite { return gauche.offset > droite.offset }
            return scoreGauche < scoreDroite
        }?.element
    }

    private static func scoreEdition(_ edition: EditionRecherche) -> Int {
        var score = 0
        if edition.cover_i != nil { score += 8 }
        if edition.isbn?.contains(where: { ISBNUtil.canonique($0) != nil }) == true {
            score += 4
        }
        if edition.number_of_pages != nil { score += 2 }
        if edition.publish_date?.isEmpty == false { score += 1 }
        if edition.publish_year?.isEmpty == false { score += 1 }
        return score
    }

    private static func enResultat(
        document: Doc,
        edition: EditionRecherche,
        langueDemandee: String?,
        isbnExact: String?
    ) -> ResultatRecherche? {
        guard let titreBrut = edition.title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !titreBrut.isEmpty
        else { return nil }

        let sousTitre = edition.subtitle?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let titre: String
        if let sousTitre, !sousTitre.isEmpty,
           !TexteUtil.normaliser(titreBrut).contains(TexteUtil.normaliser(sousTitre)) {
            titre = titreBrut + ": " + sousTitre
        } else {
            titre = titreBrut
        }

        let langueEdition: String? = {
            if let langueDemandee { return langueDemandee }
            return edition.language?
                .compactMap { depuisMARC[$0.lowercased()] ?? codeISO6391($0) }
                .first
        }()
        let isbnEdition = isbnExact ?? edition.isbn?
            .compactMap(ISBNUtil.canonique)
            .first

        var resultat = ResultatRecherche(
            id: "openlibrary:\(edition.key ?? document.key ?? titre)",
            titre: titre,
            source: "Open Library"
        )
        resultat.auteurs = document.author_name ?? []
        resultat.pages = edition.number_of_pages
        resultat.annee = edition.publish_year?.first
        resultat.dateSortie = edition.publish_date?.compactMap { dateComplete($0) }.first
        resultat.isbn = isbnEdition
        resultat.langue = langueEdition
        if let coverId = edition.cover_i {
            resultat.couvertureURL = "https://covers.openlibrary.org/b/id/\(coverId)-L.jpg"
        }
        if let langueEdition {
            resultat.titresParLangue[langueEdition] = titre
        }

        let sujets = document.subject ?? []
        // Certaines œuvres exposent plusieurs centaines de sujets historiques.
        // Ils restent utiles à la classification, mais pas tous à l'affichage.
        resultat.genres = Array(sujets.prefix(20))
        let classification = TexteUtil.normaliser(sujets.joined(separator: " "))
        if classification.contains("manga") {
            resultat.type = .manga
        } else if classification.contains("comic")
                    || classification.contains("graphic novel")
                    || classification.contains("bande dessinee") {
            resultat.type = .bd
        }
        return resultat
    }

    /// Open Library mélange dates ISO et dates éditoriales anglaises. Une
    /// année ou un mois seuls ne suffisent pas à programmer une sortie : on
    /// ne conserve que les valeurs portant réellement jour, mois et année.
    private static func dateComplete(_ valeur: String) -> Date? {
        let propre = valeur.trimmingCharacters(in: .whitespacesAndNewlines)

        // Les dates entièrement numériques sont culturellement ambiguës. On
        // accepte seulement celles dont un composant supérieur à 12 révèle
        // sans doute possible l'ordre jour/mois ou mois/jour.
        let morceauxNumeriques = propre.split { $0 == "/" || $0 == "-" }
        if morceauxNumeriques.count == 3,
           morceauxNumeriques[0].count <= 2,
           morceauxNumeriques[1].count <= 2,
           morceauxNumeriques[2].count == 4,
           let premier = Int(morceauxNumeriques[0]),
           let second = Int(morceauxNumeriques[1]),
           let annee = Int(morceauxNumeriques[2]),
           (premier > 12 || second > 12) {
            let jour = premier > 12 ? premier : second
            let mois = premier > 12 ? second : premier
            var composants = DateComponents()
            composants.calendar = Calendar(identifier: .gregorian)
            composants.timeZone = .current
            composants.year = annee
            composants.month = mois
            composants.day = jour
            composants.hour = 12
            if let date = composants.date {
                let verification = composants.calendar?.dateComponents(
                    [.year, .month, .day], from: date
                )
                if verification?.year == annee,
                   verification?.month == mois,
                   verification?.day == jour {
                    return date
                }
            }
            return nil
        }

        // Open Library expose aussi les ordinaux anglais (« Apr 2nd 2025 »).
        // Le suffixe n'apporte aucune information et DateFormatter le refuse.
        let sansOrdinal = propre.replacingOccurrences(
            of: #"(?i)(\d{1,2})(st|nd|rd|th)"#,
            with: "$1",
            options: .regularExpression
        )
        let formats = [
            "yyyy-MM-dd",
            "MMMM d, yyyy", "MMM d, yyyy",
            "MMMM d yyyy", "MMM d yyyy",
            "d MMMM yyyy", "d MMM yyyy",
        ]
        for modele in formats {
            let format = DateFormatter()
            format.locale = Locale(identifier: "en_US_POSIX")
            format.calendar = Calendar(identifier: .gregorian)
            format.timeZone = .current
            format.dateFormat = modele
            format.isLenient = false
            if let minuit = format.date(from: sansOrdinal) {
                return Calendar.current.date(byAdding: .hour, value: 12, to: minuit)
            }
        }
        return nil
    }

    // MARK: - Langues Open Library (ISO 639-2 / MARC)

    /// Code bibliographique privilégié pour chacune des langues proposées par
    /// Honya. Open Library emploie encore souvent les formes historiques
    /// (`fre`, `ger`, `dut`...) plutôt que les variantes terminologiques.
    private static let versMARC: [String: String] = [
        "fr": "fre", "en": "eng", "es": "spa", "de": "ger",
        "it": "ita", "pt": "por", "nl": "dut", "sv": "swe",
        "da": "dan", "no": "nor", "fi": "fin", "pl": "pol",
        "cs": "cze", "hu": "hun", "ro": "rum", "el": "gre",
        "tr": "tur", "ru": "rus", "uk": "ukr", "ar": "ara",
        "he": "heb", "hi": "hin", "th": "tha", "vi": "vie",
        "id": "ind", "ja": "jpn", "ko": "kor", "zh": "chi",
        "ca": "cat", "eu": "baq",
    ]

    private static let depuisMARC: [String: String] = [
        "fre": "fr", "fra": "fr", "eng": "en", "spa": "es",
        "ger": "de", "deu": "de", "ita": "it", "por": "pt",
        "dut": "nl", "nld": "nl", "swe": "sv", "dan": "da",
        "nor": "no", "fin": "fi", "pol": "pl", "cze": "cs",
        "ces": "cs", "hun": "hu", "rum": "ro", "ron": "ro",
        "gre": "el", "ell": "el", "tur": "tr", "rus": "ru",
        "ukr": "uk", "ara": "ar", "heb": "he", "hin": "hi",
        "tha": "th", "vie": "vi", "ind": "id", "jpn": "ja",
        "kor": "ko", "chi": "zh", "zho": "zh", "cat": "ca",
        "baq": "eu", "eus": "eu",
    ]

    private static func variantesMARC(pour langue: String) -> Set<String> {
        let base = codeLangueBase(langue)
        var variantes = Set([base])
        if let principal = versMARC[base] { variantes.insert(principal) }
        for (marc, iso) in depuisMARC where iso == base {
            variantes.insert(marc)
        }
        return variantes
    }

    private static func codeLangueBase(_ code: String) -> String {
        code.lowercased()
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .first
            .map { String($0) } ?? code.lowercased()
    }

    private static func codeISO6391(_ code: String) -> String? {
        let propre = codeLangueBase(code)
        return Langues.codes.contains(propre) ? propre : nil
    }

    // MARK: - Décodage

    private struct ReponseRecherche: Decodable {
        let docs: [Doc]?
    }

    private struct Doc: Decodable {
        let key: String?
        let author_name: [String]?
        let subject: [String]?
        let editions: GroupeEditions?
    }

    private struct GroupeEditions: Decodable {
        let docs: [EditionRecherche]?
    }

    private struct EditionRecherche: Decodable {
        let key: String?
        let title: String?
        let subtitle: String?
        let cover_i: Int?
        let number_of_pages: Int?
        let language: [String]?
        let isbn: [String]?
        let publish_year: [Int]?
        let publish_date: [String]?
    }
}

/// Open Library autorise trois appels/seconde aux applications identifiées.
/// Honya se place un peu sous ce seuil et annule proprement les frappes devenues
/// obsolètes, au lieu de les laisser s'entasser dans le réseau.
private actor CadenceOpenLibrary {
    static let partage = CadenceOpenLibrary()
    private static let capacite = 1.0
    private static let parSeconde = 2.75
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

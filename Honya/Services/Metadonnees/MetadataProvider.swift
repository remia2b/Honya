import Foundation

// MARK: - Résultat de recherche unifié (livres & séries manga)

struct ResultatRecherche: Identifiable, Hashable, Sendable {
    let id: String                       // "google:xxx", "openlibrary:xxx", "anilist:123"
    var titre: String
    var titreOriginal: String?
    /// Translittération latine (romaji AniList), lisible sans connaître le script d'origine.
    var romaji: String?
    /// Titres officiels connus par langue (ex. romaji/anglais/natif d'AniList).
    var titresParLangue: [String: String] = [:]
    /// Variantes officielles sans langue déclarée par le fournisseur. Elles
    /// servent uniquement à relier prudemment une série à son édition locale ;
    /// elles ne sont jamais affichées comme une traduction certaine.
    var titresAlternatifs: [String] = []
    var auteurs: [String] = []
    var type: TypeOeuvre = .livre
    var resume: String?
    var pages: Int?
    var annee: Int?
    /// Date de parution complète — future pour une précommande.
    var dateSortie: Date?
    var genres: [String] = []
    var couvertureURL: String?
    /// Provenance et date exigées par certains catalogues pour la vignette.
    var attributionCouverture: String?
    var isbn: String?
    /// Langue de l'édition trouvée (code ISO-639-1).
    var langue: String?
    // Série (manga/BD)
    var estSerie: Bool = false
    var tomesTotal: Int?
    var chapitresTotal: Int?
    var statutParution: StatutParution = .inconnue
    var idAniList: Int?
    /// Cette fiche vient d'une saisie explicite du lecteur, pas d'un
    /// catalogue susceptible d'être invalidé lors d'un changement de langue.
    var saisieManuelle: Bool = false
    var source: String

    /// Un numéro final n'est pas toujours une tomaison (`Room 101`). Il ne
    /// devient un tome que pour un format séquentiel, un marqueur explicite ou
    /// une catégorie bibliographique qui le confirme.
    var estUnTome: Bool {
        guard !estSerie, Tomaison.decomposer(titre).numero != nil else { return false }
        if type != .livre || Tomaison.estMarqueCommeTome(titre) { return true }
        let categories = TexteUtil.normaliser(genres.joined(separator: " "))
        return categories.contains("comic") || categories.contains("manga")
            || categories.contains("bande dessinee") || categories.contains("graphic")
    }

    /// Titre tel qu'un lecteur de cette langue le verrait en librairie.
    func titreAffiche(_ langue: String) -> String {
        Titres.afficher(
            titres: titresParLangue,
            original: titre,
            romaji: romaji,
            langue: langue
        )
    }
}

// MARK: - Protocole commun à toutes les sources

protocol MetadataProvider: Sendable {
    func rechercher(_ requete: String, langue: String?) async throws -> [ResultatRecherche]
    func parISBN(_ isbn: String) async throws -> ResultatRecherche?
}

// MARK: - Utilitaires ISBN

enum ISBNUtil {
    static func normaliser(_ brut: String) -> String {
        brut.uppercased().filter { $0.isNumber || $0 == "X" }
    }

    static func estValide(_ brut: String) -> Bool {
        let n = normaliser(brut)
        if n.count == 13 { return isbn13Valide(n) }
        if n.count == 10 { return isbn10Valide(n) }
        return false
    }

    /// ISBN canonique utilisé par les fournisseurs. Les vieux ISBN-10 sont
    /// convertis en ISBN-13 ; un EAN de produit ou une lecture caméra erronée
    /// n'atteint jamais les catalogues.
    static func canonique(_ brut: String) -> String? {
        let n = normaliser(brut)
        guard estValide(n) else { return nil }
        if n.count == 13 { return n }

        let base = "978" + String(n.prefix(9))
        guard let cle = cleISBN13(base) else { return nil }
        return base + String(cle)
    }

    private static func isbn13Valide(_ isbn: String) -> Bool {
        guard isbn.hasPrefix("978") || isbn.hasPrefix("979"),
              let dernier = isbn.last,
              let cleLue = Int(String(dernier)),
              let cleCalculee = cleISBN13(String(isbn.prefix(12)))
        else { return false }
        return cleLue == cleCalculee
    }

    private static func cleISBN13(_ douzeChiffres: String) -> Int? {
        guard douzeChiffres.count == 12 else { return nil }
        var somme = 0
        for (index, caractere) in douzeChiffres.enumerated() {
            guard let chiffre = Int(String(caractere)) else { return nil }
            somme += chiffre * (index.isMultiple(of: 2) ? 1 : 3)
        }
        return (10 - somme % 10) % 10
    }

    private static func isbn10Valide(_ isbn: String) -> Bool {
        var somme = 0
        for (index, caractere) in isbn.enumerated() {
            let chiffre: Int
            if index == 9, caractere == "X" {
                chiffre = 10
            } else if let valeur = Int(String(caractere)) {
                chiffre = valeur
            } else {
                return false
            }
            somme += chiffre * (10 - index)
        }
        return somme.isMultiple(of: 11)
    }

    /// Langue probable d'après le groupe d'enregistrement de l'ISBN-13
    /// (978-2 = francophone, 978-4 = Japon, etc.).
    static func langueProbable(_ brut: String) -> String? {
        let n = normaliser(brut)
        guard n.count == 13 else { return nil }
        let corps = String(n.dropFirst(3))
        // Les groupes 979 ont leur propre registre : 979-10 est français,
        // pas anglophone — le confondre faussait la langue de tout ce que
        // la France publie sous le nouveau préfixe.
        if n.hasPrefix("979") {
            if corps.hasPrefix("10") { return "fr" }
            if corps.hasPrefix("11") { return "ko" }
            if corps.hasPrefix("12") { return "it" }
            if corps.hasPrefix("8") { return "en" }
            return nil
        }
        switch corps.first {
        case "0", "1": return "en"
        case "2": return "fr"
        case "3": return "de"
        case "4": return "ja"
        case "5": return "ru"
        case "7": return "zh"
        case "8":
            if corps.hasPrefix("88") { return "it" }
            if corps.hasPrefix("84") { return "es" }
            if corps.hasPrefix("85") { return "pt" }
            if corps.hasPrefix("83") { return "pl" }
            if corps.hasPrefix("89") { return "ko" }
            return nil
        case "9":
            if corps.hasPrefix("91") { return "sv" }
            if corps.hasPrefix("90") || corps.hasPrefix("94") { return "nl" }
            return nil
        default: return nil
        }
    }
}

// MARK: - Petites aides partagées

enum TexteUtil {
    /// Comparaison souple : insensible à la casse et aux accents.
    static func contient(_ champs: [String], _ requete: String) -> Bool {
        let besoin = normaliser(requete)
        guard !besoin.isEmpty else { return true }
        return champs.contains { normaliser($0).contains(besoin) }
    }

    static func normaliser(_ texte: String) -> String {
        texte.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: .current)
    }

    /// Retire les balises HTML simples (résumés AniList).
    static func sansHTML(_ texte: String) -> String {
        var resultat = texte
            .replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "<br/>", with: "\n")
            .replacingOccurrences(of: "<br />", with: "\n")
        resultat = resultat.replacingOccurrences(
            of: #"</?(?:p|div|li|ul|ol|h[1-6])\b[^>]*>"#,
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )
        resultat = resultat.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )
        for (entite, valeur) in [
            "&amp;": "&", "&quot;": "\"", "&#39;": "'",
            "&apos;": "'", "&nbsp;": " ",
        ] {
            resultat = resultat.replacingOccurrences(of: entite, with: valeur)
        }
        resultat = resultat.replacingOccurrences(
            of: #"[ \t]+\n"#, with: "\n", options: .regularExpression
        )
        resultat = resultat.replacingOccurrences(
            of: #"\n{3,}"#, with: "\n\n", options: .regularExpression
        )
        return resultat.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Première année trouvée dans une date type "1965-08-01".
    static func annee(_ chaine: String?) -> Int? {
        guard let chaine, chaine.count >= 4 else { return nil }
        return Int(chaine.prefix(4))
    }
}

// MARK: - Correspondance d'auteurs entre catalogues

enum AuteursUtil {
    /// Deux notices de même titre ne désignent la même œuvre que si leurs
    /// mentions de responsabilité sont compatibles. Une seule notice muette
    /// ne suffit pas : c'est le cas qui collait des couvertures d'homonymes.
    static func correspondent(_ candidats: [String], _ references: [String]) -> Bool {
        let siens = candidats.compactMap(mots)
        let ceux = references.compactMap(mots)
        // On compare auteur par auteur. Mélanger toutes les personnes d'une
        // notice permettait à un simple prénom commun de valider l'ensemble.
        for candidat in siens {
            for reference in ceux {
                if candidat.normalise == reference.normalise { return true }
                let communs = candidat.tokens.intersection(reference.tokens)
                if communs.count >= 2 { return true }

                // « J. K. Rowling » et « Rowling, J. K. » ne conservent que
                // le patronyme après retrait des initiales. On accepte ce cas
                // uniquement pour un mot assez distinctif, pas « Jean » entre
                // deux noms complets différents.
                if communs.count == 1, let mot = communs.first, mot.count >= 5,
                   candidat.tokens.count == 1 || reference.tokens.count == 1 {
                    return true
                }
            }
        }
        return false
    }

    private static func mots(_ nom: String) -> (normalise: String, tokens: Set<String>)? {
        let normalise = TexteUtil.normaliser(nom)
        let tokens = Set(
            normalise
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 3 }
        )
        guard !tokens.isEmpty else { return nil }
        return (normalise, tokens)
    }
}

import Foundation

// MARK: - Résultat de recherche unifié (livres & séries manga)

struct ResultatRecherche: Identifiable, Hashable {
    let id: String                       // "google:xxx", "openlibrary:xxx", "anilist:123"
    var titre: String
    var titreOriginal: String?
    /// Titres officiels connus par langue (ex. romaji/anglais/natif d'AniList).
    var titresParLangue: [String: String] = [:]
    var auteurs: [String] = []
    var type: TypeOeuvre = .livre
    var resume: String?
    var pages: Int?
    var annee: Int?
    var genres: [String] = []
    var couvertureURL: String?
    var isbn: String?
    /// Langue de l'édition trouvée (code ISO-639-1).
    var langue: String?
    // Série (manga/BD)
    var estSerie: Bool = false
    var tomesTotal: Int?
    var chapitresTotal: Int?
    var statutParution: StatutParution = .inconnue
    var idAniList: Int?
    var source: String
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
        return n.count == 10 || n.count == 13
    }

    /// Langue probable d'après le groupe d'enregistrement de l'ISBN-13
    /// (978-2 = francophone, 978-4 = Japon, etc.).
    static func langueProbable(_ brut: String) -> String? {
        let n = normaliser(brut)
        guard n.count == 13 else { return nil }
        let corps = String(n.dropFirst(3))
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
            return nil
        default: return nil
        }
    }
}

// MARK: - Petites aides partagées

enum TexteUtil {
    /// Retire les balises HTML simples (résumés AniList).
    static func sansHTML(_ texte: String) -> String {
        var resultat = texte
            .replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "<br/>", with: "\n")
            .replacingOccurrences(of: "<br />", with: "\n")
        resultat = resultat.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )
        return resultat.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Première année trouvée dans une date type "1965-08-01".
    static func annee(_ chaine: String?) -> Int? {
        guard let chaine, chaine.count >= 4 else { return nil }
        return Int(chaine.prefix(4))
    }
}

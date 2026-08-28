import Foundation

// MARK: - Langues de lecture
//
// Honya est international : on propose toutes les grandes langues de publication,
// avec leur nom dans leur propre langue (comme le fait iOS), et la langue de
// l'appareil est présélectionnée.

struct LangueLecture: Identifiable, Hashable {
    let code: String
    var id: String { code }

    /// Nom de la langue dans sa propre langue : « Français », « 日本語 », « Español ».
    var nomNatif: String {
        Locale(identifier: code).localizedString(forLanguageCode: code)?.capitalized
            ?? code.uppercased()
    }

    /// Nom traduit dans la langue de l'utilisateur, pour lever une ambiguïté.
    var nomLocal: String {
        Locale.current.localizedString(forLanguageCode: code)?.capitalized
            ?? code.uppercased()
    }
}

enum Langues {
    /// Principales langues de publication mondiale.
    static let codes = [
        "fr", "en", "es", "de", "it", "pt", "nl", "sv", "da", "no", "fi", "pl",
        "cs", "hu", "ro", "el", "tr", "ru", "uk", "ar", "he", "hi", "th", "vi",
        "id", "ja", "ko", "zh", "ca", "eu",
    ]

    /// Liste triée : la langue de l'appareil d'abord, puis l'ordre alphabétique local.
    static var toutes: [LangueLecture] {
        let appareil = codeAppareil
        return codes
            .map(LangueLecture.init(code:))
            .sorted {
                if $0.code == appareil { return $1.code != appareil }
                if $1.code == appareil { return false }
                return $0.nomLocal.localizedCaseInsensitiveCompare($1.nomLocal) == .orderedAscending
            }
    }

    static var codeAppareil: String {
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        return codes.contains(code) ? code : "en"
    }

    static func nom(_ code: String) -> String {
        LangueLecture(code: code).nomNatif
    }

    /// Storefront Apple Books associé à chaque langue de lecture.
    private static let boutiqueParLangue: [String: String] = [
        "fr": "FR", "en": "US", "ja": "JP", "es": "ES", "de": "DE",
        "it": "IT", "pt": "BR", "nl": "NL", "sv": "SE", "da": "DK",
        "no": "NO", "fi": "FI", "pl": "PL", "cs": "CZ", "hu": "HU",
        "ro": "RO", "el": "GR", "tr": "TR", "ru": "RU", "uk": "UA",
        "ar": "SA", "he": "IL", "hi": "IN", "th": "TH", "vi": "VN",
        "id": "ID", "ko": "KR", "zh": "CN", "ca": "ES", "eu": "ES",
    ]

    /// La boutique de la LANGUE choisie dans Honya. La région courante ne doit
    /// pas reprendre la main : si le lecteur demande l'édition japonaise sur
    /// un iPhone français, il faut interroger le Japon, pas la France.
    static func storefront(pourLangue langue: String) -> String {
        let code = langue.lowercased()
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .first
            .map { String($0) } ?? langue.lowercased()
        // Pour la langue principale de l'appareil, conserver son vrai marché :
        // en-GB, fr-CA, fr-CH et pt-PT ne sont pas les éditions US/FR/BR.
        if code == codeAppareil,
           let region = Locale.current.region?.identifier,
           region.count == 2 {
            return region.uppercased()
        }
        return boutiqueParLangue[code] ?? "US"
    }

    /// La boutique de repli la plus plausible pour l'édition, estimée depuis
    /// le groupe d'enregistrement de l'ISBN.
    ///
    /// Ce groupe décrit une zone linguistique d'enregistrement, pas avec
    /// certitude le pays de vente : le résultat reste donc un filet imparfait.
    /// Il évite néanmoins de demander systématiquement la boutique américaine
    /// pour un ISBN francophone ou japonais. La correspondance finale demeure
    /// strictement contrôlée sur l'ISBN exact.
    static func storefrontEdition(_ isbn: String) -> String {
        if let langue = ISBNUtil.langueProbable(isbn),
           let pays = boutiqueParLangue[langue] {
            return pays
        }
        return storefront(pourLangue: codeAppareil)
    }
}

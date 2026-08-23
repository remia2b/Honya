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
                if $0.code == appareil { return true }
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

    /// Storefront Apple Books du lecteur : la région de l'iPhone d'abord,
    /// sinon le pays le plus naturel pour sa langue de lecture.
    static func storefront(pourLangue langue: String) -> String {
        if let region = Locale.current.region?.identifier, region.count == 2 {
            return region
        }
        let parDefaut: [String: String] = [
            "fr": "FR", "en": "US", "ja": "JP", "es": "ES", "de": "DE",
            "it": "IT", "pt": "BR", "nl": "NL", "sv": "SE", "da": "DK",
            "no": "NO", "fi": "FI", "pl": "PL", "cs": "CZ", "hu": "HU",
            "ro": "RO", "el": "GR", "tr": "TR", "ru": "RU", "uk": "UA",
            "ar": "SA", "he": "IL", "hi": "IN", "th": "TH", "vi": "VN",
            "id": "ID", "ko": "KR", "zh": "CN", "ca": "ES", "eu": "ES",
        ]
        return parDefaut[langue] ?? "US"
    }
}

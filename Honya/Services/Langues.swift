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
}

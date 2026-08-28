import Foundation

// MARK: - Choix du titre à afficher
//
// Règle Honya : on montre le titre tel qu'un lecteur le verrait en librairie,
// dans SA langue. Un francophone doit lire « Solo Leveling », jamais
// « 나 혼자만 레벨 업 ». Le titre natif reste stocké, mais n'est affiché qu'en
// dernier recours — ou quand c'est précisément la langue du lecteur.

enum Titres {

    private enum Script: Hashable {
        case grec, cyrillique, hebreu, arabe, devanagari, thai
        case kana, han, hangul
    }

    private static func script(_ scalaire: UnicodeScalar) -> Script? {
        switch scalaire.value {
        case 0x0370...0x03FF: return .grec
        case 0x0400...0x052F: return .cyrillique
        case 0x0590...0x05FF: return .hebreu
        case 0x0600...0x06FF, 0x0750...0x077F: return .arabe
        case 0x0900...0x097F: return .devanagari
        case 0x0E00...0x0E7F: return .thai
        case 0x3040...0x30FF: return .kana
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF: return .han
        case 0x1100...0x11FF, 0x3130...0x318F, 0xAC00...0xD7AF: return .hangul
        default: return nil
        }
    }

    private static func scriptsAutorises(_ langue: String) -> Set<Script> {
        switch langue.split(separator: "-").first.map({ String($0) }) ?? langue {
        case "el": return [.grec]
        case "ru", "uk", "bg", "sr": return [.cyrillique]
        case "he": return [.hebreu]
        case "ar", "fa": return [.arabe]
        case "hi": return [.devanagari]
        case "th": return [.thai]
        case "ja": return [.kana, .han]
        case "zh": return [.han]
        case "ko": return [.hangul, .han]
        default: return []
        }
    }

    /// Le texte est-il majoritairement écrit dans un script non latin ?
    static func estNonLatin(_ texte: String) -> Bool {
        let lettres = texte.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard !lettres.isEmpty else { return false }
        let horsLatin = lettres.filter { script($0) != nil }
        return Double(horsLatin.count) / Double(lettres.count) > 0.3
    }

    /// Cette langue emploie-t-elle au moins un script non latin ?
    static func litScriptNonLatin(_ langue: String) -> Bool {
        !scriptsAutorises(langue).isEmpty
    }

    /// Vérifie le script précis, pas seulement « latin / non latin ». Un titre
    /// russe n'est pas lisible parce que le lecteur est japonais, et un titre
    /// coréen n'est pas étiqueté comme japonais sous prétexte qu'ils sont CJK.
    static func estLisible(_ texte: String, langue: String) -> Bool {
        let rencontres = Set(texte.unicodeScalars.compactMap { script($0) })
        return rencontres.isSubset(of: scriptsAutorises(langue))
    }

    /// Choisit le meilleur titre à afficher pour un lecteur donné.
    ///
    /// - Parameters:
    ///   - titres: titres officiels connus, par code langue.
    ///   - original: titre dans la langue d'origine de l'œuvre.
    ///   - romaji: translittération latine éventuelle (AniList).
    ///   - langue: langue de lecture de l'utilisateur.
    static func afficher(
        titres: [String: String],
        original: String,
        romaji: String? = nil,
        langue: String
    ) -> String {
        let lisible: (String) -> Bool = { estLisible($0, langue: langue) }
        // 1. Le titre officiel dans la langue du lecteur : toujours le meilleur —
        //    sauf si une donnée corrompue y a glissé un script illisible.
        if let officiel = titres[langue], !officiel.isEmpty, lisible(officiel) {
            return officiel
        }
        // 2. L'anglais fait office de langue véhiculaire.
        if let anglais = titres["en"], !anglais.isEmpty, lisible(anglais) {
            return anglais
        }
        // 3. La translittération vaut mieux qu'un script illisible. On ne
        // choisit jamais une valeur arbitraire du dictionnaire : un titre
        // allemand est en alphabet latin, mais n'est pas un titre français.
        if let romaji, !romaji.isEmpty, lisible(romaji) {
            return romaji
        }
        return original
    }
}

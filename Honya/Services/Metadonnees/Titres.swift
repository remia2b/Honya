import Foundation

// MARK: - Choix du titre à afficher
//
// Règle Honya : on montre le titre tel qu'un lecteur le verrait en librairie,
// dans SA langue. Un francophone doit lire « Solo Leveling », jamais
// « 나 혼자만 레벨 업 ». Le titre natif reste stocké, mais n'est affiché qu'en
// dernier recours — ou quand c'est précisément la langue du lecteur.

enum Titres {

    /// Scripts qu'un lecteur d'alphabet latin ne peut pas déchiffrer.
    private static let scriptsNonLatins: [ClosedRange<UInt32>] = [
        0x0400...0x04FF,   // cyrillique
        0x0590...0x05FF,   // hébreu
        0x0600...0x06FF,   // arabe
        0x0900...0x097F,   // devanagari
        0x0E00...0x0E7F,   // thaï
        0x1100...0x11FF,   // jamo coréen
        0x3040...0x30FF,   // hiragana / katakana
        0x3400...0x4DBF,   // idéogrammes (extension A)
        0x4E00...0x9FFF,   // idéogrammes CJK
        0xAC00...0xD7AF,   // hangûl
        0xF900...0xFAFF,   // idéogrammes de compatibilité
    ]

    /// Langues qui s'écrivent dans un script non latin.
    private static let languesNonLatines: Set<String> = [
        "ja", "ko", "zh", "ru", "uk", "ar", "he", "hi", "th", "el", "bg", "sr", "fa",
    ]

    /// Le texte est-il majoritairement écrit dans un script non latin ?
    static func estNonLatin(_ texte: String) -> Bool {
        let lettres = texte.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard !lettres.isEmpty else { return false }
        let horsLatin = lettres.filter { scalar in
            scriptsNonLatins.contains { $0.contains(scalar.value) }
        }
        return Double(horsLatin.count) / Double(lettres.count) > 0.3
    }

    /// Le lecteur de cette langue sait-il lire les scripts non latins concernés ?
    static func litScriptNonLatin(_ langue: String) -> Bool {
        languesNonLatines.contains(langue)
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
        // 1. Le titre officiel dans la langue du lecteur : toujours le meilleur.
        if let officiel = titres[langue], !officiel.isEmpty {
            return officiel
        }
        // 2. L'anglais fait office de langue véhiculaire.
        if let anglais = titres["en"], !anglais.isEmpty {
            return anglais
        }
        // 3. Sinon, tout titre déjà connu dans un script lisible par ce lecteur.
        if !litScriptNonLatin(langue) {
            if let latin = titres.values.first(where: { !$0.isEmpty && !estNonLatin($0) }) {
                return latin
            }
            // 4. La translittération vaut mieux qu'un script illisible.
            if let romaji, !romaji.isEmpty, !estNonLatin(romaji) {
                return romaji
            }
            if estNonLatin(original), let secours = titres.values.first(where: { !$0.isEmpty }) {
                return secours
            }
        }
        return original
    }
}

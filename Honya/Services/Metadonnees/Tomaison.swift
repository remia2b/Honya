import Foundation

/// Décompose un titre de tome en (nom de série, numéro) :
/// « Kagurabachi T3 », « One Piece, Vol. 12 », « Naruto Tome 7 », « Berserk #5 »…
///
/// C'est la clé du rangement automatique : un résultat de recherche qui porte
/// un numéro de tome rejoint sa série au lieu de créer un livre isolé — et le
/// nom d'une série ne doit JAMAIS être celui d'un de ses tomes.
enum Tomaison {

    /// Motifs explicites : Vol., Volume, T, Tome, #, n° … suivis d'un numéro.
    private static let motifExplicite =
        #"[,\s\-–—:]*(?:vol(?:ume)?\.?|t(?:ome)?\.?\s*|n[°o]\.?\s*|#)\s*(\d{1,4})\s*(?:\((?:[^)]*)\))?\s*$"#

    /// Motif implicite : un simple numéro en fin de titre (« Kagurabachi 3 »).
    /// Volontairement prudent : petits numéros seulement, pour ne pas découper
    /// « Fahrenheit 451 » ou « 1984 ».
    private static let motifImplicite = #"\s+(\d{1,2})\s*$"#

    static func decomposer(_ titre: String) -> (base: String, numero: Int?) {
        let propre = titre.trimmingCharacters(in: .whitespacesAndNewlines)

        if let resultat = extraire(propre, motif: motifExplicite, maxNumero: 4000) {
            return resultat
        }
        if let resultat = extraire(propre, motif: motifImplicite, maxNumero: 60) {
            return resultat
        }
        return (propre, nil)
    }

    private static func extraire(_ titre: String, motif: String, maxNumero: Int) -> (String, Int?)? {
        guard let plage = titre.range(of: motif, options: [.regularExpression, .caseInsensitive])
        else { return nil }

        let chiffres = titre[plage].components(separatedBy: CharacterSet.decimalDigits.inverted)
            .first { !$0.isEmpty }
        guard let chiffres, let numero = Int(chiffres), numero >= 1, numero <= maxNumero
        else { return nil }

        var base = String(titre[..<plage.lowerBound])
        base = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while let derniere = base.last, ",;:-–—".contains(derniere) {
            base.removeLast()
        }
        base = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard base.count >= 2 else { return nil }
        return (base, numero)
    }

    /// Vrai si deux noms de série désignent la même (comparaison souple).
    static func memeSerie(_ un: String, _ deux: String) -> Bool {
        let a = TexteUtil.normaliser(un)
        let b = TexteUtil.normaliser(deux)
        guard !a.isEmpty, !b.isEmpty else { return false }
        return a == b || a.contains(b) || b.contains(a)
    }
}

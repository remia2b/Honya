import Foundation

/// Décompose un titre de tome en (nom de série, numéro) :
/// « Kagurabachi T3 », « One Piece, Vol. 12 », « Naruto Tome 7 », « Berserk #5 »…
///
/// C'est la clé du rangement automatique : un résultat de recherche qui porte
/// un numéro de tome rejoint sa série au lieu de créer un livre isolé — et le
/// nom d'une série ne doit JAMAIS être celui d'un de ses tomes.
enum Tomaison {

    /// Motifs explicites : Vol., Volume, T, Tome, #, n° … suivis d'un numéro.
    ///
    /// Le séparateur avant le marqueur est OBLIGATOIRE. Quand il était
    /// facultatif, le « t » de n'importe quel mot faisait marqueur : « Blue
    /// Giant 3 » devenait la série « Blue Gian », tome 3, et « Blast 3 »
    /// la série « Blas ».
    private static let motifExplicite =
        #"[,\s\-–—:]+(?:vol(?:ume)?|tome|t|n[°o]|#)\.?\s*(\d{1,4})\s*(?:\((?:[^)]*)\))?\s*$"#

    /// Motif implicite : un simple numéro en fin de titre (« Kagurabachi 3 »).
    ///
    /// Prudent, mais pas au point d'ignorer les longues séries : à deux
    /// chiffres, « One Piece 105 » n'affichait aucun numéro de tome. Trois
    /// chiffres et un plafond à 400 couvrent les plus longues sans découper
    /// « Fahrenheit 451 » ni « Blade Runner 2049 ».
    private static let motifImplicite = #"\s+(\d{1,3})\s*$"#

    /// « Série (Tome 3) », « Série (Vol. 3) » — le numéro entre parenthèses.
    private static let motifParenthese =
        #"\s*\((?:vol(?:ume)?\.?|t(?:ome)?\.?)\s*(\d{1,4})\)\s*$"#

    static func decomposer(_ titre: String) -> (base: String, numero: Int?) {
        let propre = titre.trimmingCharacters(in: .whitespacesAndNewlines)

        if let resultat = extraire(propre, motif: motifParenthese, maxNumero: 4000) {
            return resultat
        }
        if let resultat = extraire(propre, motif: motifExplicite, maxNumero: 4000) {
            return resultat
        }
        if let resultat = extraire(propre, motif: motifImplicite, maxNumero: 400) {
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
        if a == b { return true }
        // Une mention d'édition s'ajoute À LA FIN d'un titre — « Solo
        // Leveling » devient « Solo Leveling - Édition Deluxe ». Elle ne
        // s'insère jamais au milieu, ni au début.
        //
        // Accepter n'importe quel morceau commun faisait passer « After the
        // End » pour « The Beginning After the End » : la couverture d'un
        // roman inconnu venait se coller sur le livre du lecteur, qui
        // retrouvait dans sa bibliothèque un livre qu'il n'avait pas scanné.
        return a.hasPrefix(b) || b.hasPrefix(a)
    }
}

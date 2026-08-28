import Foundation

/// Décompose un titre de tome en (nom de série, numéro) :
/// « Kagurabachi T3 », « One Piece, Vol. 12 », « Naruto Tome 7 », « Berserk #5 »…
///
/// C'est la clé du rangement automatique : un résultat de recherche qui porte
/// un numéro de tome rejoint sa série au lieu de créer un livre isolé — et le
/// nom d'une série ne doit JAMAIS être celui d'un de ses tomes.
enum Tomaison {

    /// Marqueurs de volume rencontrés dans les catalogues internationaux.
    /// Ils restent volontairement explicites : un mot ordinaire terminé par
    /// « t » ne doit jamais être découpé comme un numéro de tome.
    private static let marqueursAvantNumero =
        #"vol(?:ume|umen|ym|um)?|book|livre|libro|livro|buch|boek|bok|bog|kirja|ksi[ąa]żka|kniha|k[öo]nyv|carte|βιβλίο|книга|книжка|كتاب|ספר|पुस्तक|หนังสือ|s[áa]ch|buku|tome|tomo|tom|band|bd|bind|deel|del|osa|d[íi]l|k[öo]tet|volumul|cilt|jilid|liburuki|t[ậa]p|part(?:ie)?|parte|teil|cz[ęe][śs][ćc]|část|cast|r[ée]sz|partea|часть|частина|μέρος|μερος|החלק|الجزء|bölüm|भाग|ภาค|ph[ầa]n|bagian|zatia|t|n(?:[°ºo]|r)|num(?:ero)?|número|núm|tomus|tomos|том|тома|томів|τόμος|τομος|כרך|المجلد|جلد|खंड|เล่ม"#

    /// Motifs explicites : Vol., Band, Tomo, Том, مجلد, T, #, n°…
    /// suivis d'un numéro.
    ///
    /// Le séparateur avant le marqueur est OBLIGATOIRE. Quand il était
    /// facultatif, le « t » de n'importe quel mot faisait marqueur : « Blue
    /// Giant 3 » devenait la série « Blue Gian », tome 3, et « Blast 3 »
    /// la série « Blas ».
    private static let motifExplicite =
        #"[,\s\-–—:\(\[]+(?:"# + marqueursAvantNumero
        + #"|#)\.?\s*(\d{1,4})\s*(?:\((?:[^)]*)\))?\s*[\)\]]?\s*$"#

    /// Les catalogues placent souvent le marqueur avant un sous-titre :
    /// « Vol.11 Le plus grand bandit » ou « Vol.10 (One Piece, 10)
    /// (French Edition) ». L'ancrage de fin ci-dessus ne les voit pas.
    ///
    /// On conserve une frontière forte avant/après le numéro et on retire les
    /// abréviations d'une seule lettre `T` / `n°`, trop ambiguës au milieu
    /// d'une phrase. Les formes complètes internationales restent acceptées.
    private static let marqueursInternesAvantNumero = marqueursAvantNumero
        .replacingOccurrences(of: #"|t|n(?:[°ºo]|r)"#, with: "")

    private static let motifExpliciteInterne =
        #"[,\s\-–—:\(\[]+(?:"# + marqueursInternesAvantNumero
        + #"|#)\.?\s*(\d{1,4})(?=\s|[,\.;:!?\-–—\(\)\[\]]|$)"#

    /// En japonais, chinois et coréen, le classificateur suit souvent le
    /// nombre (「2巻」, 「2卷」, 「2권」) ; 第/제 peut au contraire le
    /// précéder sans aucun espace après le nom de la série.
    private static let motifsExplicitesSuffixes = [
        #"\s*[\(\[]?\s*第\s*(\d{1,4})\s*[巻卷册冊部]\s*[\)\]]?\s*$"#,
        #"\s*[\(\[]?\s*제\s*(\d{1,4})\s*(?:권|부)\s*[\)\]]?\s*$"#,
        #"\s*[\(\[]?\s*(\d{1,4})\s*(?:巻|卷|册|冊|部|권|부)\s*[\)\]]?\s*$"#,
    ]

    /// Motif implicite : un simple numéro en fin de titre (« Kagurabachi 3 »).
    ///
    /// Prudent, mais pas au point d'ignorer les longues séries : à deux
    /// chiffres, « One Piece 105 » n'affichait aucun numéro de tome. Trois
    /// chiffres et un plafond à 400 couvrent les plus longues sans découper
    /// « Fahrenheit 451 » ni « Blade Runner 2049 ».
    private static let motifImplicite = #"\s+(\d{1,3})\s*$"#

    /// « Série (Tome 3) », « Série (Vol. 3) » — le numéro entre parenthèses.
    private static let motifParenthese =
        #"\s*\((?:"# + marqueursAvantNumero
        + #")\.?\s*(\d{1,4})\)\s*$"#

    static func decomposer(_ titre: String) -> (base: String, numero: Int?) {
        let propre = titre.trimmingCharacters(in: .whitespacesAndNewlines)

        if let resultat = decomposerMarqueurExplicite(propre) {
            return resultat
        }
        if let resultat = extraire(propre, motif: motifImplicite, maxNumero: 400) {
            return resultat
        }
        return (propre, nil)
    }

    /// Indique si le titre porte réellement un marqueur de volume. Cette
    /// distinction permet d'identifier un tome catalogué comme « livre » sans
    /// transformer « 1984 » ou « Fahrenheit 451 » en séries.
    static func estMarqueCommeTome(_ titre: String) -> Bool {
        decomposerMarqueurExplicite(
            titre.trimmingCharacters(in: .whitespacesAndNewlines)
        ) != nil
    }

    private static func decomposerMarqueurExplicite(
        _ titre: String
    ) -> (base: String, numero: Int?)? {
        if let resultat = extraire(titre, motif: motifParenthese, maxNumero: 4000) {
            return resultat
        }
        if let resultat = extraire(titre, motif: motifExplicite, maxNumero: 4000) {
            return resultat
        }
        if let resultat = extraire(titre, motif: motifExpliciteInterne, maxNumero: 4000) {
            return resultat
        }
        for motif in motifsExplicitesSuffixes {
            if let resultat = extraire(titre, motif: motif, maxNumero: 4000) {
                return resultat
            }
        }
        return nil
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
        while let derniere = base.last, ",;:-–—([".contains(derniere) {
            base.removeLast()
        }
        base = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard base.count >= 2 else { return nil }
        return (base, numero)
    }

    /// Vrai si deux noms de série désignent la même (comparaison souple).
    static func memeSerie(_ un: String, _ deux: String) -> Bool {
        let a = cleSerie(un)
        let b = cleSerie(deux)
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
        return estExtensionEdition(a, de: b) || estExtensionEdition(b, de: a)
    }

    /// La comparaison tolère uniquement un suffixe qui décrit une édition.
    /// Ainsi « Dragon Ball - Édition Deluxe » rejoint « Dragon Ball »,
    /// tandis que « Dragon Ball Super » et « Naruto Gaiden » restent des
    /// séries distinctes.
    private static func estExtensionEdition(_ long: String, de court: String) -> Bool {
        let prefixe = court + " "
        guard long.hasPrefix(prefixe) else { return false }
        let suffixe = String(long.dropFirst(prefixe.count))
        return suffixesEdition.contains { suffixe == $0 || suffixe.hasPrefix($0 + " ") }
    }

    private static let suffixesEdition = [
        "edition", "edicion", "edizione", "edicao", "editie", "ausgabe",
        "utgava", "wydanie", "izdanie", "издание",
        "deluxe", "collector", "collectors", "perfect", "perfecte",
        "omnibus", "integrale", "complete", "definitive", "ultimate",
        "prestige", "anniversary", "special edition", "new edition",
        "hardcover", "paperback", "poche", "grand format", "color",
        "couleur", "black edition", "kanzenban", "bunko",
    ]

    /// Clé stable, insensible aux accents, à la casse et à la ponctuation,
    /// mais qui conserve les mots : c'est leur frontière qui empêche une simple
    /// sous-chaîne de devenir une preuve d'identité.
    private static func cleSerie(_ texte: String) -> String {
        TexteUtil.normaliser(texte)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

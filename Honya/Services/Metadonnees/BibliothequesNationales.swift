import Foundation

/// Les bibliothèques nationales : le filet sous les catalogues commerciaux.
///
/// Dans chaque pays, le dépôt légal fait entrer TOUT ce qui paraît au
/// catalogue de la bibliothèque nationale — éditions de clubs, petits
/// éditeurs, tirages que Google, Apple et OpenLibrary ignorent. Le groupe
/// d'enregistrement de l'ISBN dit le pays ; on interroge la bibliothèque de
/// ce pays. Toutes celles branchées ici ont une API publique, gratuite et
/// sans clé — vérifiées une à une sur pièce :
///
///   France     BnF      SRU, Dublin Core
///   Allemagne  DNB      SRU, Dublin Core
///   Japon      openBD   JSON, puis NDL en SRU Dublin Core (échappé)
///   Suède      LIBRIS   JSON
///   Pologne    BN       JSON
///
/// Seule la BnF sert aussi les couvertures, par l'identifiant ark de la
/// notice. Pour les autres, l'agrégateur emprunte ensuite l'image d'une autre
/// édition par une recherche de titre.
struct BibliothequeNationaleProvider {

    func parISBN(_ isbn: String) async -> ResultatRecherche? {
        let propre = ISBNUtil.normaliser(isbn)
        guard propre.count == 13 else { return nil }
        let corps = String(propre.dropFirst(3))

        if propre.hasPrefix("979") {
            if corps.hasPrefix("10") { return await bnf(propre) }
            return nil
        }
        switch corps.first {
        case "2": return await bnf(propre)
        case "3": return await dnb(propre)
        case "4":
            // openBD d'abord : des deux, c'est la seule qui donne une
            // couverture — le service d'images de la NDL nous est fermé.
            if let trouve = await openBD(propre) { return trouve }
            return await ndl(propre)
        case "8" where corps.hasPrefix("83"): return await bnPologne(propre)
        case "9" where corps.hasPrefix("91"): return await libris(propre)
        default: return nil
        }
    }

    // MARK: - France · BnF

    private func bnf(_ isbn: String) async -> ResultatRecherche? {
        var composants = URLComponents(string: "https://catalogue.bnf.fr/api/SRU")!
        composants.queryItems = [
            .init(name: "version", value: "1.2"),
            .init(name: "operation", value: "searchRetrieve"),
            .init(name: "query", value: "bib.isbn adj \"\(isbn)\""),
            .init(name: "recordSchema", value: "dublincore"),
            .init(name: "maximumRecords", value: "1"),
        ]
        return await dublinCore(composants.url, isbn: isbn, source: "BnF", echappe: false)
    }

    // MARK: - Allemagne · DNB

    private func dnb(_ isbn: String) async -> ResultatRecherche? {
        var composants = URLComponents(string: "https://services.dnb.de/sru/dnb")!
        composants.queryItems = [
            .init(name: "version", value: "1.1"),
            .init(name: "operation", value: "searchRetrieve"),
            .init(name: "query", value: "isbn=\(isbn)"),
            .init(name: "recordSchema", value: "oai_dc"),
            .init(name: "maximumRecords", value: "1"),
        ]
        return await dublinCore(composants.url, isbn: isbn, source: "DNB", echappe: false)
    }

    // MARK: - Japon · openBD

    /// Le registre des éditeurs japonais : titre, auteur, date ET couverture,
    /// libre d'accès et sans clé. La NDL référence tout par dépôt légal mais
    /// ne nous laisse pas atteindre ses vignettes ; openBD, si.
    private func openBD(_ isbn: String) async -> ResultatRecherche? {
        guard let url = URL(string: "https://api.openbd.jp/v1/get?isbn=\(isbn)"),
              let donnees = await charger(url),
              let tableau = (try? JSONSerialization.jsonObject(with: donnees)) as? [Any],
              // Un code inconnu ramène `[null]` : la liste existe, son contenu non.
              let premier = tableau.first as? [String: Any],
              let resume = premier["summary"] as? [String: Any],
              let titre = resume["title"] as? String, !titre.isEmpty
        else { return nil }

        // « 尾田,栄一郎,1975- » : virgules de catalogage, dates en queue.
        let auteur = (resume["author"] as? String)?
            .components(separatedBy: ",")
            .filter { $0.first?.isNumber != true }
            .joined()

        return fiche(
            titre: titre,
            auteur: auteur,
            date: resume["pubdate"] as? String,
            langue: "ja",
            isbn: isbn,
            source: "openBD",
            couverture: (resume["cover"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        )
    }

    // MARK: - Japon · NDL

    private func ndl(_ isbn: String) async -> ResultatRecherche? {
        var composants = URLComponents(string: "https://ndlsearch.ndl.go.jp/api/sru")!
        composants.queryItems = [
            .init(name: "operation", value: "searchRetrieve"),
            .init(name: "query", value: "isbn=\(isbn)"),
            .init(name: "recordSchema", value: "dc"),
            .init(name: "maximumRecords", value: "1"),
        ]
        // La NDL renvoie le Dublin Core ÉCHAPPÉ à l'intérieur du SRU
        // (&lt;dc:title&gt;…), il faut le déplier avant de le lire.
        return await dublinCore(composants.url, isbn: isbn, source: "NDL", echappe: true)
    }

    // MARK: - Suède · LIBRIS

    private func libris(_ isbn: String) async -> ResultatRecherche? {
        guard let url = URL(string: "https://libris.kb.se/xsearch?query=isbn:\(isbn)&format=json&n=1"),
              let json = await chargerJSON(url),
              let xsearch = json["xsearch"] as? [String: Any],
              let liste = xsearch["list"] as? [[String: Any]],
              let premier = liste.first,
              let titre = premier["title"] as? String, !titre.isEmpty
        else { return nil }

        let date = (premier["date"] as? [String])?.first ?? premier["date"] as? String
        return fiche(
            titre: titre,
            auteur: premier["creator"] as? String,
            date: date,
            langue: "sv",
            isbn: isbn,
            source: "LIBRIS"
        )
    }

    // MARK: - Pologne · BN

    private func bnPologne(_ isbn: String) async -> ResultatRecherche? {
        guard let url = URL(string: "https://data.bn.org.pl/api/networks/bibs.json?isbnIssn=\(isbn)&limit=1"),
              let json = await chargerJSON(url),
              let bibs = json["bibs"] as? [[String: Any]],
              let premier = bibs.first,
              let titre = premier["title"] as? String, !titre.isEmpty
        else { return nil }

        return fiche(
            titre: titre,
            auteur: premier["author"] as? String,
            date: premier["publicationYear"] as? String,
            langue: "pl",
            isbn: isbn,
            source: "BN"
        )
    }

    // MARK: - Le socle Dublin Core (BnF, DNB, NDL)

    private func dublinCore(
        _ url: URL?, isbn: String, source: String, echappe: Bool
    ) async -> ResultatRecherche? {
        guard let url,
              let brut = await chargerTexte(url),
              !brut.contains("numberOfRecords>0<")
        else { return nil }

        let xml = echappe ? deplier(brut) : brut
        guard let titre = balise("dc:title", dans: xml) else { return nil }

        return fiche(
            titre: titre,
            auteur: balise("dc:creator", dans: xml),
            date: balise("dc:date", dans: xml),
            langue: balise("dc:language", dans: xml).map(codeLangue),
            isbn: isbn,
            source: source,
            couverture: source == "BnF" ? couvertureBnF(xml) : nil
        )
    }

    /// La couverture de la BnF, tirée de l'identifiant ark de la notice.
    ///
    /// C'est souvent la SEULE image d'une édition française que Google, Apple
    /// et Open Library ignorent — et c'est elle qui tient la promesse : un
    /// livre trouvé montre sa couverture. Vérifié sur pièce, en haute
    /// définition, sans clé.
    ///
    /// Quand la notice n'a pas d'image, le service répond une erreur et non un
    /// visuel de remplacement : aucun risque d'afficher la couverture d'un
    /// autre livre, le chargement échoue simplement.
    private func couvertureBnF(_ xml: String) -> String? {
        guard let plage = xml.range(
            of: "ark:/12148/cb[0-9a-z]+", options: .regularExpression
        ) else { return nil }
        return "https://catalogue.bnf.fr/couverture"
            + "?&appName=NE&idArk=" + xml[plage] + "&couverture=1"
    }

    /// La fiche commune, avec le nettoyage du catalogage.
    private func fiche(
        titre titreBrut: String, auteur auteurBrut: String?,
        date: String?, langue: String?, isbn: String, source: String,
        couverture: String? = nil
    ) -> ResultatRecherche? {
        // « Titre. 1 / mention de responsabilité » : la barre oblique du
        // catalogage porte les contributeurs, seul le titre nous regarde ;
        // et le point avant un numéro de tome gêne la tomaison.
        var titre = titreBrut.components(separatedBy: " / ").first ?? titreBrut
        titre = titre.trimmingCharacters(in: CharacterSet(charactersIn: " .\n\t"))
        titre = titre.replacingOccurrences(
            of: #"\.\s+(\d{1,4})\s*$"#, with: " $1", options: .regularExpression
        )
        guard !titre.isEmpty else { return nil }

        return ResultatRecherche(
            id: "\(source.lowercased()):\(isbn)",
            titre: titre,
            auteurs: [auteurBrut.map(nettoyerAuteur)].compactMap { $0 }.filter { !$0.isEmpty },
            annee: date.flatMap { Int($0.filter(\.isNumber).prefix(4)) },
            couvertureURL: couverture,
            isbn: isbn,
            langue: langue,
            source: source
        )
    }

    // MARK: - Aides

    private func chargerTexte(_ url: URL) async -> String? {
        guard let donnees = await charger(url) else { return nil }
        return String(data: donnees, encoding: .utf8)
    }

    private func chargerJSON(_ url: URL) async -> [String: Any]? {
        guard let donnees = await charger(url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: donnees)) as? [String: Any]
    }

    /// Deux essais, jamais un seul.
    ///
    /// C'est le dernier recours de toute la chaîne : quand il échoue, le livre
    /// est déclaré introuvable et le lecteur repart en croyant qu'aucun
    /// catalogue au monde ne le connaît. Or une seconde d'indisponibilité
    /// suffisait à le condamner — constaté sur une notice qui est revenue
    /// intacte à l'essai suivant. Une bibliothèque nationale mérite qu'on
    /// frappe deux fois.
    private func charger(_ url: URL) async -> Data? {
        for essai in 0..<2 {
            if essai > 0 { try? await Task.sleep(for: .milliseconds(400)) }
            var requete = URLRequest(url: url)
            requete.timeoutInterval = 12
            guard let (donnees, reponse) = try? await Reseau.catalogues.data(for: requete),
                  (reponse as? HTTPURLResponse)?.statusCode == 200
            else { continue }
            return donnees
        }
        return nil
    }

    private func balise(_ nom: String, dans xml: String) -> String? {
        guard let plage = xml.range(
            of: "<\(nom)[^>]*>([^<]+)</\(nom)>", options: .regularExpression
        ) else { return nil }
        let morceau = String(xml[plage])
        guard let debut = morceau.range(of: ">"),
              let fin = morceau.range(of: "</", options: .backwards)
        else { return nil }
        return String(morceau[debut.upperBound..<fin.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func deplier(_ texte: String) -> String {
        texte
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    /// « King, Stephen (1947-....). Auteur du texte » → « Stephen King » ;
    /// « Rowling, J. K., 1965- » → « J. K. Rowling » ;
    /// « 尾田栄一郎∥著 » → « 尾田栄一郎 ».
    private func nettoyerAuteur(_ brut: String) -> String {
        var nom = brut.components(separatedBy: "∥").first ?? brut
        nom = nom.components(separatedBy: ". ").first ?? nom
        if let parenthese = nom.range(of: " (") {
            nom = String(nom[..<parenthese.lowerBound])
        }
        // Les dates traînent en queue : « Rowling, J. K., 1965- ».
        let morceaux = nom.components(separatedBy: ", ")
            .filter { $0.first?.isNumber != true }
        if morceaux.count == 2 {
            return "\(morceaux[1]) \(morceaux[0])".trimmingCharacters(in: .whitespaces)
        }
        return nom.trimmingCharacters(in: .whitespaces)
    }

    /// Les catalogues parlent ISO 639-2 (« fre ») ; l'application, 639-1.
    private func codeLangue(_ brut: String) -> String {
        let table = [
            "fre": "fr", "eng": "en", "spa": "es", "ger": "de", "ita": "it",
            "jpn": "ja", "kor": "ko", "chi": "zh", "por": "pt", "dut": "nl",
            "rus": "ru", "pol": "pl", "swe": "sv", "tur": "tr",
        ]
        return table[brut.lowercased()] ?? String(brut.prefix(2))
    }
}

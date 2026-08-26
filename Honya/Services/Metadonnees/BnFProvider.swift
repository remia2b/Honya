import Foundation

/// Le catalogue général de la Bibliothèque nationale de France.
///
/// C'est le filet sous tous les autres : le dépôt légal étant obligatoire,
/// TOUT ce qui paraît en France y figure — éditions de clubs, petits
/// éditeurs, tirages que Google, Apple et OpenLibrary ignorent. L'API SRU
/// est publique, gratuite et sans clé.
///
/// La BnF ne fournit pas d'image de couverture : elle donne le titre,
/// l'auteur et l'année, et l'agrégateur va ensuite emprunter la couverture
/// d'une autre édition par une recherche de titre.
struct BnFProvider {

    func parISBN(_ isbn: String) async -> ResultatRecherche? {
        let propre = ISBNUtil.normaliser(isbn)
        var composants = URLComponents(string: "https://catalogue.bnf.fr/api/SRU")!
        composants.queryItems = [
            .init(name: "version", value: "1.2"),
            .init(name: "operation", value: "searchRetrieve"),
            .init(name: "query", value: "bib.isbn adj \"\(propre)\""),
            .init(name: "recordSchema", value: "dublincore"),
            .init(name: "maximumRecords", value: "1"),
        ]
        guard let url = composants.url else { return nil }

        var requete = URLRequest(url: url)
        requete.timeoutInterval = 12
        guard let (donnees, reponse) = try? await URLSession.shared.data(for: requete),
              (reponse as? HTTPURLResponse)?.statusCode == 200,
              let xml = String(data: donnees, encoding: .utf8),
              xml.contains("<srw:numberOfRecords>0<") == false
        else { return nil }

        guard let titreBrut = balise("dc:title", dans: xml) else { return nil }

        // « The beginning after the end. 1 / histoire, TurtleMe ; dessin,
        // Fuyuki23 » : le catalogage français colle la mention de
        // responsabilité après une barre oblique. Seul le titre nous regarde.
        var titre = titreBrut.components(separatedBy: " / ").first ?? titreBrut
        titre = titre.trimmingCharacters(in: .whitespacesAndNewlines)
        // « Titre. 1 » : le point avant le numéro de tome gêne la tomaison.
        titre = titre.replacingOccurrences(
            of: #"\.\s+(\d{1,4})\s*$"#, with: " $1", options: .regularExpression
        )
        guard !titre.isEmpty else { return nil }

        return ResultatRecherche(
            id: "bnf:\(propre)",
            titre: titre,
            auteurs: [balise("dc:creator", dans: xml).map(nettoyerAuteur)].compactMap { $0 },
            resume: nil,
            annee: balise("dc:date", dans: xml).flatMap { Int($0.prefix(4)) },
            isbn: propre,
            langue: balise("dc:language", dans: xml).map(codeLangue),
            source: "BnF"
        )
    }

    // MARK: - Lecture du Dublin Core

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

    /// « King, Stephen (1947-....). Auteur du texte » → « Stephen King ».
    private func nettoyerAuteur(_ brut: String) -> String {
        var nom = brut.components(separatedBy: ". ").first ?? brut
        if let parenthese = nom.range(of: " (") {
            nom = String(nom[..<parenthese.lowerBound])
        }
        let morceaux = nom.components(separatedBy: ", ")
        if morceaux.count == 2 {
            return "\(morceaux[1]) \(morceaux[0])".trimmingCharacters(in: .whitespaces)
        }
        return nom.trimmingCharacters(in: .whitespaces)
    }

    /// La BnF parle ISO 639-2 (« fre ») ; l'application, 639-1 (« fr »).
    private func codeLangue(_ brut: String) -> String {
        let table = [
            "fre": "fr", "eng": "en", "spa": "es", "ger": "de", "ita": "it",
            "jpn": "ja", "kor": "ko", "chi": "zh", "por": "pt", "dut": "nl",
            "rus": "ru", "pol": "pl", "swe": "sv", "tur": "tr",
        ]
        return table[brut.lowercased()] ?? String(brut.prefix(2))
    }
}

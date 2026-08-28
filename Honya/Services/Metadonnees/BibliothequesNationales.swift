import Foundation

/// Les bibliothèques nationales : le filet sous les catalogues commerciaux.
///
/// Le dépôt légal référence de nombreuses éditions de clubs, de petits
/// éditeurs et des tirages que Google, Apple et Open Library ignorent. Le
/// groupe d'enregistrement de l'ISBN permet de choisir le catalogue national
/// le plus pertinent parmi ceux intégrés. Ils exposent tous une API publique,
/// gratuite et sans clé :
///
///   France     BnF      SRU, Dublin Core
///   Monde      Sudoc    ISBN -> PPN, puis UNIMARC XML
///   Allemagne  DNB      SRU, Dublin Core
///   Japon      openBD   JSON, puis NDL en SRU Dublin Core (échappé)
///   Suède      LIBRIS   JSON
///   Pologne    BN       JSON
///
/// La BnF et openBD peuvent aussi servir une couverture. Sans image portant
/// l'ISBN exact, Honya laisse la couverture vide plutôt que d'en certifier une
/// provenant d'une autre édition.
struct BibliothequeNationaleProvider: Sendable {

    func parISBN(_ isbn: String) async -> ResultatRecherche? {
        guard await CadenceBibliotheques.partage.attendre() else { return nil }
        let propre = ISBNUtil.normaliser(isbn)
        guard propre.count == 13, !Task.isCancelled else { return nil }
        let corps = String(propre.dropFirst(3))

        // Sudoc et le catalogue du pays sont indépendants. Les lancer
        // ensemble évite d'ajouter deux appels réseau Sudoc à la latence de
        // la bibliothèque nationale, tout en conservant la notice nationale
        // comme source prioritaire lors de la fusion.
        async let noticeSudoc: ResultatRecherche? = sudoc(propre)

        let noticeNationale: ResultatRecherche?
        if propre.hasPrefix("979") {
            if corps.hasPrefix("10") {
                noticeNationale = await bnf(propre)
            } else {
                noticeNationale = nil
            }
        } else {
            switch corps.first {
            case "2": noticeNationale = await bnf(propre)
            case "3": noticeNationale = await dnb(propre)
            case "4":
            // openBD d'abord : des deux, c'est la seule qui donne une
            // couverture — le service d'images de la NDL nous est fermé.
                if let openBD = await openBD(propre) {
                    noticeNationale = openBD
                } else {
                    noticeNationale = await ndl(propre)
                }
            case "8" where corps.hasPrefix("83"):
                noticeNationale = await bnPologne(propre)
            case "9" where corps.hasPrefix("91"):
                noticeNationale = await libris(propre)
            default:
                noticeNationale = nil
            }
        }

        // Le Sudoc ne se limite pas aux publications françaises : son réseau
        // de bibliothèques décrit aussi de très nombreuses éditions importées.
        // Il complète donc la notice nationale quel que soit le groupe ISBN.
        // C'est notamment lui qui connaît
        // 9782749958194 (Instinct, tome 2), y compris quand Google est sans
        // quota et qu'Apple, Open Library et la BnF n'ont pas cette édition.
        guard !Task.isCancelled else { return nil }
        let complementSudoc = await noticeSudoc
        guard var principale = noticeNationale else { return complementSudoc }
        guard let complement = complementSudoc else { return principale }

        if principale.auteurs.isEmpty { principale.auteurs = complement.auteurs }
        if (complement.resume?.count ?? 0) > (principale.resume?.count ?? 0) {
            principale.resume = complement.resume
        }
        if principale.pages == nil { principale.pages = complement.pages }
        if principale.annee == nil { principale.annee = complement.annee }
        if principale.couvertureURL == nil {
            principale.couvertureURL = complement.couvertureURL
        }
        if principale.langue == nil { principale.langue = complement.langue }
        if principale.type == .livre, complement.type != .livre {
            principale.type = complement.type
        }
        for genre in complement.genres where !principale.genres.contains(genre) {
            principale.genres.append(genre)
        }
        for (langue, titre) in complement.titresParLangue
            where principale.titresParLangue[langue] == nil {
            principale.titresParLangue[langue] = titre
        }
        return principale
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

    // MARK: - Monde · Sudoc (Abes)

    /// Le service ISBN -> PPN localise d'abord la notice, puis l'exposition
    /// UNIMARC XML fournit la fiche bibliographique complète. Deux appels sont
    /// nécessaires ; ils partent en parallèle des catalogues plus rapides.
    private func sudoc(_ isbn: String) async -> ResultatRecherche? {
        guard let index = URL(string:
            "https://www.sudoc.fr/services/isbn2ppn/\(isbn)&format=text/json"
        ),
              let json = await chargerJSON(index),
              let ppn = premierPPN(dans: json),
              let url = URL(string: "https://www.sudoc.fr/\(ppn).xml"),
              let xml = await chargerTexte(url)
        else { return nil }

        let titreBloc = blocs(tag: "200", dans: xml).first
        guard let titreBase = titreBloc.flatMap({ sousChamps("a", dans: $0).first }),
              !titreBase.isEmpty
        else { return nil }

        var titre = titreBase
        if let partie = titreBloc.flatMap({ sousChamps("h", dans: $0).first }),
           !partie.isEmpty {
            // Le sous-champ UNIMARC contient déjà la désignation publiée
            // (« 2 », « Band 2 », « 第2巻 »…). Ne jamais y injecter le mot
            // français « Tome » : il corromprait les titres des autres langues.
            let designation = partie.trimmingCharacters(in: .whitespacesAndNewlines)
            // Un sous-champ réduit au numéro reste une tomaison explicite.
            // Le marqueur universel « # » conserve cette information sans
            // traduire artificiellement le titre en français.
            titre += designation.allSatisfy(\.isNumber)
                ? " #\(designation)"
                : " \(designation)"
        } else if let sousTitre = titreBloc.flatMap({ sousChamps("e", dans: $0).first }),
                  !sousTitre.isEmpty {
            titre += ": \(sousTitre)"
        }

        var auteurs: [String] = []
        for etiquette in ["700", "701"] {
            for bloc in blocs(tag: etiquette, dans: xml) {
                guard let nom = sousChamps("a", dans: bloc).first, !nom.isEmpty else { continue }
                if let prenom = sousChamps("b", dans: bloc).first, !prenom.isEmpty {
                    auteurs.append("\(prenom) \(nom)")
                } else {
                    auteurs.append(nom)
                }
            }
        }
        if auteurs.isEmpty,
           let responsabilite = titreBloc.flatMap({ sousChamps("f", dans: $0).first }),
           !responsabilite.isEmpty {
            auteurs = [responsabilite]
        }

        let langueBrute = blocs(tag: "101", dans: xml)
            .first.flatMap { sousChamps("a", dans: $0).first }
        // Le préfixe ISBN identifie une agence/zone d'enregistrement, jamais
        // avec certitude la langue du contenu. Seule la zone UNIMARC 101 est
        // une preuve assez forte pour étiqueter et localiser cette édition.
        let langue = langueBrute.flatMap(codeLangue)
        let resume = blocs(tag: "330", dans: xml)
            .first.flatMap { sousChamps("a", dans: $0).first }
        let genres = blocs(tag: "608", dans: xml)
            .flatMap { sousChamps("a", dans: $0) }
        let publication = blocs(tag: "214", dans: xml)
            .first.flatMap { sousChamps("d", dans: $0).first }
        let pagination = blocs(tag: "215", dans: xml)
            .first.flatMap { sousChamps("a", dans: $0).first }

        var resultat = ResultatRecherche(
            id: "sudoc:\(ppn)",
            titre: titre,
            auteurs: auteurs,
            resume: resume,
            pages: pagination.flatMap { nombreDePages($0) },
            annee: publication.flatMap { extraireAnnee($0) },
            genres: genres,
            isbn: isbn,
            langue: langue,
            source: "Sudoc"
        )
        if let langue { resultat.titresParLangue[langue] = titre }

        let sujets = genres.joined(separator: " ").lowercased()
        if sujets.contains("manga") {
            resultat.type = .manga
        } else if sujets.contains("bande dessin") || sujets.contains("comic")
                    || sujets.contains("graphic") {
            resultat.type = .bd
        }
        return resultat
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
        let langue = premiereChaine(premier["language"]).flatMap(codeLangue)
        return fiche(
            titre: titre,
            auteur: premier["creator"] as? String,
            date: date,
            // LIBRIS décrit aussi des éditions étrangères conservées en
            // Suède. Le pays du catalogue n'est donc jamais la langue du
            // livre : `9789147146482`, par exemple, est explicitement anglais.
            langue: langue,
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
            // La BN polonaise expose la langue en toutes lettres (`angielski`,
            // `francuski`…). Une notice présente en Pologne n'est pas pour
            // autant une édition polonaise.
            langue: premiereChaine(premier["language"]).flatMap(codeLangue),
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
        let couverture: String?
        if source == "BnF" {
            couverture = await couvertureBnF(isbn)
        } else {
            couverture = nil
        }

        return fiche(
            titre: titre,
            auteur: balise("dc:creator", dans: xml),
            date: balise("dc:date", dans: xml),
            langue: balise("dc:language", dans: xml).flatMap(codeLangue),
            isbn: isbn,
            source: source,
            couverture: couverture
        )
    }

    /// La couverture de la BnF, demandée sur l'EAN exact de la notice.
    ///
    /// C'est souvent la SEULE image d'une édition française que Google, Apple
    /// et Open Library ignorent — et c'est elle qui tient la promesse : un
    /// livre trouvé montre sa couverture. Vérifié sur pièce, en haute
    /// définition, sans clé.
    ///
    /// Quand la notice n'a pas d'image, le service répond une erreur et non un
    /// visuel de remplacement : aucun risque d'afficher la couverture d'un
    /// autre livre, le chargement échoue simplement.
    private func couvertureBnF(_ isbn: String) async -> String? {
        var composants = URLComponents(
            string: "https://openapi.bnf.fr/couverture/image/image/recupererImage"
        )
        composants?.queryItems = [
            .init(name: "EAN", value: isbn),
            .init(name: "couverture", value: "1"),
        ]
        guard let url = composants?.url,
              let donnees = await charger(url),
              estImage(donnees) else { return nil }
        return url.absoluteString
    }

    private func estImage(_ donnees: Data) -> Bool {
        donnees.starts(with: [0xFF, 0xD8, 0xFF])
            || donnees.starts(with: [0x89, 0x50, 0x4E, 0x47])
            || donnees.starts(with: [0x47, 0x49, 0x46, 0x38])
            || donnees.starts(with: [0x52, 0x49, 0x46, 0x46])
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
            of: #"\.\s+(\d{1,4})\s*$"#, with: " #$1", options: .regularExpression
        )
        guard !titre.isEmpty else { return nil }

        var resultat = ResultatRecherche(
            id: "\(source.lowercased()):\(isbn)",
            titre: titre,
            auteurs: [auteurBrut.map(nettoyerAuteur)].compactMap { $0 }.filter { !$0.isEmpty },
            annee: date.flatMap { Int($0.filter(\.isNumber).prefix(4)) },
            couvertureURL: couverture,
            isbn: isbn,
            langue: langue,
            source: source
        )
        if source == "BnF", couverture != nil {
            let jour = String(
                ISO8601DateFormatter().string(from: Date()).prefix(10)
            )
            resultat.attributionCouverture =
                "Bibliothèque nationale de France · \(jour)"
        }
        return resultat
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

    /// Dublin Core peut sérialiser une valeur unique comme une chaîne ou une
    /// liste. Garder ce petit dépliage au même endroit évite de retomber sur la
    /// langue du catalogue quand le format varie d'une notice à l'autre.
    private func premiereChaine(_ valeur: Any?) -> String? {
        if let texte = valeur as? String { return texte }
        return (valeur as? [String])?.first
    }

    /// Le service ISBN2PPN peut répondre avec un résultat unique ou une liste.
    /// On descend donc sa petite structure JSON sans figer le décodage sur une
    /// seule forme, tout en n'acceptant qu'un véritable identifiant Sudoc.
    private func premierPPN(dans valeur: Any) -> String? {
        if let objet = valeur as? [String: Any] {
            if let ppn = objet["ppn"] as? String,
               ppn.range(of: #"^[0-9]{8}[0-9X]$"#, options: .regularExpression) != nil {
                return ppn
            }
            for enfant in objet.values {
                if let ppn = premierPPN(dans: enfant) { return ppn }
            }
        } else if let liste = valeur as? [Any] {
            for enfant in liste {
                if let ppn = premierPPN(dans: enfant) { return ppn }
            }
        }
        return nil
    }

    /// Tous les champs UNIMARC portant une étiquette donnée.
    private func blocs(tag: String, dans xml: String) -> [String] {
        captures(
            #"<datafield\s+tag="\#(tag)"[^>]*>([\s\S]*?)</datafield>"#,
            dans: xml
        )
    }

    /// Toutes les valeurs d'un sous-champ dans un bloc UNIMARC.
    private func sousChamps(_ code: String, dans bloc: String) -> [String] {
        captures(
            #"<subfield\s+code="\#(code)"[^>]*>([\s\S]*?)</subfield>"#,
            dans: bloc
        )
        .map(deplier)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    }

    private func captures(_ motif: String, dans texte: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: motif) else { return [] }
        let plage = NSRange(texte.startIndex..., in: texte)
        return expression.matches(in: texte, range: plage).compactMap { resultat in
            guard resultat.numberOfRanges > 1,
                  let capture = Range(resultat.range(at: 1), in: texte)
            else { return nil }
            return String(texte[capture])
        }
    }

    private func extraireAnnee(_ texte: String) -> Int? {
        guard let plage = texte.range(
            of: #"(?:18|19|20|21)[0-9]{2}"#,
            options: .regularExpression
        ) else { return nil }
        return Int(texte[plage])
    }

    private func nombreDePages(_ texte: String) -> Int? {
        let motif = #"([0-9]{1,5})\s*(?:p\.|pages?\b)"#
        guard let expression = try? NSRegularExpression(
            pattern: motif, options: .caseInsensitive
        ),
              let resultat = expression.firstMatch(
                in: texte, range: NSRange(texte.startIndex..., in: texte)
              ),
              let capture = Range(resultat.range(at: 1), in: texte)
        else { return nil }
        return Int(texte[capture])
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
            guard !Task.isCancelled else { return nil }
            if essai > 0 {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return nil }
            }
            var requete = URLRequest(url: url)
            requete.timeoutInterval = 12
            guard let (donnees, reponse) = try? await Reseau.catalogues.data(for: requete),
                  (reponse as? HTTPURLResponse)?.statusCode == 200
            else { continue }
            guard !Task.isCancelled else { return nil }
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
        return deplier(String(morceau[debut.upperBound..<fin.lowerBound]))
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
    private func codeLangue(_ brut: String) -> String? {
        let table = [
            "fre": "fr", "fra": "fr", "eng": "en", "spa": "es",
            "ger": "de", "deu": "de", "ita": "it", "por": "pt",
            "dut": "nl", "nld": "nl", "swe": "sv", "dan": "da",
            "nor": "no", "fin": "fi", "pol": "pl", "cze": "cs",
            "ces": "cs", "hun": "hu", "rum": "ro", "ron": "ro",
            "gre": "el", "ell": "el", "tur": "tr", "rus": "ru",
            "ukr": "uk", "ara": "ar", "heb": "he", "hin": "hi",
            "tha": "th", "vie": "vi", "ind": "id", "jpn": "ja",
            "kor": "ko", "chi": "zh", "zho": "zh", "cat": "ca",
            "baq": "eu", "eus": "eu",
            // Noms employés par l'API de la Bibliothèque nationale polonaise.
            // Ils sont repliés sans accents juste en dessous.
            "francuski": "fr", "angielski": "en", "hiszpanski": "es",
            "niemiecki": "de", "wloski": "it", "portugalski": "pt",
            "niderlandzki": "nl", "szwedzki": "sv", "dunski": "da",
            "norweski": "no", "finski": "fi", "polski": "pl",
            "czeski": "cs", "wegierski": "hu", "rumunski": "ro",
            "grecki": "el", "turecki": "tr", "rosyjski": "ru",
            "ukrainski": "uk", "arabski": "ar", "hebrajski": "he",
            "tajski": "th", "wietnamski": "vi", "indonezyjski": "id",
            "japonski": "ja", "koreanski": "ko", "chinski": "zh",
            "katalonski": "ca", "baskijski": "eu",
        ]
        let propre = brut.lowercased()
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "pl"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .first.map(String.init) ?? ""
        if let code = table[propre] { return code }
        return Langues.codes.contains(propre) ? propre : nil
    }
}

/// Un scan en rafale ne doit pas devenir une attaque distribuée depuis chaque
/// iPhone. Deux ISBN par seconde au maximum, puis Sudoc et le catalogue du pays
/// travaillent en parallèle pour chacun.
private actor CadenceBibliotheques {
    static let partage = CadenceBibliotheques()
    private var prochainDepart = Date.distantPast

    func attendre() async -> Bool {
        guard !Task.isCancelled else { return false }
        let maintenant = Date()
        let attente = max(0, prochainDepart.timeIntervalSince(maintenant))
        prochainDepart = maintenant.addingTimeInterval(attente + 0.5)
        guard attente > 0 else { return true }
        do {
            try await Task.sleep(for: .seconds(attente))
            return !Task.isCancelled
        } catch {
            return false
        }
    }
}

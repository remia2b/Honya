import Foundation

/// Les catalogues dont les conditions interdisent l'agrégation commerciale
/// restent éteints tant qu'Honya n'a pas obtenu l'accord correspondant et
/// configuré l'attribution exigée. Une clé API n'est pas une licence.
enum SourcesCatalogue {
    private static func autorisee(_ cle: String) -> Bool {
        if let valeur = Bundle.main.object(forInfoDictionaryKey: cle) as? Bool {
            return valeur
        }
        let valeur = Bundle.main.object(forInfoDictionaryKey: cle) as? String
        return valeur?.uppercased() == "YES" || valeur == "1"
    }

    static var googleBooks: Bool { autorisee("HONYA_GOOGLE_BOOKS_LICENSED") }
    static var appleBooks: Bool { autorisee("HONYA_APPLE_BOOKS_PROMO_COMPLIANT") }
    static var aniList: Bool { autorisee("HONYA_ANILIST_LICENSED") }
}

/// Cache de session des recherches : la grille des tomes et le résolveur
/// posent les mêmes questions en boucle — inutile de repayer le quota Google.
actor CacheRecherche {
    static let partage = CacheRecherche()
    private var entrees: [String: [ResultatRecherche]] = [:]
    private var editionsISBN: [String: ResultatRecherche] = [:]

    func lire(_ cle: String) -> [ResultatRecherche]? { entrees[cle] }

    func ecrire(_ cle: String, _ valeur: [ResultatRecherche]) {
        // On ne mémorise pas les échecs : un quota épuisé mérite un nouvel essai.
        guard !valeur.isEmpty else { return }
        entrees[cle] = valeur
    }

    func lireISBN(_ isbn: String) -> ResultatRecherche? { editionsISBN[isbn] }

    func ecrireISBN(_ isbn: String, _ valeur: ResultatRecherche) {
        editionsISBN[isbn] = valeur
    }

    /// Une actualisation demandée par le lecteur doit réellement retourner au
    /// réseau. Le cache reste strictement un cache de session, jamais une base
    /// faisant autorité sur les prochaines sorties.
    func vider() {
        entrees.removeAll(keepingCapacity: true)
        editionsISBN.removeAll(keepingCapacity: true)
    }
}

/// La cascade de sources élargit fortement la couverture du catalogue, sans
/// prétendre à l'exhaustivité qu'aucune API publique ne peut garantir.
struct AgregateurMetadonnees: Sendable {
    static let partage = AgregateurMetadonnees()

    private let appleBooks = AppleBooksProvider()
    private let google = GoogleBooksProvider()
    private let openLibrary = OpenLibraryProvider()
    private let aniList = AniListProvider()
    private let bibliotheques = BibliothequeNationaleProvider()

    func viderCache() async {
        await CacheRecherche.partage.vider()
    }

    // MARK: Recherche texte

    func rechercherLivres(_ requete: String, langue: String?) async -> [ResultatRecherche] {
        let cle = "livres|" + requete.lowercased() + "|" + (langue ?? "-")
        if let connu = await CacheRecherche.partage.lire(cle) { return connu }

        // Les catalogues se complètent : attendre que l'un soit vide cachait
        // tout ce que les deux autres connaissaient. Ils partent ensemble,
        // puis le tri place les éditions locales et complètes en premier.
        let langueLecteur = langue ?? Langues.codeAppareil
        let pays = Langues.storefront(pourLangue: langueLecteur)
        async let dApple: [ResultatRecherche] = rechercherAppleSiUtile(
            requete,
            pays: pays,
            langueLecteur: langueLecteur,
            langueDemandee: langue
        )
        async let deGoogle: [ResultatRecherche] = rechercherGoogleSiAutorise(
            requete, langue: langue
        )
        async let dOpenLibrary: [ResultatRecherche] =
            (try? await openLibrary.rechercher(requete, langue: langue)) ?? []
        let lots = await (dApple, deGoogle, dOpenLibrary)
        guard !Task.isCancelled else { return [] }
        let resultatsBruts = lots.0 + lots.1 + lots.2
        // Un storefront ou un filtre serveur n'est pas une preuve de langue :
        // chaque résultat conservé doit annoncer explicitement celle demandée.
        // Cela écarte notamment les ebooks Apple dont l'API ne publie aucune
        // langue, plutôt que de présenter une couverture anglaise comme locale.
        let resultats: [ResultatRecherche]
        if let langue {
            let code = langue.lowercased()
                .split(whereSeparator: { $0 == "-" || $0 == "_" })
                .first
                .map { String($0) } ?? langue.lowercased()
            resultats = resultatsBruts.filter { resultat in
                guard let langueResultat = resultat.langue else { return false }
                let codeResultat = langueResultat.lowercased()
                    .split(whereSeparator: { $0 == "-" || $0 == "_" })
                    .first
                    .map { String($0) } ?? langueResultat.lowercased()
                return codeResultat == code
            }
        } else {
            resultats = resultatsBruts
        }
        let tries = dedoublonner(
            trierParPertinence(resultats, requete: requete, langue: langue)
        )
        await CacheRecherche.partage.ecrire(cle, tries)
        return tries
    }

    /// Passe plus profonde réservée à une fiche de série. La recherche
    /// interactive reste légère, tandis que ce parcours pagine Google et
    /// demande jusqu'à 100 works à Open Library pour les longues collections.
    func rechercherEditionsSerie(
        _ requete: String, langue: String
    ) async -> [ResultatRecherche] {
        let cle = "serie-editions|" + requete.lowercased() + "|" + langue
        if let connu = await CacheRecherche.partage.lire(cle) { return connu }

        async let deGoogle = rechercherSerieGoogleSiAutorise(
            requete, langue: langue
        )
        async let dOpenLibrary = (try? await openLibrary.rechercherSerie(
            requete, langue: langue
        )) ?? []
        let lots = await (deGoogle, dOpenLibrary)
        guard !Task.isCancelled else { return [] }

        let code = langue.lowercased()
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .first.map(String.init) ?? langue.lowercased()
        let locaux = (lots.0 + lots.1).filter { resultat in
            guard let langueResultat = resultat.langue else { return false }
            let codeResultat = langueResultat.lowercased()
                .split(whereSeparator: { $0 == "-" || $0 == "_" })
                .first.map(String.init) ?? langueResultat.lowercased()
            return codeResultat == code
        }
        let tries = dedoublonner(
            trierParPertinence(locaux, requete: requete, langue: langue)
        )
        await CacheRecherche.partage.ecrire(cle, tries)
        return tries
    }

    /// Apple Books expose le pays du storefront, mais pas la langue de chaque
    /// ebook. Quand une langue précise est demandée, ces résultats seraient
    /// nécessairement rejetés par la vérification stricte ci-dessus : ne pas
    /// lancer l'appel économise du temps et le quota Apple.
    private func rechercherAppleSiUtile(
        _ requete: String,
        pays: String,
        langueLecteur: String,
        langueDemandee: String?
    ) async -> [ResultatRecherche] {
        guard SourcesCatalogue.appleBooks, langueDemandee == nil else { return [] }
        return (try? await appleBooks.rechercher(
            requete, pays: pays, langue: langueLecteur
        )) ?? []
    }

    private func rechercherGoogleSiAutorise(
        _ requete: String, langue: String?
    ) async -> [ResultatRecherche] {
        guard SourcesCatalogue.googleBooks else { return [] }
        return (try? await google.rechercher(requete, langue: langue)) ?? []
    }

    private func rechercherSerieGoogleSiAutorise(
        _ requete: String, langue: String
    ) async -> [ResultatRecherche] {
        guard SourcesCatalogue.googleBooks else { return [] }
        return (try? await google.rechercherSerie(requete, langue: langue)) ?? []
    }

    /// Deux éditions du même tome ne doivent apparaître qu'une fois : on garde
    /// la mieux classée (couverture, langue du lecteur…).
    private func dedoublonner(_ resultats: [ResultatRecherche]) -> [ResultatRecherche] {
        var vus = Set<String>()
        return resultats.filter { resultat in
            if let isbn = resultat.isbn.flatMap(ISBNUtil.canonique) {
                return vus.insert("isbn|" + isbn).inserted
            }
            let (base, numero) = Tomaison.decomposer(resultat.titre)
            let auteur = resultat.auteurs.first.map(TexteUtil.normaliser) ?? "-"
            let cle = TexteUtil.normaliser(base) + "|"
                + (numero.map { String($0) } ?? "-") + "|" + auteur
            return vus.insert(cle).inserted
        }
    }

    /// Remonte les titres qui correspondent vraiment à la recherche, et repousse
    /// ceux qu'un lecteur de cette langue ne saurait pas lire.
    private func trierParPertinence(
        _ resultats: [ResultatRecherche],
        requete: String,
        langue: String?
    ) -> [ResultatRecherche] {
        let besoin = requete.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        // En mode « Toutes les langues », le tri garde malgré tout la langue
        // principale de l'appareil comme préférence. Un lecteur francophone
        // ne doit pas voir artificiellement les éditions anglaises remonter.
        let langueLecteur = langue ?? Langues.codeAppareil

        func score(_ r: ResultatRecherche) -> Int {
            var points = 0
            let titre = r.titreAffiche(langueLecteur)
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            if titre == besoin { points += 100 }
            else if titre.hasPrefix(besoin) { points += 60 }
            else if titre.contains(besoin) { points += 40 }
            if r.auteurs.contains(where: {
                $0.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).contains(besoin)
            }) { points += 20 }
            if r.couvertureURL != nil { points += 8 }
            if !r.auteurs.isEmpty { points += 4 }
            // L'édition dans la langue du lecteur passe devant les autres :
            // un francophone doit voir Kana avant VIZ.
            if let langueResultat = r.langue {
                if langueResultat == langueLecteur { points += 30 }
                else { points -= 15 }
            }
            // Un titre illisible pour ce lecteur passe après les autres.
            if !Titres.estLisible(titre, langue: langueLecteur) { points -= 50 }
            return points
        }

        return resultats.enumerated()
            .sorted { a, b in
                let sa = score(a.element), sb = score(b.element)
                return sa == sb ? a.offset < b.offset : sa > sb
            }
            .map(\.element)
    }

    func rechercherMangas(_ requete: String, langue: String? = nil) async -> [ResultatRecherche] {
        let cle = "mangas|" + requete.lowercased() + "|" + (langue ?? "-")
        if let connu = await CacheRecherche.partage.lire(cle) { return connu }
        async let series = rechercherMangasBruts(requete)
        async let editions = editionsMangaLocales(requete, langue: langue)
        let lots = await (series, editions)
        guard !Task.isCancelled else { return [] }
        let localises: [ResultatRecherche]
        if lots.0.isEmpty {
            // Sans licence AniList, la recherche manga reste fonctionnelle à
            // partir des éditions physiques ouvertes : catégories BD/manga ou
            // marqueur de tome explicite.
            localises = lots.1.filter {
                $0.type != .livre || $0.estUnTome
            }
        } else {
            localises = localiserMangas(
                lots.0, avec: lots.1, langue: langue
            )
        }
        let tries = trierParPertinence(localises, requete: requete, langue: langue)
        await CacheRecherche.partage.ecrire(cle, tries)
        return tries
    }

    /// Recherche combinée sans doubler les appels Google/Open Library : la
    /// liste des éditions sert à la fois aux livres/tomes et à localiser les
    /// séries AniList.
    func rechercherTout(_ requete: String, langue: String?) async -> [ResultatRecherche] {
        let cle = "tout|" + requete.lowercased() + "|" + (langue ?? "-")
        if let connu = await CacheRecherche.partage.lire(cle) { return connu }
        async let series = rechercherMangasBruts(requete)
        async let editions = rechercherLivres(requete, langue: langue)
        let lots = await (series, editions)
        guard !Task.isCancelled else { return [] }
        let mangas = trierParPertinence(
            localiserMangas(lots.0, avec: lots.1, langue: langue),
            requete: requete,
            langue: langue
        )
        let combines = mangas + lots.1
        await CacheRecherche.partage.ecrire(cle, combines)
        return combines
    }

    private func rechercherMangasBruts(_ requete: String) async -> [ResultatRecherche] {
        guard SourcesCatalogue.aniList else { return [] }
        let cle = "anilist|" + requete.lowercased()
        if let connu = await CacheRecherche.partage.lire(cle) { return connu }
        let resultats = (try? await aniList.rechercher(requete, langue: nil)) ?? []
        guard !Task.isCancelled else { return [] }
        await CacheRecherche.partage.ecrire(cle, resultats)
        return resultats
    }

    private func editionsMangaLocales(
        _ requete: String, langue: String?
    ) async -> [ResultatRecherche] {
        guard let langue else { return [] }
        return await rechercherLivres(requete, langue: langue)
    }

    /// AniList connaît la structure d'une série ; les catalogues de livres
    /// connaissent ses éditions physiques locales. On ne les fusionne que si
    /// le nom (titre, synonyme ou translittération) ET l'auteur concordent.
    /// Une simple proximité de recherche n'est jamais suffisante.
    private func localiserMangas(
        _ series: [ResultatRecherche],
        avec editions: [ResultatRecherche],
        langue: String?
    ) -> [ResultatRecherche] {
        guard let langue, !editions.isEmpty else { return series }

        return series.map { serie in
            let nomsConnus = ([serie.titre, serie.titreOriginal, serie.romaji]
                .compactMap { $0 })
                + Array(serie.titresParLangue.values)
                + serie.titresAlternatifs
            let basesConnues = nomsConnus.map { Tomaison.decomposer($0).base }
            let compatibles = editions.filter { edition in
                guard AuteursUtil.correspondent(edition.auteurs, serie.auteurs)
                else { return false }
                let baseEdition = Tomaison.decomposer(edition.titre).base
                return basesConnues.contains {
                    Tomaison.memeSerie(baseEdition, $0)
                }
            }
            let edition = compatibles.first {
                Tomaison.decomposer($0.titre).numero == 1
            } ?? compatibles.first
            guard let edition else { return serie }

            var copie = serie
            let titreLocal = Tomaison.decomposer(edition.titre).base
            copie.titresParLangue[langue] = titreLocal
            copie.langue = langue
            copie.couvertureURL = edition.couvertureURL ?? copie.couvertureURL
            if let resume = edition.resume, !resume.isEmpty {
                copie.resume = resume
            }
            for genre in edition.genres where !copie.genres.contains(genre) {
                copie.genres.append(genre)
            }
            copie.source = serie.source + " + " + edition.source
            return copie
        }
    }

    // MARK: ISBN (le scanner passe par ici)

    /// La fiche du code scanné, aussi vite que le réseau le permet.
    ///
    /// Les catalogues sont interrogés EN MÊME TEMPS. En file indienne,
    /// le plus lent imposait son temps à tous : on attendait Google, puis
    /// Apple, puis Open Library, chacun jusqu'à soixante secondes. Ensemble,
    /// l'attente n'est plus que celle du plus lent des trois — et ils sont
    /// coupés à six secondes.
    ///
    /// Ce qui manque encore — la couverture d'une édition rare — se cherche
    /// après, par `couvertureDeSecours`, pour que le livre s'affiche tout de
    /// suite au lieu d'attendre son image.
    func parISBN(_ isbn: String) async -> ResultatRecherche? {
        guard let isbnCanonique = ISBNUtil.canonique(isbn) else { return nil }
        if let connu = await CacheRecherche.partage.lireISBN(isbnCanonique) {
            return connu
        }
        // Le groupe ISBN indique l'agence d'enregistrement de l'éditeur, pas
        // la langue du texte. Il peut router vers un catalogue national, mais
        // ne doit jamais faire passer un livre anglais publié en France pour
        // une édition française.
        let langueLecteur = Langues.codeAppareil
        // La boutique du PAYS DE L'ÉDITION, pas celle du téléphone.
        let pays = Langues.storefrontEdition(isbnCanonique)

        // La bibliothèque nationale part elle aussi tout de suite, mais une
        // fiche commerciale déjà complète n'attend pas son chemin plus long.
        // La tâche annulée vérifie la cancellation entre ses tentatives.
        let dBibliotheque = Task {
            await bibliotheques.parISBN(isbnCanonique)
        }
        // `Task {}` n'est pas automatiquement annulée avec son appelant.
        // Le defer couvre donc aussi une frappe remplacée ou une vue fermée.
        defer { dBibliotheque.cancel() }
        async let deGoogle = parISBNGoogleSiAutorise(isbnCanonique)
        async let dOpenLibrary = (try? openLibrary.parISBN(isbnCanonique)) ?? nil
        let reponsesRapides = [await deGoogle, await dOpenLibrary]
        guard !Task.isCancelled else { return nil }

        if let rapide = fusionnerISBN(
            reponsesRapides, isbn: isbnCanonique, langue: langueLecteur
        ), ficheSuffisante(rapide) {
            dBibliotheque.cancel()
            let complet = complete(rapide, isbn: isbnCanonique)
            await CacheRecherche.partage.ecrireISBN(isbnCanonique, complet)
            return complet
        }

        let reponseNationale = await withTaskCancellationHandler {
            await dBibliotheque.value
        } onCancel: {
            // `Task {}` n'est pas un enfant structuré de cet appel. Sans ce
            // relais, fermer le scanner pouvait rester suspendu jusqu'au
            // timeout du catalogue national en cours.
            dBibliotheque.cancel()
        }
        var reponses = reponsesRapides + [reponseNationale]
        guard !Task.isCancelled else { return nil }

        // Une seule fiche Honya, composée uniquement de réponses qui portent
        // réellement CET ISBN. Chaque source apporte sa meilleure pièce : le
        // titre local, les auteurs, les pages, le résumé ou la couverture.
        var meilleur = fusionnerISBN(
            reponses, isbn: isbnCanonique, langue: langueLecteur
        )

        // Apple ne connaît que son catalogue ebook et son endpoint est limité
        // à environ 20 appels/minute. Il reste un dernier filet exact, jamais
        // une taxe de latence sur chaque code-barres papier déjà trouvé.
        if SourcesCatalogue.appleBooks,
           meilleur.map(ficheSuffisante) != true {
            let apple = await appleBooks.parISBN(
                isbnCanonique, pays: pays, langue: langueLecteur
            )
            guard !Task.isCancelled else { return nil }
            reponses.append(apple)
            meilleur = fusionnerISBN(
                reponses, isbn: isbnCanonique, langue: langueLecteur
            )
        }

        guard let meilleur else { return nil }
        let complet = complete(meilleur, isbn: isbnCanonique)
        await CacheRecherche.partage.ecrireISBN(isbnCanonique, complet)
        return complet
    }

    /// Le scanner peut rendre cette fiche immédiatement. Une donnée absente
    /// déclenche le filet bibliographique, mais jamais une autre édition.
    private func ficheSuffisante(_ fiche: ResultatRecherche) -> Bool {
        !fiche.titre.isEmpty
            && !fiche.auteurs.isEmpty
            && fiche.langue != nil
    }

    /// Complète en arrière-plan une fiche déjà identifiée, sans jamais sortir
    /// de son ISBN. Le scanner peut ainsi afficher immédiatement Google/Open
    /// Library, puis recevoir le type bibliographique, le résumé ou l'image
    /// d'une bibliothèque nationale sans risquer l'édition voisine.
    func enrichirFicheExacte(_ fiche: ResultatRecherche) async -> ResultatRecherche {
        guard let brut = fiche.isbn,
              let isbn = ISBNUtil.canonique(brut) else { return fiche }
        let langue = fiche.langue ?? Langues.codeAppareil
        let nationale = await bibliotheques.parISBN(isbn)
        guard !Task.isCancelled else { return fiche }
        var fusion = fusionnerISBN(
            [fiche, nationale], isbn: isbn, langue: langue
        ) ?? fiche

        // Apple reste un ultime filet exact et uniquement pour une image
        // absente. Son endpoint est fortement limité : ne pas le taxer pour
        // chaque scan déjà illustré.
        if SourcesCatalogue.appleBooks, fusion.couvertureURL == nil {
            let apple = await appleBooks.parISBN(
                isbn,
                pays: Langues.storefrontEdition(isbn),
                langue: langue
            )
            guard !Task.isCancelled else { return fiche }
            fusion = fusionnerISBN(
                [fusion, apple], isbn: isbn, langue: langue
            ) ?? fusion
        }

        let resultat = complete(fusion, isbn: isbn)
        await CacheRecherche.partage.ecrireISBN(isbn, resultat)
        return resultat
    }

    private func parISBNGoogleSiAutorise(_ isbn: String) async -> ResultatRecherche? {
        guard SourcesCatalogue.googleBooks else { return nil }
        return (try? await google.parISBN(isbn)) ?? nil
    }

    /// Fusion prudente des catalogues sur l'identifiant exact. Les recherches
    /// de titre n'entrent jamais ici : elles ne peuvent donc pas rebaptiser un
    /// code-barres ou lui attacher les données d'un homonyme.
    private func fusionnerISBN(
        _ reponses: [ResultatRecherche?], isbn: String, langue: String
    ) -> ResultatRecherche? {
        let exactes = reponses.compactMap { $0 }.filter { resultat in
            guard let trouve = resultat.isbn else { return false }
            return ISBNUtil.canonique(trouve) == isbn
        }
        guard !exactes.isEmpty else { return nil }

        func score(_ resultat: ResultatRecherche) -> Int {
            var points = resultat.langue == langue ? 20 : 0
            if resultat.couvertureURL != nil { points += 10 }
            if !resultat.auteurs.isEmpty { points += 6 }
            if resultat.resume?.isEmpty == false { points += 4 }
            if resultat.pages != nil { points += 3 }
            if resultat.dateSortie != nil { points += 2 }
            if resultat.type != .livre { points += 2 }
            return points
        }

        var fusion = exactes.max { score($0) < score($1) }!
        for fiche in exactes where fiche.id != fusion.id {
            for (code, titre) in fiche.titresParLangue
                where fusion.titresParLangue[code] == nil {
                fusion.titresParLangue[code] = titre
            }
            if fusion.titreOriginal == nil { fusion.titreOriginal = fiche.titreOriginal }
            if fusion.romaji == nil { fusion.romaji = fiche.romaji }
            if fusion.auteurs.isEmpty { fusion.auteurs = fiche.auteurs }
            if (fiche.resume?.count ?? 0) > (fusion.resume?.count ?? 0) {
                fusion.resume = fiche.resume
            }
            if fusion.pages == nil { fusion.pages = fiche.pages }
            if fusion.annee == nil { fusion.annee = fiche.annee }
            if fusion.dateSortie == nil { fusion.dateSortie = fiche.dateSortie }
            if fusion.couvertureURL == nil, let couverture = fiche.couvertureURL {
                fusion.couvertureURL = couverture
                fusion.attributionCouverture = fiche.attributionCouverture
            } else if fusion.attributionCouverture == nil,
                      fusion.couvertureURL == fiche.couvertureURL {
                fusion.attributionCouverture = fiche.attributionCouverture
            }
            if fusion.langue == nil { fusion.langue = fiche.langue }
            if fusion.type == .livre, fiche.type != .livre { fusion.type = fiche.type }
            if fusion.tomesTotal == nil { fusion.tomesTotal = fiche.tomesTotal }
            if fusion.chapitresTotal == nil { fusion.chapitresTotal = fiche.chapitresTotal }
            if fusion.idAniList == nil { fusion.idAniList = fiche.idAniList }
            for genre in fiche.genres where !fusion.genres.contains(genre) {
                fusion.genres.append(genre)
            }
        }
        fusion.isbn = isbn
        return fusion
    }

    /// La couverture manquante, empruntée à une autre édition du même tome.
    ///
    /// Tenue à l'écart de `parISBN` à dessein : elle passe par une recherche
    /// de titre, bien plus longue que la fiche elle-même. Le scanner pose donc
    /// le livre à l'écran d'abord, et l'image le rejoint quand elle arrive.
    func couvertureDeSecours(pour fiche: ResultatRecherche) async -> String? {
        guard fiche.couvertureURL == nil else { return nil }

        // La bibliothèque nationale d'abord : elle répond sur l'ISBN exact,
        // donc sur L'ÉDITION qu'on tient en main — la vraie couverture, celle
        // du tirage posé sur la table. L'emprunt par titre, lui, ne donne que
        // l'image d'une autre édition, plus grande approximation.
        //
        // On y revient même quand un catalogue commercial a répondu : Google
        // donne souvent le titre sans l'image, et refermer la cascade là
        // laissait la couverture vide alors qu'elle était à portée.
        if let isbn = fiche.isbn,
           let notice = await bibliotheques.parISBN(isbn),
           let image = notice.couvertureURL {
            return image
        }

        // Une recherche par titre peut trouver l'ebook ou un autre tirage,
        // donc un autre code-barres. Pour un scan exact, cette image serait
        // enregistrée comme si elle appartenait au livre tenu en main : mieux
        // vaut attendre une vraie couverture que certifier la mauvaise.
        if fiche.isbn != nil { return nil }

        let langue = fiche.langue ?? Langues.codeAppareil
        return await couvertureParTitre(fiche, langue: langue)
    }

    /// La couverture d'une autre édition du même titre — même tome si la
    /// tomaison en donne un. On n'emprunte qu'à un résultat dont le titre
    /// désigne la même œuvre : mieux vaut aucune image qu'une image fausse.
    private func couvertureParTitre(
        _ fiche: ResultatRecherche, langue: String
    ) async -> String? {
        let (base, numero) = Tomaison.decomposer(fiche.titre)
        guard base.count >= 3 else { return nil }

        let candidats = await rechercherLivres(base, langue: langue)
        return candidats.first { candidat in
            guard candidat.couvertureURL != nil,
                  AuteursUtil.correspondent(candidat.auteurs, fiche.auteurs)
            else { return false }
            let (baseCandidat, numeroCandidat) = Tomaison.decomposer(candidat.titre)
            guard Tomaison.memeSerie(baseCandidat, base) else { return false }
            // Un tome précis n'accepte que la couverture du même numéro.
            if let numero { return numeroCandidat == numero }
            return true
        }?.couvertureURL
    }

    private func complete(_ resultat: ResultatRecherche, isbn: String) -> ResultatRecherche {
        var copie = resultat
        if copie.isbn == nil { copie.isbn = ISBNUtil.normaliser(isbn) }
        return copie
    }

    // MARK: Titres officiels localisés
    // Politique Honya : jamais de traduction automatique — on va chercher
    // le titre de l'édition réellement publiée dans la langue demandée.

    func titreOfficiel(_ titreConnu: String, langue: String) async -> String? {
        let resultats = await rechercherLivres(titreConnu, langue: langue)
        let exact = resultats.first(where: { $0.langue == langue })?.titre
        return exact ?? resultats.first?.titre
    }
}

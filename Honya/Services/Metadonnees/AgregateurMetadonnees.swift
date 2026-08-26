import Foundation

/// Cache de session des recherches : la grille des tomes et le résolveur
/// posent les mêmes questions en boucle — inutile de repayer le quota Google.
actor CacheRecherche {
    static let partage = CacheRecherche()
    private var entrees: [String: [ResultatRecherche]] = [:]

    func lire(_ cle: String) -> [ResultatRecherche]? { entrees[cle] }

    func ecrire(_ cle: String, _ valeur: [ResultatRecherche]) {
        // On ne mémorise pas les échecs : un quota épuisé mérite un nouvel essai.
        guard !valeur.isEmpty else { return }
        entrees[cle] = valeur
    }
}

/// La cascade de sources : aucune API ne référence « tous les livres du monde »,
/// l'empilement Google Books → Open Library (+ AniList pour les séries) si.
struct AgregateurMetadonnees: Sendable {
    static let partage = AgregateurMetadonnees()

    private let appleBooks = AppleBooksProvider()
    private let google = GoogleBooksProvider()
    private let openLibrary = OpenLibraryProvider()
    private let aniList = AniListProvider()
    private let bibliotheques = BibliothequeNationaleProvider()

    // MARK: Recherche texte

    func rechercherLivres(_ requete: String, langue: String?) async -> [ResultatRecherche] {
        let cle = "livres|" + requete.lowercased() + "|" + (langue ?? "-")
        if let connu = await CacheRecherche.partage.lire(cle) { return connu }

        // Le catalogue Apple Books du pays du lecteur d'abord — la même base
        // que son app Apple Books : éditions locales, couvertures HD, tri
        // d'Apple. Google puis Open Library ne sont que des replis.
        let langueLecteur = langue ?? Langues.codeAppareil
        let pays = Langues.storefront(pourLangue: langueLecteur)
        var resultats = (try? await appleBooks.rechercher(
            requete, pays: pays, langue: langueLecteur
        )) ?? []
        if resultats.isEmpty {
            resultats = (try? await google.rechercher(requete, langue: langue)) ?? []
        }
        if resultats.isEmpty {
            resultats = (try? await openLibrary.rechercher(requete, langue: langue)) ?? []
        }
        let tries = dedoublonner(trierParPertinence(resultats, requete: requete, langue: langue))
        await CacheRecherche.partage.ecrire(cle, tries)
        return tries
    }

    /// Deux éditions du même tome ne doivent apparaître qu'une fois : on garde
    /// la mieux classée (couverture, langue du lecteur…).
    private func dedoublonner(_ resultats: [ResultatRecherche]) -> [ResultatRecherche] {
        var vus = Set<String>()
        return resultats.filter { resultat in
            let (base, numero) = Tomaison.decomposer(resultat.titre)
            let cle: String
            if let numero {
                cle = TexteUtil.normaliser(base) + "|" + String(numero)
            } else {
                cle = resultat.id
            }
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
        let langueLecteur = langue ?? "en"

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
                else if !Titres.litScriptNonLatin(langueLecteur),
                        Titres.litScriptNonLatin(langueResultat) { points -= 15 }
            }
            // Un titre illisible pour ce lecteur passe après les autres.
            if !Titres.litScriptNonLatin(langueLecteur), Titres.estNonLatin(titre) { points -= 50 }
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
        let resultats = (try? await aniList.rechercher(requete, langue: nil)) ?? []
        let tries = trierParPertinence(resultats, requete: requete, langue: langue)
        await CacheRecherche.partage.ecrire(cle, tries)
        return tries
    }

    // MARK: ISBN (le scanner passe par ici)

    /// La fiche du code scanné, aussi vite que le réseau le permet.
    ///
    /// Les trois catalogues sont interrogés EN MÊME TEMPS. En file indienne,
    /// le plus lent imposait son temps à tous : on attendait Google, puis
    /// Apple, puis Open Library, chacun jusqu'à soixante secondes. Ensemble,
    /// l'attente n'est plus que celle du plus lent des trois — et ils sont
    /// coupés à six secondes.
    ///
    /// Ce qui manque encore — la couverture d'une édition rare — se cherche
    /// après, par `couvertureDeSecours`, pour que le livre s'affiche tout de
    /// suite au lieu d'attendre son image.
    func parISBN(_ isbn: String) async -> ResultatRecherche? {
        let langueLecteur = ISBNUtil.langueProbable(isbn) ?? Langues.codeAppareil
        let pays = Langues.storefront(pourLangue: langueLecteur)

        async let deGoogle = (try? google.parISBN(isbn)) ?? nil
        async let dApple = appleBooks.parISBN(isbn, pays: pays, langue: langueLecteur)
        async let dOpenLibrary = (try? openLibrary.parISBN(isbn)) ?? nil
        let reponses = [await deGoogle, await dApple, await dOpenLibrary]

        // La première fiche donne le texte ; n'importe laquelle peut donner
        // l'image. Google répond souvent le premier et sans couverture, alors
        // qu'Apple Books l'avait : la fiche s'affichait avec un rectangle
        // générique pour rien.
        var meilleur = reponses.compactMap { $0 }.first
        if meilleur?.couvertureURL == nil,
           let image = reponses.compactMap({ $0?.couvertureURL }).first {
            meilleur?.couvertureURL = image
        }

        // Le filet : la bibliothèque nationale du pays de l'ISBN. Le dépôt
        // légal y fait entrer tout ce qui paraît — y compris ce que Google,
        // Apple et Open Library ignorent. Un lecteur qui scanne un livre
        // acheté en librairie DOIT le trouver. On n'y va que si les trois
        // catalogues ont fait chou blanc : c'est le chemin lent.
        if meilleur == nil {
            meilleur = await bibliotheques.parISBN(isbn)
        }

        return meilleur.map { complete($0, isbn: isbn) }
    }

    /// La couverture manquante, empruntée à une autre édition du même tome.
    ///
    /// Tenue à l'écart de `parISBN` à dessein : elle passe par une recherche
    /// de titre, bien plus longue que la fiche elle-même. Le scanner pose donc
    /// le livre à l'écran d'abord, et l'image le rejoint quand elle arrive.
    func couvertureDeSecours(pour fiche: ResultatRecherche) async -> String? {
        guard fiche.couvertureURL == nil else { return nil }
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
            guard candidat.couvertureURL != nil else { return false }
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
        if copie.langue == nil { copie.langue = ISBNUtil.langueProbable(isbn) }
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

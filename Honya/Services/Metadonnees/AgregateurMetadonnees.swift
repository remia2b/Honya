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

    func parISBN(_ isbn: String) async -> ResultatRecherche? {
        if let resultat = (try? await google.parISBN(isbn)) ?? nil {
            return complete(resultat, isbn: isbn)
        }
        let langueLecteur = ISBNUtil.langueProbable(isbn) ?? Langues.codeAppareil
        if let resultat = await appleBooks.parISBN(
            isbn,
            pays: Langues.storefront(pourLangue: langueLecteur),
            langue: langueLecteur
        ) {
            return complete(resultat, isbn: isbn)
        }
        if let resultat = (try? await openLibrary.parISBN(isbn)) ?? nil {
            return complete(resultat, isbn: isbn)
        }
        return nil
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

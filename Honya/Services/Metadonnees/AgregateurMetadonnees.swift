import Foundation

/// La cascade de sources : aucune API ne référence « tous les livres du monde »,
/// l'empilement Google Books → Open Library (+ AniList pour les séries) si.
struct AgregateurMetadonnees: Sendable {
    static let partage = AgregateurMetadonnees()

    private let google = GoogleBooksProvider()
    private let openLibrary = OpenLibraryProvider()
    private let aniList = AniListProvider()

    // MARK: Recherche texte

    func rechercherLivres(_ requete: String, langue: String?) async -> [ResultatRecherche] {
        // Google Books d'abord (meilleure pertinence), Open Library en repli — sans clé
        // API, Google impose un quota bas et renvoie souvent une réponse vide.
        var resultats = (try? await google.rechercher(requete, langue: langue)) ?? []
        if resultats.isEmpty {
            resultats = (try? await openLibrary.rechercher(requete, langue: langue)) ?? []
        }
        return trierParPertinence(resultats, requete: requete, langue: langue)
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
        let resultats = (try? await aniList.rechercher(requete, langue: nil)) ?? []
        return trierParPertinence(resultats, requete: requete, langue: langue)
    }

    // MARK: ISBN (le scanner passe par ici)

    func parISBN(_ isbn: String) async -> ResultatRecherche? {
        if let resultat = (try? await google.parISBN(isbn)) ?? nil {
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

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
        if let resultats = try? await google.rechercher(requete, langue: langue), !resultats.isEmpty {
            return resultats
        }
        return (try? await openLibrary.rechercher(requete, langue: langue)) ?? []
    }

    func rechercherMangas(_ requete: String) async -> [ResultatRecherche] {
        (try? await aniList.rechercher(requete, langue: nil)) ?? []
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

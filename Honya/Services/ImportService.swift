import Foundation
import SwiftData

/// Transforme un résultat de recherche en objets SwiftData, avec déduplication.
@MainActor
enum ImportService {

    enum Ajout {
        case oeuvre(Oeuvre)
        case serie(Serie)
        case dejaPresent
    }

    static func existeDeja(_ resultat: ResultatRecherche, dans contexte: ModelContext) -> Bool {
        let series = (try? contexte.fetch(FetchDescriptor<Serie>())) ?? []
        if resultat.estSerie {
            return series.contains { $0.idAniList != nil && $0.idAniList == resultat.idAniList }
        }
        // Un tome (« Kagurabachi T3 ») est « déjà là » si la série le possède.
        let (base, numero) = Tomaison.decomposer(resultat.titre)
        if let numero,
           let serie = serieCorrespondante(base, dans: series),
           let tome = serie.tomes.first(where: { $0.numero == numero }),
           tome.possede {
            return true
        }
        let oeuvres = (try? contexte.fetch(FetchDescriptor<Oeuvre>())) ?? []
        return oeuvres.contains { oeuvre in
            oeuvre.idExterne == resultat.id
                || (oeuvre.titreOriginal.caseInsensitiveCompare(resultat.titre) == .orderedSame
                    && oeuvre.auteurPrincipal == (resultat.auteurs.first ?? oeuvre.auteurPrincipal))
        }
    }

    /// Ce que la bibliothèque possède déjà pour ce résultat, s'il y a lieu.
    ///
    /// Plus permissif que `existeDeja` : une série présente compte même si le
    /// tome visé n'est pas encore possédé. On cherche ici où EMMENER le
    /// lecteur, pas s'il faut lui proposer d'ajouter.
    static func trouver(
        _ resultat: ResultatRecherche, dans contexte: ModelContext
    ) -> CibleSession? {
        let series = (try? contexte.fetch(FetchDescriptor<Serie>())) ?? []

        if resultat.estSerie,
           let serie = series.first(where: {
               $0.idAniList != nil && $0.idAniList == resultat.idAniList
           }) {
            return .serie(serie)
        }

        let (base, _) = Tomaison.decomposer(resultat.titre)
        if let serie = serieCorrespondante(base, dans: series) {
            return .serie(serie)
        }

        let oeuvres = (try? contexte.fetch(FetchDescriptor<Oeuvre>())) ?? []
        if let oeuvre = oeuvres.first(where: { oeuvre in
            oeuvre.idExterne == resultat.id
                || (oeuvre.titreOriginal.caseInsensitiveCompare(resultat.titre) == .orderedSame
                    && oeuvre.auteurPrincipal == (resultat.auteurs.first ?? oeuvre.auteurPrincipal))
        }) {
            return .oeuvre(oeuvre)
        }
        return nil
    }

    private static func serieCorrespondante(_ nom: String, dans series: [Serie]) -> Serie? {
        series.first { serie in
            Tomaison.memeSerie(serie.nom, nom)
                || serie.noms.values.contains { Tomaison.memeSerie($0, nom) }
                || (serie.nomRomaji.map { Tomaison.memeSerie($0, nom) } ?? false)
        }
    }

    @discardableResult
    static func ajouter(
        _ resultat: ResultatRecherche,
        statut: StatutLecture,
        dans contexte: ModelContext
    ) -> Ajout {
        guard !existeDeja(resultat, dans: contexte) else { return .dejaPresent }
        let objectif = Objectif.courant(dans: contexte)

        if resultat.estSerie {
            // Une série déjà rangée sous un autre identifiant — retrouvée par
            // son nom — ne doit pas se dédoubler : on rend celle qui existe.
            let series = (try? contexte.fetch(FetchDescriptor<Serie>())) ?? []
            if let existante = serieCorrespondante(resultat.titre, dans: series) {
                return .serie(existante)
            }
            return .serie(ajouterSerie(resultat, statut: statut,
                                       contexte: contexte, objectif: objectif))
        }

        // Un tome rejoint sa série : « Kagurabachi T3 » va dans Kagurabachi,
        // qu'elle existe déjà ou qu'il faille la créer — comme chez Apple Books.
        let (base, numero) = Tomaison.decomposer(resultat.titre)
        if let numero, estTomaison(resultat) {
            let series = (try? contexte.fetch(FetchDescriptor<Serie>())) ?? []
            let serie = serieCorrespondante(base, dans: series)
                ?? creerSerieDepuisTome(base: base, resultat: resultat, contexte: contexte)
            integrerTome(numero: numero, depuis: resultat, statut: statut, dans: serie)
            return .serie(serie)
        }

        return .oeuvre(ajouterOeuvre(resultat, statut: statut, contexte: contexte))
    }

    /// Ce résultat ressemble-t-il à un tome de série ? (BD/manga, ou série déjà connue)
    private static func estTomaison(_ resultat: ResultatRecherche) -> Bool {
        if resultat.type != .livre { return true }
        let genres = resultat.genres.joined(separator: " ").lowercased()
        return genres.contains("comic") || genres.contains("manga")
            || genres.contains("bande dessinée") || genres.contains("graphic")
    }

    private static func creerSerieDepuisTome(
        base: String,
        resultat: ResultatRecherche,
        contexte: ModelContext
    ) -> Serie {
        let serie = Serie(nom: base, type: resultat.type == .livre ? .manga : resultat.type)
        serie.auteur = resultat.auteurs.first
        serie.genres = resultat.genres
        serie.couvertureLocaleURL = resultat.couvertureURL
        if let langue = resultat.langue {
            serie.noms[langue] = base
        }
        contexte.insert(serie)
        return serie
    }

    private static func integrerTome(
        numero: Int,
        depuis resultat: ResultatRecherche,
        statut: StatutLecture,
        dans serie: Serie
    ) {
        let tome: Tome
        if let existant = serie.tomes.first(where: { $0.numero == numero }) {
            tome = existant
        } else {
            tome = Tome(numero: numero)
            serie.tomes.append(tome)
            if let total = serie.tomesTotal, numero > total { serie.tomesTotal = numero }
        }
        tome.titre = resultat.titre
        tome.couvertureURL = resultat.couvertureURL ?? tome.couvertureURL
        tome.isbn = resultat.isbn ?? tome.isbn
        tome.pages = resultat.pages ?? tome.pages

        switch statut {
        case .lu:
            tome.possede = true
            if !tome.lu { tome.dateLu = Date() }
            tome.lu = true
        case .wishlist:
            break // le tome reste manquant : il est « à acheter »
        default:
            tome.possede = true
        }
        // Le tome 1 donne sa couverture à la série si elle n'en a pas de locale.
        if numero == 1, serie.couvertureLocaleURL == nil {
            serie.couvertureLocaleURL = resultat.couvertureURL
        }
    }

    // MARK: - Livre

    private static func ajouterOeuvre(
        _ resultat: ResultatRecherche,
        statut: StatutLecture,
        contexte: ModelContext
    ) -> Oeuvre {
        let objectif = Objectif.courant(dans: contexte)
        let oeuvre = Oeuvre(
            titreOriginal: resultat.titreOriginal ?? resultat.titre,
            auteurs: resultat.auteurs,
            type: resultat.type
        )
        oeuvre.titres = resultat.titresParLangue
        oeuvre.titreRomaji = resultat.romaji
        if let langue = resultat.langue, oeuvre.titres[langue] == nil {
            oeuvre.titres[langue] = resultat.titre
        }
        oeuvre.genres = resultat.genres
        oeuvre.resume = resultat.resume
        oeuvre.anneePublication = resultat.annee
        oeuvre.pages = resultat.pages
        oeuvre.couvertureCanoniqueURL = resultat.couvertureURL
        oeuvre.idExterne = resultat.id

        let exemplaire = Exemplaire(statut: statut, possede: statut != .wishlist)
        exemplaire.isbn = resultat.isbn
        exemplaire.langueEdition = resultat.langue
        exemplaire.couvertureEditionURL = resultat.couvertureURL
        if exemplaire.possede { exemplaire.dateAchat = Date() }
        if statut == .enCours { exemplaire.dateDebut = Date() }
        oeuvre.exemplaire = exemplaire

        contexte.insert(oeuvre)
        let langue = objectif.languePrincipale
        Task { @MainActor in
            await EditionsLocales.rafraichirOeuvre(oeuvre, langue: langue)
        }
        return oeuvre
    }

    // MARK: - Série manga

    private static func ajouterSerie(
        _ resultat: ResultatRecherche,
        statut: StatutLecture,
        contexte: ModelContext,
        objectif: Objectif
    ) -> Serie {
        let serie = Serie(nom: resultat.titre, type: resultat.type)
        // Le statut choisi à l'ajout prime sur le calcul : une série qu'on
        // déclare lue ne doit pas repasser « à acheter » sous prétexte
        // qu'aucun tome n'est encore coché. On peut toujours revenir au
        // calcul depuis la fiche.
        serie.statutChoisi = statut
        serie.noms = resultat.titresParLangue
        serie.nomRomaji = resultat.romaji
        serie.auteur = resultat.auteurs.first
        serie.genres = resultat.genres
        serie.resume = resultat.resume
        serie.couvertureURL = resultat.couvertureURL
        serie.tomesTotal = resultat.tomesTotal
        serie.chapitresTotal = resultat.chapitresTotal
        serie.statutParution = resultat.statutParution
        serie.idAniList = resultat.idAniList

        // Crée les cases de tomes (l'utilisateur peut en ajouter si la parution continue).
        let nombre = resultat.tomesTotal ?? 0
        if nombre > 0 {
            for numero in 1...nombre {
                let tome = Tome(numero: numero)
                serie.tomes.append(tome)
            }
        }
        contexte.insert(serie)

        // Enrichissement automatique : l'édition du pays du lecteur — nom,
        // couvertures de tous les tomes, résumé — en une seule requête.
        let langue = objectif.languePrincipale
        Task { @MainActor in
            await EditionsLocales.rafraichirSerieComplete(serie, langue: langue)
        }
        return serie
    }
}

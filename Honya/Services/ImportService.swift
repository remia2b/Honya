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
            return .serie(ajouterSerie(resultat, contexte: contexte, objectif: objectif))
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
        resoudreEditionLocale(
            reference: oeuvre.titres["en"] ?? oeuvre.titreRomaji ?? oeuvre.titreOriginal,
            langue: objectif.languePrincipale,
            titreActuel: { oeuvre.titres[objectif.languePrincipale] }
        ) { titre, couverture in
            if let titre { oeuvre.titres[objectif.languePrincipale] = titre }
            if oeuvre.couvertureLocaleURL == nil { oeuvre.couvertureLocaleURL = couverture }
        } surResume: { resume in
            if oeuvre.resumeLocal == nil, let resume, !resume.isEmpty {
                oeuvre.resumeLocal = resume
            }
        }
        return oeuvre
    }

    /// Va chercher l'édition RÉELLEMENT publiée dans la langue du lecteur :
    /// son titre officiel ET sa couverture (celle qu'il verrait en librairie).
    /// Aucune traduction automatique : si l'œuvre n'a jamais paru dans cette
    /// langue, on garde ce qu'on a et l'affichage se rabat sur l'anglais.
    private static func resoudreEditionLocale(
        reference: String,
        langue: String,
        titreActuel: @escaping () -> String?,
        appliquer: @escaping (_ titre: String?, _ couverture: String?) -> Void,
        surResume: ((String?) -> Void)? = nil
    ) {
        guard !reference.isEmpty else { return }
        Task { @MainActor in
            let resultats = await AgregateurMetadonnees.partage
                .rechercherLivres(reference, langue: langue)
            let bon = resultats.first { $0.langue == langue && $0.couvertureURL != nil }
                ?? resultats.first { $0.couvertureURL != nil }
                ?? resultats.first
            guard let bon else { return }

            var titre: String?
            if titreActuel() == nil,
               !Titres.estNonLatin(bon.titre) || Titres.litScriptNonLatin(langue) {
                titre = bon.titre
            }
            appliquer(titre, bon.couvertureURL)
            surResume?(bon.resume)
        }
    }

    // MARK: - Série manga

    private static func ajouterSerie(
        _ resultat: ResultatRecherche,
        contexte: ModelContext,
        objectif: Objectif
    ) -> Serie {
        let serie = Serie(nom: resultat.titre, type: resultat.type)
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

        // Enrichissement paresseux : le nom officiel ET la couverture de
        // l'édition locale (Kana, Glénat… pour un lecteur français).
        let langue = objectif.languePrincipale
        resoudreEditionLocale(
            reference: serie.noms["en"] ?? serie.nomRomaji ?? serie.nom,
            langue: langue,
            titreActuel: { serie.noms[langue] }
        ) { titre, couverture in
            // Le premier résultat est souvent un TOME (« Kagurabachi, Vol. 1 ») :
            // on n'en garde que le nom de série.
            if let titre {
                serie.noms[langue] = Tomaison.decomposer(titre).base
            }
            if serie.couvertureLocaleURL == nil { serie.couvertureLocaleURL = couverture }
        } surResume: { resume in
            if serie.resumeLocal == nil, let resume, !resume.isEmpty {
                serie.resumeLocal = resume
            }
        }
        return serie
    }
}

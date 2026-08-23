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
        if resultat.estSerie {
            let series = (try? contexte.fetch(FetchDescriptor<Serie>())) ?? []
            return series.contains { $0.idAniList != nil && $0.idAniList == resultat.idAniList }
        }
        let oeuvres = (try? contexte.fetch(FetchDescriptor<Oeuvre>())) ?? []
        return oeuvres.contains { oeuvre in
            oeuvre.idExterne == resultat.id
                || (oeuvre.titreOriginal.caseInsensitiveCompare(resultat.titre) == .orderedSame
                    && oeuvre.auteurPrincipal == (resultat.auteurs.first ?? oeuvre.auteurPrincipal))
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
        return .oeuvre(ajouterOeuvre(resultat, statut: statut, contexte: contexte))
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
        appliquer: @escaping (_ titre: String?, _ couverture: String?) -> Void
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
            if let titre { serie.noms[langue] = titre }
            if serie.couvertureLocaleURL == nil { serie.couvertureLocaleURL = couverture }
        }
        return serie
    }
}

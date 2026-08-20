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
        resoudreTitreLocal(
            actuel: { oeuvre.titres[objectif.languePrincipale] },
            reference: oeuvre.titres["en"] ?? oeuvre.titreRomaji ?? oeuvre.titreOriginal,
            langue: objectif.languePrincipale
        ) { officiel in
            oeuvre.titres[objectif.languePrincipale] = officiel
        }
        return oeuvre
    }

    /// Va chercher le titre RÉELLEMENT publié dans la langue du lecteur.
    /// Aucune traduction automatique : si l'œuvre n'a jamais paru dans cette
    /// langue, on garde ce qu'on a et l'affichage se rabat sur l'anglais.
    private static func resoudreTitreLocal(
        actuel: @escaping () -> String?,
        reference: String,
        langue: String,
        appliquer: @escaping (String) -> Void
    ) {
        guard actuel() == nil, !reference.isEmpty else { return }
        Task { @MainActor in
            guard let officiel = await AgregateurMetadonnees.partage
                .titreOfficiel(reference, langue: langue) else { return }
            // Un titre dans un script illisible n'apporte rien au lecteur.
            guard !Titres.estNonLatin(officiel) || Titres.litScriptNonLatin(langue) else { return }
            appliquer(officiel)
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

        // Enrichissement paresseux : le nom OFFICIEL dans la langue de l'utilisateur.
        let langue = objectif.languePrincipale
        resoudreTitreLocal(
            actuel: { serie.noms[langue] },
            reference: serie.noms["en"] ?? serie.nomRomaji ?? serie.nom,
            langue: langue
        ) { officiel in
            serie.noms[langue] = officiel
        }
        return serie
    }
}

import Foundation
import SwiftData

/// Transforme un résultat de recherche en objets SwiftData, avec déduplication.
@MainActor
enum ImportService {

    enum Ajout {
        case oeuvre(Oeuvre)
        case serie(Serie)
        case dejaPresent
        case limiteAtteinte
    }

    /// Nombre d'entrées réellement rangées, utilisé par tous les parcours
    /// d'ajout. Les cases futures créées pour afficher une série ne sont pas
    /// facturées comme des livres possédés ; une série suivie compte toutefois
    /// au minimum pour une entrée.
    static func nombreRange(dans contexte: ModelContext) -> Int {
        let exemplaires = (try? contexte.fetch(FetchDescriptor<Exemplaire>())) ?? []
        let series = (try? contexte.fetch(FetchDescriptor<Serie>())) ?? []
        let volumesSeries = series.reduce(into: 0) { total, serie in
            total += max(1, serie.tomes.filter(\.possede).count)
        }
        return exemplaires.count + volumesSeries
    }

    /// Autorise une mutation existante qui va faire entrer plusieurs tomes
    /// possédés d'un coup (toggle, « lus jusqu'ici », menu rapide…). Tous les
    /// parcours passent ici afin que le plafond de 200 ne dépende pas de
    /// l'écran depuis lequel on agit.
    static func autorisePossession(
        des tomes: [Tome],
        de serie: Serie,
        dans contexte: ModelContext
    ) -> Bool {
        guard !Droits.partage.plus else { return true }
        let identifiants = Set(tomes.map(\.persistentModelID))
        let nouveaux = serie.tomes.filter {
            identifiants.contains($0.persistentModelID) && !$0.possede
        }.count
        let possedes = serie.tomes.filter(\.possede).count
        let impact = max(1, possedes + nouveaux) - max(1, possedes)
        guard impact > 0 else { return true }
        return nombreRange(dans: contexte) + impact <= Limites.tomes
    }

    /// Variante pour une opération qui remplace un ensemble complet (par
    /// exemple « possédés jusqu'au tome N »). Elle tient compte des volumes
    /// retirés dans le même geste au lieu de bloquer sur les seuls ajouts.
    static func autoriseNombrePossedesProjete(
        _ nombreProjete: Int,
        de serie: Serie,
        dans contexte: ModelContext
    ) -> Bool {
        guard !Droits.partage.plus else { return true }
        let actuel = serie.tomes.filter(\.possede).count
        let impact = max(1, nombreProjete) - max(1, actuel)
        guard impact > 0 else { return true }
        return nombreRange(dans: contexte) + impact <= Limites.tomes
    }

    static func existeDeja(_ resultat: ResultatRecherche, dans contexte: ModelContext) -> Bool {
        let series = (try? contexte.fetch(FetchDescriptor<Serie>())) ?? []
        if let isbn = resultat.isbn.flatMap(ISBNUtil.canonique) {
            if series.flatMap(\.tomes).contains(where: {
                $0.possede && $0.isbn.flatMap(ISBNUtil.canonique) == isbn
            }) {
                return true
            }
            let exemplaires = (try? contexte.fetch(FetchDescriptor<Exemplaire>())) ?? []
            if exemplaires.contains(where: {
                $0.isbn.flatMap(ISBNUtil.canonique) == isbn
            }) {
                return true
            }
        }
        if resultat.estSerie {
            return series.contains { $0.idAniList != nil && $0.idAniList == resultat.idAniList }
        }
        // Un tome (« Kagurabachi T3 ») est « déjà là » si la série le possède.
        let (base, numero) = Tomaison.decomposer(resultat.titre)
        if let numero,
           let serie = serieCorrespondante(base, auteurs: resultat.auteurs, dans: series),
           let tome = serie.tomes.first(where: { $0.numero == numero }),
           tome.possede {
            return true
        }
        let oeuvres = (try? contexte.fetch(FetchDescriptor<Oeuvre>())) ?? []
        return oeuvres.contains { oeuvre in
            oeuvre.idExterne == resultat.id
                || (oeuvre.titreOriginal.caseInsensitiveCompare(resultat.titre) == .orderedSame
                    && AuteursUtil.correspondent(resultat.auteurs, oeuvre.auteurs))
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

        if let isbn = resultat.isbn.flatMap(ISBNUtil.canonique) {
            if let tome = series.flatMap(\.tomes).first(where: {
                $0.isbn.flatMap(ISBNUtil.canonique) == isbn
            }), let serie = tome.serie {
                return .serie(serie)
            }
            let oeuvres = (try? contexte.fetch(FetchDescriptor<Oeuvre>())) ?? []
            if let oeuvre = oeuvres.first(where: {
                $0.exemplaire?.isbn.flatMap(ISBNUtil.canonique) == isbn
            }) {
                return .oeuvre(oeuvre)
            }
        }

        if resultat.estSerie,
           let serie = series.first(where: {
               $0.idAniList != nil && $0.idAniList == resultat.idAniList
           }) {
            return .serie(serie)
        }

        let (base, _) = Tomaison.decomposer(resultat.titre)
        if let serie = serieCorrespondante(base, auteurs: resultat.auteurs, dans: series) {
            return .serie(serie)
        }

        let oeuvres = (try? contexte.fetch(FetchDescriptor<Oeuvre>())) ?? []
        if let oeuvre = oeuvres.first(where: { oeuvre in
            oeuvre.idExterne == resultat.id
                || (oeuvre.titreOriginal.caseInsensitiveCompare(resultat.titre) == .orderedSame
                    && AuteursUtil.correspondent(resultat.auteurs, oeuvre.auteurs))
        }) {
            return .oeuvre(oeuvre)
        }
        return nil
    }

    private static func serieCorrespondante(
        _ nom: String, auteurs: [String], dans series: [Serie]
    ) -> Serie? {
        let besoin = TexteUtil.normaliser(Tomaison.decomposer(nom).base)
        return series.first { serie in
            let noms = [serie.nom, serie.nomRomaji].compactMap { $0 }
                + Array(serie.noms.values) + serie.nomsAlternatifs
            let titreCompatible = noms.contains { Tomaison.memeSerie($0, nom) }
            guard titreCompatible else { return false }

            let auteursSerie = [serie.auteur].compactMap { $0 }
            if auteurs.isEmpty || auteursSerie.isEmpty {
                // Sans auteur pour arbitrer, seul un nom exactement égal est
                // assez sûr : « Instinct » ne rejoint pas « Instinct de survie ».
                return noms.contains {
                    TexteUtil.normaliser(Tomaison.decomposer($0).base) == besoin
                }
            }
            return AuteursUtil.correspondent(auteursSerie, auteurs)
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
        let series = (try? contexte.fetch(FetchDescriptor<Serie>())) ?? []

        if resultat.estSerie {
            // Une série déjà rangée sous un autre identifiant — retrouvée par
            // son nom — ne doit pas se dédoubler : on rend celle qui existe.
            if let existante = serieCorrespondante(
                resultat.titre, auteurs: resultat.auteurs, dans: series
            ) {
                return .serie(existante)
            }
            guard placeDisponible(
                pour: resultat, statut: statut, series: series, dans: contexte
            ) else { return .limiteAtteinte }
            return .serie(ajouterSerie(resultat, statut: statut,
                                       contexte: contexte, objectif: objectif))
        }

        // Un tome rejoint sa série : « Kagurabachi T3 » va dans Kagurabachi,
        // qu'elle existe déjà ou qu'il faille la créer — comme chez Apple Books.
        let (base, numero) = Tomaison.decomposer(resultat.titre)
        if let numero, estTomaison(resultat) {
            guard placeDisponible(
                pour: resultat, statut: statut, series: series, dans: contexte
            ) else { return .limiteAtteinte }
            let serie = serieCorrespondante(base, auteurs: resultat.auteurs, dans: series)
                ?? creerSerieDepuisTome(base: base, resultat: resultat, contexte: contexte)
            integrerTome(numero: numero, depuis: resultat, statut: statut, dans: serie)
            // Une série née d'un scan possède déjà une couverture : attendre
            // l'ouverture de sa fiche ne lançait donc jamais la passe rayon.
            // La réservation du quota reste centralisée dans EditionsLocales.
            if !serie.rayonEnrichi && (!serie.rayonRefuse || Droits.partage.plus) {
                let langue = objectif.languePrincipale
                Task { @MainActor in
                    await EditionsLocales.rafraichirSerieComplete(
                        serie, langue: langue, profonde: true
                    )
                }
            }
            return .serie(serie)
        }

        guard placeDisponible(
            pour: resultat, statut: statut, series: series, dans: contexte
        ) else { return .limiteAtteinte }
        return .oeuvre(ajouterOeuvre(resultat, statut: statut, contexte: contexte))
    }

    /// Le plafond porte sur ce qui sera rangé APRÈS l'opération, pas sur le
    /// simple fait d'appuyer sur Ajouter. Exemple : une série sans tome possédé
    /// compte déjà pour une entrée ; en posséder le tome 1 ne fait donc pas
    /// passer 200 à 201 et doit rester possible au plafond.
    private static func placeDisponible(
        pour resultat: ResultatRecherche,
        statut: StatutLecture,
        series: [Serie],
        dans contexte: ModelContext
    ) -> Bool {
        guard !Droits.partage.plus else { return true }
        let impact = impactProjete(
            de: resultat, statut: statut, series: series
        )
        // Une opération sans croissance reste autorisée, même pour une
        // ancienne bibliothèque qui dépassait déjà le plafond avant Honya+.
        guard impact > 0 else { return true }
        return nombreRange(dans: contexte) + impact <= Limites.tomes
    }

    private static func impactProjete(
        de resultat: ResultatRecherche,
        statut: StatutLecture,
        series: [Serie]
    ) -> Int {
        if resultat.estSerie { return 1 }

        let (base, numero) = Tomaison.decomposer(resultat.titre)
        guard let numero, estTomaison(resultat),
              let serie = serieCorrespondante(
                  base, auteurs: resultat.auteurs, dans: series
              )
        else {
            // Une nouvelle série ou un livre isolé crée une entrée.
            return 1
        }

        // Mettre un tome manquant en liste d'achat n'augmente pas le nombre
        // rangé ; posséder un tome déjà possédé non plus.
        guard statut != .wishlist,
              serie.tomes.first(where: { $0.numero == numero })?.possede != true
        else { return 0 }

        let possedes = serie.tomes.filter(\.possede).count
        return max(1, possedes + 1) - max(1, possedes)
    }

    /// Ce résultat ressemble-t-il à un tome de série ? (BD/manga, ou série déjà connue)
    private static func estTomaison(_ resultat: ResultatRecherche) -> Bool {
        resultat.estUnTome
    }

    private static func creerSerieDepuisTome(
        base: String,
        resultat: ResultatRecherche,
        contexte: ModelContext
    ) -> Serie {
        // Le fournisseur peut réellement décrire une série de livres. Ne pas
        // la transformer artificiellement en manga au seul motif qu'elle a
        // plusieurs tomes.
        let serie = Serie(nom: base, type: resultat.type)
        serie.auteur = resultat.auteurs.first
        serie.genres = resultat.genres
        serie.nomsAlternatifs = resultat.titresAlternatifs
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
            if let total = serie.tomesTotal, numero > total {
                // Le total explicite est devenu périmé. Le numéro ajouté est
                // une borne basse, pas une preuve que la série s'arrête ici.
                serie.tomesTotal = nil
            }
        }
        tome.titre = resultat.titre
        tome.couvertureURL = resultat.couvertureURL ?? tome.couvertureURL
        if resultat.couvertureURL != nil {
            tome.attributionCouverture = resultat.attributionCouverture
        }
        tome.isbn = resultat.isbn ?? tome.isbn
        tome.pages = resultat.pages ?? tome.pages
        tome.dateSortie = resultat.dateSortie ?? tome.dateSortie
        if resultat.saisieManuelle { tome.metadonneesManuelles = true }

        switch statut {
        case .lu:
            tome.possede = true
            if !tome.lu { tome.dateLu = Date() }
            tome.lu = true
            tome.abandonne = false
            serie.statutChoisi = nil
        case .enCours:
            tome.possede = true
            tome.abandonne = false
            serie.statutChoisi = .enCours
        case .abandonne:
            tome.possede = true
            tome.lu = false
            tome.dateLu = nil
            tome.abandonne = true
            serie.statutChoisi = .abandonne
        case .wishlist:
            break // le tome reste manquant : il est « à acheter »
        case .aLire:
            tome.possede = true
            tome.abandonne = false
            serie.statutChoisi = nil
        }
        // Le tome 1 donne sa couverture à la série si elle n'en a pas de locale.
        if numero == 1, serie.couvertureLocaleURL == nil {
            serie.couvertureLocaleURL = resultat.couvertureURL
            serie.attributionCouverture = resultat.attributionCouverture
        }

        // `rayonComplet` décrit uniquement une structure 1...total dont le
        // total vient d'une source explicite. Il ne sert jamais de drapeau
        // générique disant qu'une recherche a eu lieu.
        if let total = serie.tomesTotal, total > 0 {
            let numeros = Set(serie.tomes.map(\.numero))
            serie.rayonComplet = (1...total).allSatisfy { numeros.contains($0) }
        } else {
            serie.rayonComplet = false
        }
    }

    /// Une réponse bibliographique plus riche peut arriver après l'affichage
    /// du scan et même après l'appui sur « Ajouter ». Elle ne met à jour que
    /// l'exemplaire portant exactement le même ISBN ; aucun rapprochement par
    /// titre n'est autorisé ici.
    static func appliquerEnrichissementExact(
        _ resultat: ResultatRecherche, dans contexte: ModelContext
    ) {
        guard let exact = resultat.isbn.flatMap(ISBNUtil.canonique) else { return }

        let series = (try? contexte.fetch(FetchDescriptor<Serie>())) ?? []
        for serie in series {
            for tome in serie.tomes where
                tome.isbn.flatMap(ISBNUtil.canonique) == exact {
                tome.titre = resultat.titre
                if let couverture = resultat.couvertureURL {
                    tome.couvertureURL = couverture
                    tome.attributionCouverture = resultat.attributionCouverture
                }
                tome.pages = resultat.pages ?? tome.pages
                tome.dateSortie = resultat.dateSortie ?? tome.dateSortie
                if resultat.type != .livre { serie.type = resultat.type }
                for genre in resultat.genres where !serie.genres.contains(genre) {
                    serie.genres.append(genre)
                }
                if tome.numero == 1, let couverture = resultat.couvertureURL {
                    serie.couvertureLocaleURL = couverture
                    serie.attributionCouverture = resultat.attributionCouverture
                }
            }
        }

        let oeuvres = (try? contexte.fetch(FetchDescriptor<Oeuvre>())) ?? []
        for oeuvre in oeuvres where
            oeuvre.exemplaire?.isbn.flatMap(ISBNUtil.canonique) == exact {
            if let langue = resultat.langue {
                oeuvre.titres[langue] = resultat.titreAffiche(langue)
                oeuvre.exemplaire?.langueEdition = langue
            }
            if oeuvre.auteurs.isEmpty { oeuvre.auteurs = resultat.auteurs }
            if oeuvre.resume == nil { oeuvre.resume = resultat.resume }
            if oeuvre.pages == nil { oeuvre.pages = resultat.pages }
            if oeuvre.anneePublication == nil { oeuvre.anneePublication = resultat.annee }
            if let couverture = resultat.couvertureURL,
               !CouverturesPersonnelles.estPersonnelle(
                    oeuvre.exemplaire?.couvertureEditionURL
               ) {
                oeuvre.exemplaire?.couvertureEditionURL = couverture
                oeuvre.couvertureCanoniqueURL = couverture
                oeuvre.attributionCouverture = resultat.attributionCouverture
            }
            for genre in resultat.genres where !oeuvre.genres.contains(genre) {
                oeuvre.genres.append(genre)
            }
        }
        try? contexte.save()
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
        oeuvre.attributionCouverture = resultat.attributionCouverture
        oeuvre.idExterne = resultat.id

        let exemplaire = Exemplaire()
        exemplaire.isbn = resultat.isbn
        exemplaire.langueEdition = resultat.langue
        exemplaire.couvertureEditionURL = resultat.couvertureURL
        oeuvre.exemplaire = exemplaire
        exemplaire.changerStatut(statut)
        if exemplaire.possede { exemplaire.dateAchat = Date() }

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
        serie.nomsAlternatifs = resultat.titresAlternatifs
        serie.nomRomaji = resultat.romaji
        serie.auteur = resultat.auteurs.first
        serie.genres = resultat.genres
        serie.resume = resultat.resume
        serie.couvertureURL = resultat.couvertureURL
        serie.tomesTotal = resultat.tomesTotal
        serie.chapitresTotal = resultat.chapitresTotal
        serie.statutParution = resultat.statutParution
        serie.idAniList = resultat.idAniList

        // Le total explicite est conservé comme information, mais aucune case
        // future n'est créée ici : EditionsLocales réserve d'abord l'un des
        // trois rayons gratuits (ou vérifie Honya+) avant de matérialiser 1...N.
        contexte.insert(serie)

        // Enrichissement automatique : l'édition du pays du lecteur — nom,
        // couvertures de tous les tomes, résumé — en une seule requête.
        let langue = objectif.languePrincipale
        Task { @MainActor in
            await EditionsLocales.rafraichirSerieComplete(
                serie, langue: langue, profonde: true
            )
        }
        return serie
    }
}

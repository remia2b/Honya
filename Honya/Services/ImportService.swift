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
        /// La fiche reste consultable, mais ce volume appartient à la
        /// continuation Honya+ d'un rayon au-delà des trois séries offertes.
        case rayonVerrouille(Serie)
    }

    /// Une seule règle pour la grille, la recherche, le scan et les raccourcis
    /// de bibliothèque. Sans ce point commun, « Toute la série lue » pouvait
    /// contourner le cadenas affiché sur exactement les mêmes volumes.
    static func tomeVerrouilleParRayon(_ tome: Tome, de serie: Serie) -> Bool {
        guard !tome.possede else { return false }
        return numeroVerrouilleParRayon(tome.numero, de: serie)
    }

    static func numeroVerrouilleParRayon(_ numero: Int, de serie: Serie) -> Bool {
        guard !Droits.partage.plus,
              serie.rayonRefuse
                || serie.rayonHonyaPlus
                || EditionsLocales.accesProvisoireRefuse(serie)
        else { return false }
        // Le droit porte sur les trois PREMIERS numéros, pas sur les trois
        // premiers découverts. Sinon scanner directement le tome 8 avant que
        // le catalogue ait rempli 1...7 le ferait passer pour l'index zéro.
        return numero > Limites.tomesApercuSerie
    }

    static func contientTomeVerrouille(
        _ tomes: [Tome], de serie: Serie
    ) -> Bool {
        tomes.contains { tomeVerrouilleParRayon($0, de: serie) }
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
                || serieCorrespondante(
                    resultat.titre, auteurs: resultat.auteurs, dans: series
                ) != nil
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

    /// Les premières bêtas rangeaient certains mangas/BD numérotés comme des
    /// livres isolés. Après la mise à jour, on les replace automatiquement dans
    /// leur série afin qu'un ancien « TBATE 1 » ne cohabite pas avec le nouveau
    /// rayon TBATE.
    ///
    /// La migration reste volontairement conservatrice : si l'ancienne fiche
    /// contient une citation, une note, des moods, une progression ou un suivi
    /// qui n'ont pas encore d'équivalent visible au niveau Tome, elle ne la
    /// supprime pas. Les sessions, étagères, prêt, statut, dates, langue et
    /// couverture sont en revanche transférés sans perte.
    @discardableResult
    static func migrerTomesIsolesLegacy(dans contexte: ModelContext) -> Int {
        let oeuvres = (try? contexte.fetch(FetchDescriptor<Oeuvre>())) ?? []
        guard !oeuvres.isEmpty else { return 0 }

        var series = (try? contexte.fetch(FetchDescriptor<Serie>())) ?? []
        let langue = ((try? contexte.fetch(FetchDescriptor<Objectif>())) ?? [])
            .first?.languePrincipale ?? Langues.codeAppareil
        var migrees = 0
        var aEnrichir: [Serie] = []

        for oeuvre in oeuvres {
            guard let exemplaire = oeuvre.exemplaire,
                  oeuvre.citations.isEmpty,
                  exemplaire.note == nil,
                  exemplaire.moods.isEmpty,
                  exemplaire.pageCourante == 0,
                  exemplaire.format == nil,
                  exemplaire.prixPaye == nil,
                  !exemplaire.aSuivre,
                  let decomposition = decompositionLegacy(
                    de: oeuvre,
                    langue: langue,
                    parmi: oeuvres,
                    seriesConnues: series
                  )
            else { continue }

            let serie: Serie
            if let existante = serieCorrespondante(
                decomposition.base,
                auteurs: oeuvre.auteurs,
                dans: series
            ) {
                serie = existante
            } else {
                serie = Serie(nom: decomposition.base, type: oeuvre.type)
                serie.auteur = oeuvre.auteurs.first
                serie.genres = oeuvre.genres
                serie.resume = oeuvre.resume
                serie.resumeLocal = oeuvre.resumeLocal
                for (code, titre) in oeuvre.titres {
                    let base = Tomaison.decomposer(titre).base
                    if !base.isEmpty { serie.noms[code] = base }
                }
                contexte.insert(serie)
                series.append(serie)
            }

            let tome: Tome
            if let existant = serie.tomes.first(where: {
                $0.numero == decomposition.numero
            }) {
                // Deux fiches possédées peuvent porter des historiques
                // contradictoires. Ne jamais en supprimer une arbitrairement.
                guard !existant.possede else { continue }
                tome = existant
            } else {
                tome = Tome(numero: decomposition.numero)
                serie.tomes.append(tome)
            }

            tome.titre = tome.titre ?? oeuvre.titre(langue)
            tome.isbn = tome.isbn ?? exemplaire.isbn
            tome.langueEdition = tome.langueEdition ?? exemplaire.langueEdition
            tome.pages = tome.pages ?? oeuvre.pages
            tome.couvertureURL = tome.couvertureURL
                ?? exemplaire.couvertureEditionURL
                ?? oeuvre.couvertureLocaleURL
                ?? oeuvre.couvertureCanoniqueURL
            tome.couverturePersonnelleURL = tome.couverturePersonnelleURL
                ?? exemplaire.couverturePersonnelleURL
            tome.attributionCouverture = tome.attributionCouverture
                ?? oeuvre.attributionCouverture
            tome.preteA = tome.preteA ?? exemplaire.preteA
            tome.preteLe = tome.preteLe ?? exemplaire.preteLe
            if !tome.possede || tome.statut == .wishlist {
                tome.changerStatut(exemplaire.statut)
                tome.dateAchat = exemplaire.dateAchat
                tome.dateDebut = exemplaire.dateDebut
                tome.dateFin = exemplaire.dateFin
                if exemplaire.statut == .lu, let date = exemplaire.dateFin {
                    tome.dateLu = date
                }
            }

            if serie.type == .livre, oeuvre.type != .livre {
                serie.type = oeuvre.type
            }
            // Une migration technique ne doit pas faire remonter un ancien
            // ajout comme s'il venait d'être rangé aujourd'hui.
            serie.dateAjout = min(serie.dateAjout, oeuvre.dateAjout)
            if serie.auteur == nil { serie.auteur = oeuvre.auteurs.first }
            for genre in oeuvre.genres where !serie.genres.contains(genre) {
                serie.genres.append(genre)
            }
            for collection in oeuvre.collections where !serie.collections.contains(
                where: { $0.persistentModelID == collection.persistentModelID }
            ) {
                serie.collections.append(collection)
            }
            // Réaffecter la relation modifie immédiatement `oeuvre.sessions` :
            // parcourir une copie garantit qu'aucune session n'est sautée puis
            // supprimée par la cascade de l'œuvre.
            for session in Array(oeuvre.sessions) {
                session.oeuvre = nil
                session.serie = serie
            }

            contexte.delete(oeuvre)
            migrees += 1
            if !aEnrichir.contains(where: { $0 === serie }) {
                aEnrichir.append(serie)
            }
        }

        guard migrees > 0 else { return 0 }
        do {
            try contexte.save()
        } catch {
            contexte.rollback()
            return 0
        }

        for serie in aEnrichir where !serie.rayonEnrichi {
            Task { @MainActor in
                await EditionsLocales.rafraichirSerieComplete(
                    serie, langue: langue, profonde: true
                )
            }
        }
        return migrees
    }

    private static func decompositionLegacy(
        de oeuvre: Oeuvre,
        langue: String,
        parmi oeuvres: [Oeuvre],
        seriesConnues: [Serie]
    ) -> (base: String, numero: Int)? {
        let decompositions = decompositionsLegacyBrutes(
            de: oeuvre, langue: langue
        )

        // « Tome 3 », « Vol. 3 » ou « #3 » est une preuve explicite et reste
        // sûr même si un seul volume avait été ajouté dans une ancienne bêta.
        if let explicite = decompositions.first(where: { $0.explicite }) {
            return (explicite.base, explicite.numero)
        }

        // Un chiffre final seul est ambigu : « Area 51 » n'est pas forcément
        // le tome 51 d'une série. On ne le migre que si un rayon correspondant
        // existe déjà, ou si une deuxième fiche numérotée confirme la suite.
        guard oeuvre.type != .livre else { return nil }
        for implicite in decompositions {
            if serieCorrespondante(
                implicite.base,
                auteurs: oeuvre.auteurs,
                dans: seriesConnues
            ) != nil {
                return (implicite.base, implicite.numero)
            }

            let suiteConfirmee = oeuvres.contains { autre in
                guard autre !== oeuvre, autre.type == oeuvre.type else {
                    return false
                }
                if !oeuvre.auteurs.isEmpty, !autre.auteurs.isEmpty,
                   !AuteursUtil.correspondent(oeuvre.auteurs, autre.auteurs) {
                    return false
                }
                return decompositionsLegacyBrutes(de: autre, langue: langue)
                    .contains { candidate in
                        candidate.numero != implicite.numero
                            && Tomaison.memeSerie(candidate.base, implicite.base)
                    }
            }
            if suiteConfirmee {
                return (implicite.base, implicite.numero)
            }
        }
        return nil
    }

    private static func decompositionsLegacyBrutes(
        de oeuvre: Oeuvre, langue: String
    ) -> [(base: String, numero: Int, explicite: Bool)] {
        let candidats = [oeuvre.titre(langue), oeuvre.titreOriginal]
            + Array(oeuvre.titres.values)
        var vus = Set<String>()
        return candidats.compactMap { titre in
            let decomposition = Tomaison.decomposer(titre)
            guard let numero = decomposition.numero,
                  !decomposition.base.isEmpty
            else { return nil }
            let cle = "\(TexteUtil.normaliser(decomposition.base))#\(numero)"
            guard vus.insert(cle).inserted else { return nil }
            return (
                base: decomposition.base,
                numero: numero,
                explicite: Tomaison.estMarqueCommeTome(titre)
            )
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
            let serieExistante = serieCorrespondante(
                base, auteurs: resultat.auteurs, dans: series
            )
            // Refuser la croissance globale avant de réserver/refuser un
            // rayon : une action sans ajout ne doit laisser aucune mutation.
            guard placeDisponible(
                pour: resultat, statut: statut, series: series, dans: contexte
            ) else { return .limiteAtteinte }

            if let serieExistante {
                EditionsLocales.preparerAccesRayon(serieExistante)
                if Droits.partage.plus,
                   numero > Limites.tomesApercuSerie {
                    // Si le catalogue échoue puis que l'abonnement expire,
                    // cette origine payante persistante réactive le cadenas.
                    // Sans elle, une réservation mémoire disparaîtrait au
                    // redémarrage et un tome wishlist deviendrait possédable.
                    serieExistante.rayonHonyaPlus = true
                }
                let verrouille = numeroVerrouilleParRayon(
                    numero, de: serieExistante
                )
                if verrouille {
                    // Le droit protège aussi un volume d'abord rangé « À
                    // acheter » : après un redémarrage, sa fiche ne doit pas
                    // permettre de le transformer gratuitement en possession.
                    serieExistante.rayonRefuse = true
                }
                if statut != .wishlist, verrouille {
                    // Conserver la fiche exacte du scan, grisée : le lecteur
                    // voit ce qu'il a tenté d'ajouter, sans que `possede`
                    // puisse contourner Honya+.
                    integrerTome(
                        numero: numero,
                        depuis: resultat,
                        statut: .wishlist,
                        dans: serieExistante
                    )
                    lancerEnrichissement(
                        de: serieExistante, langue: objectif.languePrincipale
                    )
                    return .rayonVerrouille(serieExistante)
                }
            }
            let serie = serieExistante
                ?? creerSerieDepuisTome(
                    base: base, resultat: resultat, contexte: contexte
                )
            // Cette réservation doit précéder `integrerTome` et ne dépendre
            // d'aucun retour réseau : un lot scanné peut contenir dix volumes
            // et les appels de cette boucle s'enchaînent dans le même runloop.
            EditionsLocales.preparerAccesRayon(serie)
            if Droits.partage.plus,
               numero > Limites.tomesApercuSerie {
                serie.rayonHonyaPlus = true
            }
            let verrouille = numeroVerrouilleParRayon(numero, de: serie)
            if verrouille {
                // Même garantie pour une série créée par ce scan, y compris
                // lorsque son premier statut demandé est « À acheter ».
                serie.rayonRefuse = true
            }
            if statut != .wishlist, verrouille {
                integrerTome(
                    numero: numero,
                    depuis: resultat,
                    statut: .wishlist,
                    dans: serie
                )
                lancerEnrichissement(
                    de: serie, langue: objectif.languePrincipale
                )
                return .rayonVerrouille(serie)
            }
            integrerTome(numero: numero, depuis: resultat, statut: statut, dans: serie)
            // Une série née d'un scan possède déjà une couverture : attendre
            // l'ouverture de sa fiche ne lançait donc jamais la passe rayon.
            lancerEnrichissement(de: serie, langue: objectif.languePrincipale)
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
        serie.attributionCouverture = resultat.attributionCouverture
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

        tome.changerStatut(statut)
        switch statut {
        case .lu, .aLire, .enCours, .abandonne:
            // L'ajout concerne ce volume précis. La série se recalcule donc
            // depuis ses tomes (y compris « En cours » et « Abandonné »), au
            // lieu de recevoir un choix manuel global qui resterait collé.
            serie.statutChoisi = nil
        case .wishlist:
            break // le tome reste manquant : il est « à acheter »
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

    /// La déduplication des tâches est assurée dans `EditionsLocales`. Garder
    /// ce lancement indépendant de `rayonEnrichi` est essentiel : le quota
    /// reste une réservation mémoire jusqu'au premier résultat catalogue.
    private static func lancerEnrichissement(de serie: Serie, langue: String) {
        Task { @MainActor in
            await EditionsLocales.rafraichirSerieComplete(
                serie, langue: langue, profonde: true
            )
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
        serie.attributionCouverture = resultat.attributionCouverture
        serie.tomesTotal = resultat.tomesTotal
        serie.chapitresTotal = resultat.chapitresTotal
        serie.statutParution = resultat.statutParution
        serie.idAniList = resultat.idAniList

        // Le total explicite est conservé comme information, mais aucune case
        // future n'est créée ici : EditionsLocales réserve d'abord l'un des
        // trois rayons gratuits (ou vérifie Honya+) avant de matérialiser 1...N.
        contexte.insert(serie)
        EditionsLocales.preparerAccesRayon(serie)

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

import Foundation
import SwiftData

/// Reconstruit une bibliothèque locale depuis le format autonome v1.
///
/// Ce service ne contacte aucun serveur et ne choisit jamais de stratégie de
/// fusion. Une restauration n'est autorisée que dans un contexte propre et
/// vide, à l'exception de l'`Objectif` intact créé au premier lancement. Cette
/// contrainte est volontaire : remplacer ou fusionner silencieusement une
/// bibliothèque existante pourrait faire perdre des données utilisateur.
@MainActor
enum RestaurateurBibliothequeSnapshotV1 {
    enum Erreur: Error, LocalizedError, Sendable {
        case modificationsNonSauvegardees
        case contexteNonVide(entites: Int)
        case objectifExistantPersonnalise
        case plusieursObjectifsDansLeSnapshot(Int)

        var errorDescription: String? {
            switch self {
            case .modificationsNonSauvegardees:
                return "Le contexte contient des modifications non sauvegardées."
            case .contexteNonVide(let entites):
                return "La restauration exige une bibliothèque vide (\(entites) élément(s) existant(s))."
            case .objectifExistantPersonnalise:
                return "L’objectif existant contient déjà des préférences personnelles."
            case .plusieursObjectifsDansLeSnapshot(let nombre):
                return "Le snapshot contient \(nombre) objectifs alors qu’un seul est autorisé."
            }
        }
    }

    struct Rapport: Equatable, Sendable {
        let oeuvres: Int
        let exemplaires: Int
        let series: Int
        let tomes: Int
        let sessions: Int
        let citations: Int
        let objectifs: Int
        let collections: Int
        let badges: Int
        let objectifParDefautRemplace: Bool

        var total: Int {
            oeuvres + exemplaires + series + tomes + sessions
                + citations + objectifs + collections + badges
        }
    }

    /// Décode les dates numériques du snapshot en millisecondes Unix, comme
    /// l'encodeur v1, puis valide le document entier avant de le retourner.
    nonisolated static func decoder(_ donnees: Data) throws -> BibliothequeSnapshotV1 {
        let decodeur = JSONDecoder()
        decodeur.dateDecodingStrategy = .millisecondsSince1970
        let snapshot = try decodeur.decode(BibliothequeSnapshotV1.self, from: donnees)
        try snapshot.valider()
        try verifierContraintesDeRestauration(snapshot)
        return snapshot
    }

    static func restaurer(
        donnees: Data,
        dans contexte: ModelContext
    ) throws -> Rapport {
        let snapshot = try decoder(donnees)
        return try restaurer(snapshot: snapshot, dans: contexte)
    }

    /// Restaure un snapshot déjà matérialisé. La validation est répétée pour
    /// que cet overload ne permette pas de contourner le contrôle du JSON.
    static func restaurer(
        snapshot: BibliothequeSnapshotV1,
        dans contexte: ModelContext
    ) throws -> Rapport {
        try verifierPreconditions(snapshot: snapshot, contexte: contexte)
        let objectifInitial = try verifierContexteReceveur(contexte)

        return try executer(
            snapshot: snapshot,
            dans: contexte,
            objectifParDefautRemplace: objectifInitial != nil
        ) {
            if let objectifInitial {
                contexte.delete(objectifInitial)
            }
        }
    }

    /// Remplace explicitement une bibliothèque après arbitrage de l'appelant.
    /// Cette API n'est jamais choisie automatiquement : l'UI doit obtenir la
    /// confirmation de l'utilisateur avant de l'appeler.
    static func remplacer(
        snapshot: BibliothequeSnapshotV1,
        dans contexte: ModelContext
    ) throws -> Rapport {
        try verifierPreconditions(snapshot: snapshot, contexte: contexte)

        // Charger toutes les entités peut échouer ; le faire avant la première
        // suppression maintient la garantie « valider avant de muter ».
        let existants = try ContenuExistant.charger(depuis: contexte)

        return try executer(
            snapshot: snapshot,
            dans: contexte,
            objectifParDefautRemplace: false
        ) {
            existants.supprimer(dans: contexte)
        }
    }

    private static func verifierPreconditions(
        snapshot: BibliothequeSnapshotV1,
        contexte: ModelContext
    ) throws {
        guard !contexte.hasChanges else {
            throw Erreur.modificationsNonSauvegardees
        }
        try snapshot.valider()
        try verifierContraintesDeRestauration(snapshot)
    }

    /// Point transactionnel partagé par la restauration vide et le
    /// remplacement confirmé. `mutationInitiale` ne sauvegarde jamais.
    private static func executer(
        snapshot: BibliothequeSnapshotV1,
        dans contexte: ModelContext,
        objectifParDefautRemplace: Bool,
        mutationInitiale: () -> Void
    ) throws -> Rapport {
        do {
            mutationInitiale()
            try reconstruire(snapshot: snapshot, dans: contexte)

            // Tous les inserts et toutes les relations restent en mémoire
            // jusqu'à cette unique sauvegarde atomique.
            try contexte.save()

            return Rapport(
                oeuvres: snapshot.oeuvres.count,
                exemplaires: snapshot.exemplaires.count,
                series: snapshot.series.count,
                tomes: snapshot.tomes.count,
                sessions: snapshot.sessions.count,
                citations: snapshot.citations.count,
                objectifs: snapshot.objectifs.count,
                collections: snapshot.collections.count,
                badges: snapshot.badges.count,
                objectifParDefautRemplace: objectifParDefautRemplace
            )
        } catch {
            // Le contexte était garanti propre avant la première mutation :
            // rollback ne peut donc annuler aucune édition sans rapport.
            contexte.rollback()
            throw error
        }
    }

    private static func reconstruire(
        snapshot: BibliothequeSnapshotV1,
        dans contexte: ModelContext
    ) throws {
        var oeuvres: [UUID: Oeuvre] = [:]
        var exemplaires: [UUID: Exemplaire] = [:]
        var series: [UUID: Serie] = [:]
        var tomes: [UUID: Tome] = [:]
        var sessions: [UUID: SessionLecture] = [:]
        var citations: [UUID: Citation] = [:]
        var collections: [UUID: Collection] = [:]

        for donnees in snapshot.oeuvres {
            let modele = creerOeuvre(donnees)
            contexte.insert(modele)
            oeuvres[donnees.cloudID] = modele
        }
        for donnees in snapshot.exemplaires {
            let modele = creerExemplaire(donnees)
            contexte.insert(modele)
            exemplaires[donnees.cloudID] = modele
        }
        for donnees in snapshot.series {
            let modele = creerSerie(donnees)
            contexte.insert(modele)
            series[donnees.cloudID] = modele
        }
        for donnees in snapshot.tomes {
            let modele = creerTome(donnees)
            contexte.insert(modele)
            tomes[donnees.cloudID] = modele
        }
        for donnees in snapshot.sessions {
            let modele = creerSession(donnees)
            contexte.insert(modele)
            sessions[donnees.cloudID] = modele
        }
        for donnees in snapshot.citations {
            let modele = creerCitation(donnees)
            contexte.insert(modele)
            citations[donnees.cloudID] = modele
        }
        for donnees in snapshot.objectifs {
            contexte.insert(creerObjectif(donnees))
        }
        for donnees in snapshot.collections {
            let modele = creerCollection(donnees)
            contexte.insert(modele)
            collections[donnees.cloudID] = modele
        }
        for donnees in snapshot.badges {
            contexte.insert(creerBadge(donnees))
        }

        // Une seule extrémité de chaque relation est affectée. Les inverses
        // SwiftData déclarées dans les modèles reconstruisent l'autre côté
        // sans risquer d'insérer deux fois un élément dans une collection.
        for donnees in snapshot.exemplaires {
            guard let modele = exemplaires[donnees.cloudID] else {
                throw ErreurBibliothequeSnapshotV1.referenceInconnue(
                    donnees.cloudID,
                    source: "restauration exemplaire"
                )
            }
            modele.oeuvre = try resoudre(
                donnees.oeuvreCloudID,
                dans: oeuvres,
                source: "exemplaire \(donnees.cloudID)"
            )
        }

        for donnees in snapshot.tomes {
            guard let modele = tomes[donnees.cloudID] else {
                throw ErreurBibliothequeSnapshotV1.referenceInconnue(
                    donnees.cloudID,
                    source: "restauration tome"
                )
            }
            modele.serie = try resoudre(
                donnees.serieCloudID,
                dans: series,
                source: "tome \(donnees.cloudID)"
            )
        }

        for donnees in snapshot.sessions {
            guard let modele = sessions[donnees.cloudID] else {
                throw ErreurBibliothequeSnapshotV1.referenceInconnue(
                    donnees.cloudID,
                    source: "restauration session"
                )
            }
            modele.oeuvre = try resoudre(
                donnees.oeuvreCloudID,
                dans: oeuvres,
                source: "session \(donnees.cloudID)"
            )
            modele.serie = try resoudre(
                donnees.serieCloudID,
                dans: series,
                source: "session \(donnees.cloudID)"
            )
        }

        for donnees in snapshot.citations {
            guard let modele = citations[donnees.cloudID] else {
                throw ErreurBibliothequeSnapshotV1.referenceInconnue(
                    donnees.cloudID,
                    source: "restauration citation"
                )
            }
            modele.oeuvre = try resoudre(
                donnees.oeuvreCloudID,
                dans: oeuvres,
                source: "citation \(donnees.cloudID)"
            )
        }

        for donnees in snapshot.collections {
            guard let modele = collections[donnees.cloudID] else {
                throw ErreurBibliothequeSnapshotV1.referenceInconnue(
                    donnees.cloudID,
                    source: "restauration collection"
                )
            }
            modele.oeuvres = try donnees.oeuvreCloudIDs.map {
                try resoudre(
                    $0,
                    dans: oeuvres,
                    source: "collection \(donnees.cloudID)"
                )
            }
            modele.series = try donnees.serieCloudIDs.map {
                try resoudre(
                    $0,
                    dans: series,
                    source: "collection \(donnees.cloudID)"
                )
            }
        }
    }

    /// Graphe persistant chargé intégralement avant le remplacement. Garder les
    /// instances permet à `rollback()` de restaurer exactement leur dernier
    /// état sauvegardé si la reconstruction ou l'unique save final échoue.
    private struct ContenuExistant {
        let oeuvres: [Oeuvre]
        let exemplaires: [Exemplaire]
        let series: [Serie]
        let tomes: [Tome]
        let sessions: [SessionLecture]
        let citations: [Citation]
        let objectifs: [Objectif]
        let collections: [Collection]
        let badges: [BadgeGagne]

        @MainActor
        static func charger(depuis contexte: ModelContext) throws -> Self {
            let oeuvres = try contexte.fetch(FetchDescriptor<Oeuvre>())
            let exemplaires = try contexte.fetch(FetchDescriptor<Exemplaire>())
            let series = try contexte.fetch(FetchDescriptor<Serie>())
            let tomes = try contexte.fetch(FetchDescriptor<Tome>())
            let sessions = try contexte.fetch(FetchDescriptor<SessionLecture>())
            let citations = try contexte.fetch(FetchDescriptor<Citation>())
            let objectifs = try contexte.fetch(FetchDescriptor<Objectif>())
            let collections = try contexte.fetch(FetchDescriptor<Collection>())
            let badges = try contexte.fetch(FetchDescriptor<BadgeGagne>())
            return Self(
                oeuvres: oeuvres,
                exemplaires: exemplaires,
                series: series,
                tomes: tomes,
                sessions: sessions,
                citations: citations,
                objectifs: objectifs,
                collections: collections,
                badges: badges
            )
        }

        @MainActor
        func supprimer(dans contexte: ModelContext) {
            // Les relations et enfants sont retirés avant les racines dont les
            // règles sont en cascade. Chaque type du schéma est néanmoins
            // explicitement couvert, y compris les entités orphelines.
            for modele in collections { contexte.delete(modele) }
            for modele in sessions { contexte.delete(modele) }
            for modele in citations { contexte.delete(modele) }
            for modele in exemplaires { contexte.delete(modele) }
            for modele in tomes { contexte.delete(modele) }
            for modele in objectifs { contexte.delete(modele) }
            for modele in badges { contexte.delete(modele) }
            for modele in oeuvres { contexte.delete(modele) }
            for modele in series { contexte.delete(modele) }
        }
    }

    private nonisolated static func verifierContraintesDeRestauration(
        _ snapshot: BibliothequeSnapshotV1
    ) throws {
        guard snapshot.objectifs.count <= 1 else {
            throw Erreur.plusieursObjectifsDansLeSnapshot(snapshot.objectifs.count)
        }
    }

    /// Retourne l'unique objectif jetable, le cas échéant.
    private static func verifierContexteReceveur(
        _ contexte: ModelContext
    ) throws -> Objectif? {
        var significatifs = try contexte.fetchCount(FetchDescriptor<Oeuvre>())
        significatifs += try contexte.fetchCount(FetchDescriptor<Exemplaire>())
        significatifs += try contexte.fetchCount(FetchDescriptor<Serie>())
        significatifs += try contexte.fetchCount(FetchDescriptor<Tome>())
        significatifs += try contexte.fetchCount(FetchDescriptor<SessionLecture>())
        significatifs += try contexte.fetchCount(FetchDescriptor<Citation>())
        significatifs += try contexte.fetchCount(FetchDescriptor<Collection>())
        significatifs += try contexte.fetchCount(FetchDescriptor<BadgeGagne>())

        let objectifs = try contexte.fetch(FetchDescriptor<Objectif>())
        guard significatifs == 0, objectifs.count <= 1 else {
            throw Erreur.contexteNonVide(entites: significatifs + objectifs.count)
        }
        guard let objectif = objectifs.first else { return nil }
        guard objectifEstIntact(objectif) else {
            throw Erreur.objectifExistantPersonnalise
        }
        return objectif
    }

    private static func objectifEstIntact(_ objectif: Objectif) -> Bool {
        objectif.minutesParJour == 20
            && objectif.defiAnnuelLivres == 26
            && objectif.languesLecture.isEmpty
            && objectif.typesPreferes == [
                TypeOeuvre.livre.rawValue,
                TypeOeuvre.manga.rawValue,
            ]
            && objectif.emprunteursRecents.isEmpty
    }

    private static func resoudre<Modele>(
        _ identifiant: UUID,
        dans modeles: [UUID: Modele],
        source: String
    ) throws -> Modele {
        guard let modele = modeles[identifiant] else {
            throw ErreurBibliothequeSnapshotV1.referenceInconnue(
                identifiant,
                source: source
            )
        }
        return modele
    }

    private static func resoudre<Modele>(
        _ identifiant: UUID?,
        dans modeles: [UUID: Modele],
        source: String
    ) throws -> Modele? {
        guard let identifiant else { return nil }
        // Swift accepte la promotion implicite d'un UUID en UUID?, ce qui
        // rend l'appel à la surcharge non optionnelle ambigu sous Xcode 26.
        // Résoudre directement évite cette ambiguïté tout en conservant le
        // même diagnostic de snapshot corrompu.
        guard let modele = modeles[identifiant] else {
            throw ErreurBibliothequeSnapshotV1.referenceInconnue(
                identifiant,
                source: source
            )
        }
        return modele
    }

    private static func creerOeuvre(
        _ donnees: BibliothequeSnapshotV1.OeuvreDonnees
    ) -> Oeuvre {
        let modele = Oeuvre()
        modele.cloudID = donnees.cloudID
        modele.titreOriginal = donnees.titreOriginal
        modele.titres = donnees.titres
        modele.titreRomaji = donnees.titreRomaji
        modele.auteurs = donnees.auteurs
        modele.typeRaw = donnees.typeRaw
        modele.genres = donnees.genres
        modele.resume = donnees.resume
        modele.resumeLocal = donnees.resumeLocal
        modele.anneePublication = donnees.anneePublication
        modele.pages = donnees.pages
        modele.couvertureCanoniqueURL = donnees.couvertureCanoniqueURL
        modele.couvertureLocaleURL = donnees.couvertureLocaleURL
        modele.attributionCouverture = donnees.attributionCouverture
        modele.dernierEssaiEditionLocale = donnees.dernierEssaiEditionLocale
        modele.idExterne = donnees.idExterne
        modele.dateAjout = donnees.dateAjout
        return modele
    }

    private static func creerExemplaire(
        _ donnees: BibliothequeSnapshotV1.ExemplaireDonnees
    ) -> Exemplaire {
        let modele = Exemplaire()
        modele.cloudID = donnees.cloudID
        modele.statutRaw = donnees.statutRaw
        modele.possede = donnees.possede
        modele.note = donnees.note
        modele.moods = donnees.moods
        modele.pageCourante = donnees.pageCourante
        modele.formatRaw = donnees.formatRaw
        modele.prixPaye = donnees.prixPaye
        modele.preteA = donnees.preteA
        modele.preteLe = donnees.preteLe
        modele.isbn = donnees.isbn
        modele.langueEdition = donnees.langueEdition
        modele.couvertureEditionURL = donnees.couvertureEditionURL
        modele.couverturePersonnelleURL = donnees.couverturePersonnelleURL
        modele.dateAchat = donnees.dateAchat
        modele.dateDebut = donnees.dateDebut
        modele.dateFin = donnees.dateFin
        modele.aSuivre = donnees.aSuivre
        return modele
    }

    private static func creerSerie(
        _ donnees: BibliothequeSnapshotV1.SerieDonnees
    ) -> Serie {
        let modele = Serie()
        modele.cloudID = donnees.cloudID
        modele.nom = donnees.nom
        modele.noms = donnees.noms
        modele.nomsAlternatifs = donnees.nomsAlternatifs
        modele.nomRomaji = donnees.nomRomaji
        modele.auteur = donnees.auteur
        modele.typeRaw = donnees.typeRaw
        modele.genres = donnees.genres
        modele.resume = donnees.resume
        modele.resumeLocal = donnees.resumeLocal
        modele.couvertureURL = donnees.couvertureURL
        modele.attributionCouverture = donnees.attributionCouverture
        modele.couvertureLocaleURL = donnees.couvertureLocaleURL
        modele.dernierEssaiEditionLocale = donnees.dernierEssaiEditionLocale
        modele.tomesTotal = donnees.tomesTotal
        modele.statutParutionRaw = donnees.statutParutionRaw
        modele.chapitresLus = donnees.chapitresLus
        modele.chapitresTotal = donnees.chapitresTotal
        modele.prochaineSortieNumero = donnees.prochaineSortieNumero
        modele.prochaineSortieDate = donnees.prochaineSortieDate
        modele.rappelActive = donnees.rappelActive
        modele.identifiantRappelSortie = donnees.identifiantRappelSortie
        modele.idAniList = donnees.idAniList
        modele.dateAjout = donnees.dateAjout
        modele.statutManuelRaw = donnees.statutManuelRaw
        modele.statutManuelLe = donnees.statutManuelLe
        modele.rayonComplet = donnees.rayonComplet
        modele.rayonEnrichi = donnees.rayonEnrichi
        modele.rayonHonyaPlus = donnees.rayonHonyaPlus
        modele.rayonRefuse = donnees.rayonRefuse
        return modele
    }

    private static func creerTome(
        _ donnees: BibliothequeSnapshotV1.TomeDonnees
    ) -> Tome {
        let modele = Tome(numero: donnees.numero)
        modele.cloudID = donnees.cloudID
        modele.preteA = donnees.preteA
        modele.preteLe = donnees.preteLe
        modele.abandonne = donnees.abandonne
        modele.numero = donnees.numero
        modele.possede = donnees.possede
        modele.lu = donnees.lu
        modele.dateLu = donnees.dateLu
        modele.isbn = donnees.isbn
        modele.titre = donnees.titre
        modele.couvertureURL = donnees.couvertureURL
        modele.couverturePersonnelleURL = donnees.couverturePersonnelleURL
        modele.attributionCouverture = donnees.attributionCouverture
        modele.pages = donnees.pages
        modele.metadonneesManuelles = donnees.metadonneesManuelles
        modele.dateSortie = donnees.dateSortie
        return modele
    }

    private static func creerSession(
        _ donnees: BibliothequeSnapshotV1.SessionDonnees
    ) -> SessionLecture {
        let modele = SessionLecture(
            debut: donnees.debut,
            dureeSecondes: donnees.dureeSecondes,
            pagesLues: donnees.pagesLues
        )
        modele.cloudID = donnees.cloudID
        modele.mood = donnees.mood
        return modele
    }

    private static func creerCitation(
        _ donnees: BibliothequeSnapshotV1.CitationDonnees
    ) -> Citation {
        let modele = Citation(texte: donnees.texte, page: donnees.page)
        modele.cloudID = donnees.cloudID
        modele.dateAjout = donnees.dateAjout
        return modele
    }

    private static func creerObjectif(
        _ donnees: BibliothequeSnapshotV1.ObjectifDonnees
    ) -> Objectif {
        let modele = Objectif()
        modele.cloudID = donnees.cloudID
        modele.minutesParJour = donnees.minutesParJour
        modele.defiAnnuelLivres = donnees.defiAnnuelLivres
        modele.languesLecture = donnees.languesLecture
        modele.typesPreferes = donnees.typesPreferes
        modele.emprunteursRecents = donnees.emprunteursRecents
        return modele
    }

    private static func creerCollection(
        _ donnees: BibliothequeSnapshotV1.CollectionDonnees
    ) -> Collection {
        let modele = Collection(nom: donnees.nom, symbole: donnees.symbole)
        modele.cloudID = donnees.cloudID
        modele.dateCreation = donnees.dateCreation
        return modele
    }

    private static func creerBadge(
        _ donnees: BibliothequeSnapshotV1.BadgeDonnees
    ) -> BadgeGagne {
        let modele = BadgeGagne(typeRaw: donnees.typeRaw)
        modele.cloudID = donnees.cloudID
        modele.date = donnees.date
        return modele
    }
}

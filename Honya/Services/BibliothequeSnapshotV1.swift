import CryptoKit
import Foundation
import SwiftData

/// Représentation autonome et versionnée de la bibliothèque locale.
///
/// Les tableaux sont plats : aucune instance SwiftData n'est encodée et toutes
/// les relations sont exprimées avec les `cloudID`. La v1 conserve les deux
/// côtés des relations SwiftData afin qu'une future restauration puisse les
/// vérifier avant d'écrire quoi que ce soit dans le store local.
struct BibliothequeSnapshotV1: Codable, Sendable {
    static let versionActuelle = 1

    let version: Int
    let oeuvres: [OeuvreDonnees]
    let exemplaires: [ExemplaireDonnees]
    let series: [SerieDonnees]
    let tomes: [TomeDonnees]
    let sessions: [SessionDonnees]
    let citations: [CitationDonnees]
    let objectifs: [ObjectifDonnees]
    let collections: [CollectionDonnees]
    let badges: [BadgeDonnees]

    struct OeuvreDonnees: Codable, Sendable {
        let cloudID: UUID
        let titreOriginal: String
        let titres: [String: String]
        let titreRomaji: String?
        let auteurs: [String]
        let typeRaw: String
        let genres: [String]
        let resume: String?
        let resumeLocal: String?
        let anneePublication: Int?
        let pages: Int?
        let couvertureCanoniqueURL: String?
        let couvertureLocaleURL: String?
        let attributionCouverture: String?
        let dernierEssaiEditionLocale: Date?
        let idExterne: String?
        let dateAjout: Date
        let exemplaireCloudID: UUID?
        let citationCloudIDs: [UUID]
        let sessionCloudIDs: [UUID]
        let collectionCloudIDs: [UUID]
    }

    struct ExemplaireDonnees: Codable, Sendable {
        let cloudID: UUID
        let statutRaw: String
        let possede: Bool
        let note: Int?
        let moods: [String]
        let pageCourante: Int
        let formatRaw: String?
        let prixPaye: Double?
        let preteA: String?
        let preteLe: Date?
        let isbn: String?
        let langueEdition: String?
        let couvertureEditionURL: String?
        let couverturePersonnelleURL: String?
        let dateAchat: Date?
        let dateDebut: Date?
        let dateFin: Date?
        let aSuivre: Bool
        let oeuvreCloudID: UUID?
    }

    struct SerieDonnees: Codable, Sendable {
        let cloudID: UUID
        let nom: String
        let noms: [String: String]
        let nomsAlternatifs: [String]
        let nomRomaji: String?
        let auteur: String?
        let typeRaw: String
        let genres: [String]
        let resume: String?
        let resumeLocal: String?
        let couvertureURL: String?
        let attributionCouverture: String?
        let couvertureLocaleURL: String?
        let dernierEssaiEditionLocale: Date?
        let tomesTotal: Int?
        let statutParutionRaw: String
        let chapitresLus: Int
        let chapitresTotal: Int?
        let prochaineSortieNumero: Int?
        let prochaineSortieDate: Date?
        let rappelActive: Bool
        let identifiantRappelSortie: String?
        let idAniList: Int?
        let dateAjout: Date
        let statutManuelRaw: String?
        let statutManuelLe: Date?
        let rayonComplet: Bool
        let rayonEnrichi: Bool
        let rayonHonyaPlus: Bool
        let rayonRefuse: Bool
        let tomeCloudIDs: [UUID]
        let sessionCloudIDs: [UUID]
        let collectionCloudIDs: [UUID]
    }

    struct TomeDonnees: Codable, Sendable {
        let cloudID: UUID
        let preteA: String?
        let preteLe: Date?
        let abandonne: Bool
        let numero: Int
        let possede: Bool
        let lu: Bool
        let dateLu: Date?
        let isbn: String?
        let titre: String?
        let couvertureURL: String?
        let couverturePersonnelleURL: String?
        let attributionCouverture: String?
        let pages: Int?
        let metadonneesManuelles: Bool
        let dateSortie: Date?
        let serieCloudID: UUID?
    }

    struct SessionDonnees: Codable, Sendable {
        let cloudID: UUID
        let debut: Date
        let dureeSecondes: Int
        let pagesLues: Int
        let mood: String?
        let oeuvreCloudID: UUID?
        let serieCloudID: UUID?
    }

    struct CitationDonnees: Codable, Sendable {
        let cloudID: UUID
        let texte: String
        let page: Int?
        let dateAjout: Date
        let oeuvreCloudID: UUID?
    }

    struct ObjectifDonnees: Codable, Sendable {
        let cloudID: UUID
        let minutesParJour: Int
        let defiAnnuelLivres: Int
        let languesLecture: [String]
        let typesPreferes: [String]
        let emprunteursRecents: [String]
    }

    struct CollectionDonnees: Codable, Sendable {
        let cloudID: UUID
        let nom: String
        let symbole: String
        let dateCreation: Date
        let oeuvreCloudIDs: [UUID]
        let serieCloudIDs: [UUID]
    }

    struct BadgeDonnees: Codable, Sendable {
        let cloudID: UUID
        let typeRaw: String
        let date: Date
    }
}

enum ErreurBibliothequeSnapshotV1: Error, LocalizedError, Sendable {
    case versionInvalide(Int)
    case identifiantManquant(String)
    case identifiantDuplique(UUID, premier: String, second: String)
    case referenceDupliquee(UUID, source: String)
    case referenceInconnue(UUID, source: String)
    case relationIncoherente(String)

    var errorDescription: String? {
        switch self {
        case .versionInvalide(let version):
            return "Version de snapshot non prise en charge : \(version)."
        case .identifiantManquant(let entite):
            return "Identifiant cloud manquant pour \(entite)."
        case .identifiantDuplique(let identifiant, let premier, let second):
            return "Identifiant cloud \(identifiant) partagé par \(premier) et \(second)."
        case .referenceDupliquee(let identifiant, let source):
            return "Référence \(identifiant) dupliquée dans \(source)."
        case .referenceInconnue(let identifiant, let source):
            return "Référence \(identifiant) inconnue depuis \(source)."
        case .relationIncoherente(let detail):
            return "Relation incohérente : \(detail)."
        }
    }
}

extension BibliothequeSnapshotV1 {
    /// Refuse un document partiel ou ambigu avant son encodage et son hachage.
    func valider() throws {
        guard version == Self.versionActuelle else {
            throw ErreurBibliothequeSnapshotV1.versionInvalide(version)
        }

        var proprietaires: [UUID: String] = [:]
        func enregistrer(_ identifiant: UUID, comme description: String) throws {
            if let premier = proprietaires.updateValue(description, forKey: identifiant) {
                throw ErreurBibliothequeSnapshotV1.identifiantDuplique(
                    identifiant,
                    premier: premier,
                    second: description
                )
            }
        }

        for valeur in oeuvres { try enregistrer(valeur.cloudID, comme: "oeuvre") }
        for valeur in exemplaires { try enregistrer(valeur.cloudID, comme: "exemplaire") }
        for valeur in series { try enregistrer(valeur.cloudID, comme: "serie") }
        for valeur in tomes { try enregistrer(valeur.cloudID, comme: "tome") }
        for valeur in sessions { try enregistrer(valeur.cloudID, comme: "session") }
        for valeur in citations { try enregistrer(valeur.cloudID, comme: "citation") }
        for valeur in objectifs { try enregistrer(valeur.cloudID, comme: "objectif") }
        for valeur in collections { try enregistrer(valeur.cloudID, comme: "collection") }
        for valeur in badges { try enregistrer(valeur.cloudID, comme: "badge") }

        let oeuvreIDs = Set(oeuvres.map(\.cloudID))
        let exemplaireIDs = Set(exemplaires.map(\.cloudID))
        let serieIDs = Set(series.map(\.cloudID))
        let tomeIDs = Set(tomes.map(\.cloudID))
        let sessionIDs = Set(sessions.map(\.cloudID))
        let citationIDs = Set(citations.map(\.cloudID))
        let collectionIDs = Set(collections.map(\.cloudID))

        func verifier(
            _ references: [UUID],
            dans cibles: Set<UUID>,
            depuis source: String
        ) throws {
            var locales = Set<UUID>()
            for reference in references {
                guard locales.insert(reference).inserted else {
                    throw ErreurBibliothequeSnapshotV1.referenceDupliquee(reference, source: source)
                }
                guard cibles.contains(reference) else {
                    throw ErreurBibliothequeSnapshotV1.referenceInconnue(reference, source: source)
                }
            }
        }

        func verifier(
            _ reference: UUID?,
            dans cibles: Set<UUID>,
            depuis source: String
        ) throws {
            guard let reference else { return }
            guard cibles.contains(reference) else {
                throw ErreurBibliothequeSnapshotV1.referenceInconnue(reference, source: source)
            }
        }

        for valeur in oeuvres {
            let source = "oeuvre \(valeur.cloudID)"
            try verifier(valeur.exemplaireCloudID, dans: exemplaireIDs, depuis: source)
            try verifier(valeur.citationCloudIDs, dans: citationIDs, depuis: source)
            try verifier(valeur.sessionCloudIDs, dans: sessionIDs, depuis: source)
            try verifier(valeur.collectionCloudIDs, dans: collectionIDs, depuis: source)
        }
        for valeur in exemplaires {
            try verifier(
                valeur.oeuvreCloudID,
                dans: oeuvreIDs,
                depuis: "exemplaire \(valeur.cloudID)"
            )
        }
        for valeur in series {
            let source = "serie \(valeur.cloudID)"
            try verifier(valeur.tomeCloudIDs, dans: tomeIDs, depuis: source)
            try verifier(valeur.sessionCloudIDs, dans: sessionIDs, depuis: source)
            try verifier(valeur.collectionCloudIDs, dans: collectionIDs, depuis: source)
        }
        for valeur in tomes {
            try verifier(valeur.serieCloudID, dans: serieIDs, depuis: "tome \(valeur.cloudID)")
        }
        for valeur in sessions {
            let source = "session \(valeur.cloudID)"
            guard (valeur.oeuvreCloudID == nil) != (valeur.serieCloudID == nil) else {
                throw ErreurBibliothequeSnapshotV1.relationIncoherente(
                    "\(source) doit cibler exactement une oeuvre ou une serie"
                )
            }
            try verifier(valeur.oeuvreCloudID, dans: oeuvreIDs, depuis: source)
            try verifier(valeur.serieCloudID, dans: serieIDs, depuis: source)
        }
        for valeur in citations {
            try verifier(valeur.oeuvreCloudID, dans: oeuvreIDs, depuis: "citation \(valeur.cloudID)")
        }
        for valeur in collections {
            let source = "collection \(valeur.cloudID)"
            try verifier(valeur.oeuvreCloudIDs, dans: oeuvreIDs, depuis: source)
            try verifier(valeur.serieCloudIDs, dans: serieIDs, depuis: source)
        }

        try validerRelationsInverses()
    }

    private func validerRelationsInverses() throws {
        let oeuvresParID = Dictionary(uniqueKeysWithValues: oeuvres.map { ($0.cloudID, $0) })
        let exemplairesParID = Dictionary(uniqueKeysWithValues: exemplaires.map { ($0.cloudID, $0) })
        let seriesParID = Dictionary(uniqueKeysWithValues: series.map { ($0.cloudID, $0) })
        let tomesParID = Dictionary(uniqueKeysWithValues: tomes.map { ($0.cloudID, $0) })
        let sessionsParID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.cloudID, $0) })
        let citationsParID = Dictionary(uniqueKeysWithValues: citations.map { ($0.cloudID, $0) })
        let collectionsParID = Dictionary(uniqueKeysWithValues: collections.map { ($0.cloudID, $0) })

        func incoherente(_ detail: String) throws {
            throw ErreurBibliothequeSnapshotV1.relationIncoherente(detail)
        }

        for oeuvre in oeuvres {
            if let identifiant = oeuvre.exemplaireCloudID,
               exemplairesParID[identifiant]?.oeuvreCloudID != oeuvre.cloudID {
                try incoherente("oeuvre.exemplaire ↔ exemplaire.oeuvre")
            }
            for identifiant in oeuvre.citationCloudIDs
            where citationsParID[identifiant]?.oeuvreCloudID != oeuvre.cloudID {
                try incoherente("oeuvre.citations ↔ citation.oeuvre")
            }
            for identifiant in oeuvre.sessionCloudIDs
            where sessionsParID[identifiant]?.oeuvreCloudID != oeuvre.cloudID {
                try incoherente("oeuvre.sessions ↔ session.oeuvre")
            }
            for identifiant in oeuvre.collectionCloudIDs
            where collectionsParID[identifiant]?.oeuvreCloudIDs.contains(oeuvre.cloudID) != true {
                try incoherente("oeuvre.collections ↔ collection.oeuvres")
            }
        }

        for exemplaire in exemplaires {
            if let identifiant = exemplaire.oeuvreCloudID,
               oeuvresParID[identifiant]?.exemplaireCloudID != exemplaire.cloudID {
                try incoherente("exemplaire.oeuvre ↔ oeuvre.exemplaire")
            }
        }

        for serie in series {
            for identifiant in serie.tomeCloudIDs
            where tomesParID[identifiant]?.serieCloudID != serie.cloudID {
                try incoherente("serie.tomes ↔ tome.serie")
            }
            for identifiant in serie.sessionCloudIDs
            where sessionsParID[identifiant]?.serieCloudID != serie.cloudID {
                try incoherente("serie.sessions ↔ session.serie")
            }
            for identifiant in serie.collectionCloudIDs
            where collectionsParID[identifiant]?.serieCloudIDs.contains(serie.cloudID) != true {
                try incoherente("serie.collections ↔ collection.series")
            }
        }

        for tome in tomes {
            if let identifiant = tome.serieCloudID,
               seriesParID[identifiant]?.tomeCloudIDs.contains(tome.cloudID) != true {
                try incoherente("tome.serie ↔ serie.tomes")
            }
        }

        for session in sessions {
            if let identifiant = session.oeuvreCloudID,
               oeuvresParID[identifiant]?.sessionCloudIDs.contains(session.cloudID) != true {
                try incoherente("session.oeuvre ↔ oeuvre.sessions")
            }
            if let identifiant = session.serieCloudID,
               seriesParID[identifiant]?.sessionCloudIDs.contains(session.cloudID) != true {
                try incoherente("session.serie ↔ serie.sessions")
            }
        }

        for citation in citations {
            if let identifiant = citation.oeuvreCloudID,
               oeuvresParID[identifiant]?.citationCloudIDs.contains(citation.cloudID) != true {
                try incoherente("citation.oeuvre ↔ oeuvre.citations")
            }
        }

        for collection in collections {
            for identifiant in collection.oeuvreCloudIDs
            where oeuvresParID[identifiant]?.collectionCloudIDs.contains(collection.cloudID) != true {
                try incoherente("collection.oeuvres ↔ oeuvre.collections")
            }
            for identifiant in collection.serieCloudIDs
            where seriesParID[identifiant]?.collectionCloudIDs.contains(collection.cloudID) != true {
                try incoherente("collection.series ↔ serie.collections")
            }
        }
    }
}

/// Exporte uniquement l'état local. Aucun réseau, upload, restauration ou
/// branchement UI n'est effectué ici.
@MainActor
enum ExporteurBibliothequeSnapshotV1 {
    struct Resultat: Sendable {
        let snapshot: BibliothequeSnapshotV1
        let donnees: Data
        /// SHA-256 hexadécimal des octets exacts de `donnees`.
        let empreinteSHA256: String
    }

    static func exporter(depuis contexte: ModelContext) throws -> Resultat {
        // Une sauvegarde doit inclure la toute dernière note ou progression.
        // Persister d'abord rend aussi le rollback défensif du backfill sans
        // danger pour des modifications utilisateur sans rapport.
        if contexte.hasChanges { try contexte.save() }
        _ = try IdentifiantsCloud.reparer(dans: contexte)

        let snapshot = try BibliothequeSnapshotV1(
            version: BibliothequeSnapshotV1.versionActuelle,
            oeuvres: contexte.fetch(FetchDescriptor<Oeuvre>())
                .map { try convertir($0) }.triesParIdentifiant(),
            exemplaires: contexte.fetch(FetchDescriptor<Exemplaire>())
                .map { try convertir($0) }.triesParIdentifiant(),
            series: contexte.fetch(FetchDescriptor<Serie>())
                .map { try convertir($0) }.triesParIdentifiant(),
            tomes: contexte.fetch(FetchDescriptor<Tome>())
                .map { try convertir($0) }.triesParIdentifiant(),
            sessions: contexte.fetch(FetchDescriptor<SessionLecture>())
                .map { try convertir($0) }.triesParIdentifiant(),
            citations: contexte.fetch(FetchDescriptor<Citation>())
                .map { try convertir($0) }.triesParIdentifiant(),
            objectifs: contexte.fetch(FetchDescriptor<Objectif>())
                .map { try convertir($0) }.triesParIdentifiant(),
            collections: contexte.fetch(FetchDescriptor<Collection>())
                .map { try convertir($0) }.triesParIdentifiant(),
            badges: contexte.fetch(FetchDescriptor<BadgeGagne>())
                .map { try convertir($0) }.triesParIdentifiant()
        )
        try snapshot.valider()

        let encodeur = JSONEncoder()
        encodeur.outputFormatting = [.sortedKeys]
        encodeur.dateEncodingStrategy = .millisecondsSince1970
        let donnees = try encodeur.encode(snapshot)
        let empreinte = SHA256.hash(data: donnees)
            .map { String(format: "%02x", $0) }
            .joined()

        return Resultat(snapshot: snapshot, donnees: donnees, empreinteSHA256: empreinte)
    }

    private static func convertir(_ modele: Oeuvre) throws -> BibliothequeSnapshotV1.OeuvreDonnees {
        try .init(
            cloudID: identifiant(modele.cloudID, entite: "oeuvre"),
            titreOriginal: modele.titreOriginal,
            titres: modele.titres,
            titreRomaji: modele.titreRomaji,
            auteurs: modele.auteurs,
            typeRaw: modele.typeRaw,
            genres: modele.genres,
            resume: modele.resume,
            resumeLocal: modele.resumeLocal,
            anneePublication: modele.anneePublication,
            pages: modele.pages,
            couvertureCanoniqueURL: modele.couvertureCanoniqueURL,
            couvertureLocaleURL: modele.couvertureLocaleURL,
            attributionCouverture: modele.attributionCouverture,
            dernierEssaiEditionLocale: modele.dernierEssaiEditionLocale,
            idExterne: modele.idExterne,
            dateAjout: modele.dateAjout,
            exemplaireCloudID: identifiant(modele.exemplaire, entite: "exemplaire"),
            citationCloudIDs: identifiants(modeles: modele.citations, entite: "citation"),
            sessionCloudIDs: identifiants(modeles: modele.sessions, entite: "session"),
            collectionCloudIDs: identifiants(modeles: modele.collections, entite: "collection")
        )
    }

    private static func convertir(_ modele: Exemplaire) throws -> BibliothequeSnapshotV1.ExemplaireDonnees {
        try .init(
            cloudID: identifiant(modele.cloudID, entite: "exemplaire"),
            statutRaw: modele.statutRaw,
            possede: modele.possede,
            note: modele.note,
            moods: modele.moods,
            pageCourante: modele.pageCourante,
            formatRaw: modele.formatRaw,
            prixPaye: modele.prixPaye,
            preteA: modele.preteA,
            preteLe: modele.preteLe,
            isbn: modele.isbn,
            langueEdition: modele.langueEdition,
            couvertureEditionURL: modele.couvertureEditionURL,
            couverturePersonnelleURL: modele.couverturePersonnelleURL,
            dateAchat: modele.dateAchat,
            dateDebut: modele.dateDebut,
            dateFin: modele.dateFin,
            aSuivre: modele.aSuivre,
            oeuvreCloudID: identifiant(modele.oeuvre, entite: "oeuvre")
        )
    }

    private static func convertir(_ modele: Serie) throws -> BibliothequeSnapshotV1.SerieDonnees {
        try .init(
            cloudID: identifiant(modele.cloudID, entite: "serie"),
            nom: modele.nom,
            noms: modele.noms,
            nomsAlternatifs: modele.nomsAlternatifs,
            nomRomaji: modele.nomRomaji,
            auteur: modele.auteur,
            typeRaw: modele.typeRaw,
            genres: modele.genres,
            resume: modele.resume,
            resumeLocal: modele.resumeLocal,
            couvertureURL: modele.couvertureURL,
            attributionCouverture: modele.attributionCouverture,
            couvertureLocaleURL: modele.couvertureLocaleURL,
            dernierEssaiEditionLocale: modele.dernierEssaiEditionLocale,
            tomesTotal: modele.tomesTotal,
            statutParutionRaw: modele.statutParutionRaw,
            chapitresLus: modele.chapitresLus,
            chapitresTotal: modele.chapitresTotal,
            prochaineSortieNumero: modele.prochaineSortieNumero,
            prochaineSortieDate: modele.prochaineSortieDate,
            rappelActive: modele.rappelActive,
            identifiantRappelSortie: modele.identifiantRappelSortie,
            idAniList: modele.idAniList,
            dateAjout: modele.dateAjout,
            statutManuelRaw: modele.statutManuelRaw,
            statutManuelLe: modele.statutManuelLe,
            rayonComplet: modele.rayonComplet,
            rayonEnrichi: modele.rayonEnrichi,
            rayonHonyaPlus: modele.rayonHonyaPlus,
            rayonRefuse: modele.rayonRefuse,
            tomeCloudIDs: identifiants(modeles: modele.tomes, entite: "tome"),
            sessionCloudIDs: identifiants(modeles: modele.sessions, entite: "session"),
            collectionCloudIDs: identifiants(modeles: modele.collections, entite: "collection")
        )
    }

    private static func convertir(_ modele: Tome) throws -> BibliothequeSnapshotV1.TomeDonnees {
        try .init(
            cloudID: identifiant(modele.cloudID, entite: "tome"),
            preteA: modele.preteA,
            preteLe: modele.preteLe,
            abandonne: modele.abandonne,
            numero: modele.numero,
            possede: modele.possede,
            lu: modele.lu,
            dateLu: modele.dateLu,
            isbn: modele.isbn,
            titre: modele.titre,
            couvertureURL: modele.couvertureURL,
            couverturePersonnelleURL: modele.couverturePersonnelleURL,
            attributionCouverture: modele.attributionCouverture,
            pages: modele.pages,
            metadonneesManuelles: modele.metadonneesManuelles,
            dateSortie: modele.dateSortie,
            serieCloudID: identifiant(modele.serie, entite: "serie")
        )
    }

    private static func convertir(_ modele: SessionLecture) throws -> BibliothequeSnapshotV1.SessionDonnees {
        try .init(
            cloudID: identifiant(modele.cloudID, entite: "session"),
            debut: modele.debut,
            dureeSecondes: modele.dureeSecondes,
            pagesLues: modele.pagesLues,
            mood: modele.mood,
            oeuvreCloudID: identifiant(modele.oeuvre, entite: "oeuvre"),
            serieCloudID: identifiant(modele.serie, entite: "serie")
        )
    }

    private static func convertir(_ modele: Citation) throws -> BibliothequeSnapshotV1.CitationDonnees {
        try .init(
            cloudID: identifiant(modele.cloudID, entite: "citation"),
            texte: modele.texte,
            page: modele.page,
            dateAjout: modele.dateAjout,
            oeuvreCloudID: identifiant(modele.oeuvre, entite: "oeuvre")
        )
    }

    private static func convertir(_ modele: Objectif) throws -> BibliothequeSnapshotV1.ObjectifDonnees {
        try .init(
            cloudID: identifiant(modele.cloudID, entite: "objectif"),
            minutesParJour: modele.minutesParJour,
            defiAnnuelLivres: modele.defiAnnuelLivres,
            languesLecture: modele.languesLecture,
            typesPreferes: modele.typesPreferes,
            emprunteursRecents: modele.emprunteursRecents
        )
    }

    private static func convertir(_ modele: Collection) throws -> BibliothequeSnapshotV1.CollectionDonnees {
        try .init(
            cloudID: identifiant(modele.cloudID, entite: "collection"),
            nom: modele.nom,
            symbole: modele.symbole,
            dateCreation: modele.dateCreation,
            oeuvreCloudIDs: identifiants(modeles: modele.oeuvres, entite: "oeuvre"),
            serieCloudIDs: identifiants(modeles: modele.series, entite: "serie")
        )
    }

    private static func convertir(_ modele: BadgeGagne) throws -> BibliothequeSnapshotV1.BadgeDonnees {
        try .init(
            cloudID: identifiant(modele.cloudID, entite: "badge"),
            typeRaw: modele.typeRaw,
            date: modele.date
        )
    }

    private static func identifiant(
        _ valeur: UUID?,
        entite: String
    ) throws -> UUID {
        guard let valeur else {
            throw ErreurBibliothequeSnapshotV1.identifiantManquant(entite)
        }
        return valeur
    }

    private static func identifiant<Modele: ModeleIdentifieCloud>(
        _ modele: Modele?,
        entite: String
    ) throws -> UUID? {
        guard let modele else { return nil }
        return try identifiant(modele.cloudID, entite: entite)
    }

    private static func identifiants<Modele: ModeleIdentifieCloud>(
        modeles: [Modele],
        entite: String
    ) throws -> [UUID] {
        try modeles.map { try identifiant($0.cloudID, entite: entite) }
            .sorted { $0.uuidString < $1.uuidString }
    }
}

private protocol ModeleIdentifieCloud: AnyObject {
    var cloudID: UUID? { get }
}

extension Oeuvre: ModeleIdentifieCloud {}
extension Exemplaire: ModeleIdentifieCloud {}
extension Serie: ModeleIdentifieCloud {}
extension Tome: ModeleIdentifieCloud {}
extension SessionLecture: ModeleIdentifieCloud {}
extension Citation: ModeleIdentifieCloud {}
extension Objectif: ModeleIdentifieCloud {}
extension Collection: ModeleIdentifieCloud {}
extension BadgeGagne: ModeleIdentifieCloud {}

private protocol DonneesIdentifieesSnapshot {
    var cloudID: UUID { get }
}

extension BibliothequeSnapshotV1.OeuvreDonnees: DonneesIdentifieesSnapshot {}
extension BibliothequeSnapshotV1.ExemplaireDonnees: DonneesIdentifieesSnapshot {}
extension BibliothequeSnapshotV1.SerieDonnees: DonneesIdentifieesSnapshot {}
extension BibliothequeSnapshotV1.TomeDonnees: DonneesIdentifieesSnapshot {}
extension BibliothequeSnapshotV1.SessionDonnees: DonneesIdentifieesSnapshot {}
extension BibliothequeSnapshotV1.CitationDonnees: DonneesIdentifieesSnapshot {}
extension BibliothequeSnapshotV1.ObjectifDonnees: DonneesIdentifieesSnapshot {}
extension BibliothequeSnapshotV1.CollectionDonnees: DonneesIdentifieesSnapshot {}
extension BibliothequeSnapshotV1.BadgeDonnees: DonneesIdentifieesSnapshot {}

private extension Array where Element: DonneesIdentifieesSnapshot {
    func triesParIdentifiant() -> Self {
        sorted { $0.cloudID.uuidString < $1.cloudID.uuidString }
    }
}

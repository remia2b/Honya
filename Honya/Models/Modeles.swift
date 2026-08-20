import Foundation
import SwiftData

// MARK: - Énumérations du domaine

enum TypeOeuvre: String, Codable, CaseIterable, Identifiable {
    case livre, manga, bd

    var id: String { rawValue }

    var libelle: String {
        switch self {
        case .livre: return "Livre"
        case .manga: return "Manga"
        case .bd: return "BD"
        }
    }
}

enum StatutLecture: String, Codable, CaseIterable, Identifiable {
    case aLire, enCours, lu, abandonne, wishlist

    var id: String { rawValue }

    var libelle: String {
        switch self {
        case .aLire: return "À lire"
        case .enCours: return "En cours"
        case .lu: return "Lu"
        case .abandonne: return "Abandonné"
        case .wishlist: return "Wishlist"
        }
    }
}

enum FormatLivre: String, Codable, CaseIterable, Identifiable {
    case poche, grandFormat, relie, numerique, audio

    var id: String { rawValue }

    var libelle: String {
        switch self {
        case .poche: return "Poche"
        case .grandFormat: return "Grand format"
        case .relie: return "Relié"
        case .numerique: return "Numérique"
        case .audio: return "Audio"
        }
    }
}

enum StatutParution: String, Codable {
    case enCours, terminee, inconnue

    var libelle: String {
        switch self {
        case .enCours: return "En cours de parution"
        case .terminee: return "Terminée"
        case .inconnue: return "Parution inconnue"
        }
    }
}

/// Moods proposés sur la fiche (inspiré StoryGraph/Fable).
enum Moods {
    static let tous = ["Épique", "Doux", "Sombre", "Drôle", "Haletant", "Contemplatif", "Politique", "Émouvant"]
}

// MARK: - Œuvre (métadonnées universelles, partagées par tous les utilisateurs)

@Model
final class Oeuvre {
    /// Titre dans la langue d'origine de l'œuvre.
    var titreOriginal: String = ""
    /// Titres OFFICIELS publiés, par code langue ("fr", "en", …). Jamais de traduction automatique.
    var titres: [String: String] = [:]
    /// Translittération latine, pour rester lisible quand seul le titre natif existe.
    var titreRomaji: String?
    var auteurs: [String] = []
    var typeRaw: String = TypeOeuvre.livre.rawValue
    var genres: [String] = []
    var resume: String?
    var anneePublication: Int?
    var pages: Int?
    /// Couverture canonique GLOBALE : la même pour tout le monde (politique produit).
    var couvertureCanoniqueURL: String?
    /// Identifiant de la source (volumeId Google Books, id AniList…), pour dédupliquer.
    var idExterne: String?
    var dateAjout: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \Exemplaire.oeuvre)
    var exemplaire: Exemplaire?

    @Relationship(deleteRule: .cascade, inverse: \Citation.oeuvre)
    var citations: [Citation] = []

    @Relationship(deleteRule: .cascade, inverse: \SessionLecture.oeuvre)
    var sessions: [SessionLecture] = []

    /// Collections personnelles auxquelles ce livre appartient.
    var collections: [Collection] = []

    init(titreOriginal: String = """, auteurs: [String] = [], type: TypeOeuvre = .livre) {
        self.titreOriginal = titreOriginal
        self.auteurs = auteurs
        self.typeRaw = type.rawValue
    }

    var type: TypeOeuvre {
        get { TypeOeuvre(rawValue: typeRaw) ?? .livre }
        set { typeRaw = newValue.rawValue }
    }

    /// Titre affiché : celui qu'un lecteur de cette langue verrait en librairie.
    func titre(_ langue: String) -> String {
        Titres.afficher(titres: titres, original: titreOriginal, romaji: titreRomaji, langue: langue)
    }

    var auteurPrincipal: String { auteurs.first ?? "" }
}

// MARK: - Exemplaire (la relation de l'utilisateur à une œuvre)

@Model
final class Exemplaire {
    var statutRaw: String = StatutLecture.aLire.rawValue
    var possede: Bool = true
    /// Note sur 10 (permet les demi-étoiles). nil = pas encore noté.
    var note: Int?
    var moods: [String] = []
    var pageCourante: Int = 0
    var formatRaw: String?
    var prixPaye: Double?
    var preteA: String?
    /// ISBN de l'édition réellement possédée.
    var isbn: String?
    var langueEdition: String?
    /// Couverture de l'édition scannée — stockée mais non affichée (politique couverture canonique).
    var couvertureEditionURL: String?
    var dateAchat: Date?
    var dateDebut: Date?
    var dateFin: Date?
    /// Dans la file « À suivre » de l'écran Aujourd'hui.
    var aSuivre: Bool = false

    var oeuvre: Oeuvre?

    init(statut: StatutLecture = .aLire, possede: Bool = true) {
        self.statutRaw = statut.rawValue
        self.possede = possede
    }

    var statut: StatutLecture {
        get { StatutLecture(rawValue: statutRaw) ?? .aLire }
        set { statutRaw = newValue.rawValue }
    }

    var format: FormatLivre? {
        get { formatRaw.flatMap(FormatLivre.init(rawValue:)) }
        set { formatRaw = newValue?.rawValue }
    }

    var progression: Double {
        guard let pages = oeuvre?.pages, pages > 0 else { return 0 }
        return min(1, Double(pageCourante) / Double(pages))
    }

    /// Change le statut en tenant les dates à jour.
    func changerStatut(_ nouveau: StatutLecture) {
        statut = nouveau
        switch nouveau {
        case .enCours where dateDebut == nil: dateDebut = Date()
        case .lu:
            if dateFin == nil { dateFin = Date() }
            if let pages = oeuvre?.pages { pageCourante = pages }
        case .wishlist: possede = false
        default: break
        }
    }
}

// MARK: - Série (manga / BD / saga)

@Model
final class Serie {
    var nom: String = ""
    /// Noms OFFICIELS par langue, même politique que les titres d'œuvres.
    var noms: [String: String] = [:]
    /// Translittération latine (romaji), lisible sans connaître le script d'origine.
    var nomRomaji: String?
    var auteur: String?
    var typeRaw: String = TypeOeuvre.manga.rawValue
    var genres: [String] = []
    var resume: String?
    /// Couverture canonique globale de la série.
    var couvertureURL: String?
    var tomesTotal: Int?
    var statutParutionRaw: String = StatutParution.inconnue.rawValue
    var chapitresLus: Int = 0
    var chapitresTotal: Int?
    var prochaineSortieNumero: Int?
    var prochaineSortieDate: Date?
    var rappelActive: Bool = false
    var idAniList: Int?
    var dateAjout: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \Tome.serie)
    var tomes: [Tome] = []

    @Relationship(deleteRule: .cascade, inverse: \SessionLecture.serie)
    var sessions: [SessionLecture] = []

    /// Collections personnelles auxquelles cette série appartient.
    var collections: [Collection] = []

    init(nom: String = """, type: TypeOeuvre = .manga) {
        self.nom = nom
        self.typeRaw = type.rawValue
    }

    var type: TypeOeuvre {
        get { TypeOeuvre(rawValue: typeRaw) ?? .manga }
        set { typeRaw = newValue.rawValue }
    }

    var statutParution: StatutParution {
        get { StatutParution(rawValue: statutParutionRaw) ?? .inconnue }
        set { statutParutionRaw = newValue.rawValue }
    }

    func nomAffiche(_ langue: String) -> String {
        Titres.afficher(titres: noms, original: nom, romaji: nomRomaji, langue: langue)
    }

    var tomesTries: [Tome] { tomes.sorted { $0.numero < $1.numero } }
    var nbPossedes: Int { tomes.filter(\.possede).count }
    var nbLus: Int { tomes.filter(\.lu).count }

    var prochainAAcheter: Int? {
        tomesTries.first(where: { !$0.possede })?.numero
    }

    /// La série apparaît dans « En cours » si on a commencé sans finir.
    var lectureEnCours: Bool {
        (nbLus > 0 && nbLus < tomes.count) || (chapitresLus > 0)
    }
}

// MARK: - Tome

@Model
final class Tome {
    var numero: Int = 1
    var possede: Bool = false
    var lu: Bool = false
    var dateLu: Date?
    var isbn: String?

    var serie: Serie?

    init(numero: Int, possede: Bool = false, lu: Bool = false) {
        self.numero = numero
        self.possede = possede
        self.lu = lu
    }
}

// MARK: - Session de lecture

@Model
final class SessionLecture {
    var debut: Date = Date()
    var dureeSecondes: Int = 0
    var pagesLues: Int = 0
    var mood: String?

    var oeuvre: Oeuvre?
    var serie: Serie?

    init(debut: Date = Date(), dureeSecondes: Int = 0, pagesLues: Int = 0) {
        self.debut = debut
        self.dureeSecondes = dureeSecondes
        self.pagesLues = pagesLues
    }

    var minutes: Int { dureeSecondes / 60 }

    var titreCible: String {
        if let oeuvre { return oeuvre.titre(Langues.codeAppareil) }
        if let serie { return serie.nomAffiche(Langues.codeAppareil) }
        return "Lecture"
    }
}

// MARK: - Citation

@Model
final class Citation {
    var texte: String = ""
    var page: Int?
    var dateAjout: Date = Date()

    var oeuvre: Oeuvre?

    init(texte: String, page: Int? = nil) {
        self.texte = texte
        self.page = page
    }
}

// MARK: - Objectif & préférences de lecture

@Model
final class Objectif {
    var minutesParJour: Int = 20
    var defiAnnuelLivres: Int = 26
    /// Langues de lecture préférées, codes ISO ("fr", "en"…). Pilote la recherche et l'affichage des titres.
    var languesLecture: [String] = []
    /// Types d'œuvres qui intéressent l'utilisateur (onboarding).
    var typesPreferes: [String] = [TypeOeuvre.livre.rawValue, TypeOeuvre.manga.rawValue]

    init() {}

    var languePrincipale: String { languesLecture.first ?? Langues.codeAppareil }

    /// Récupère (ou crée) l'objectif unique de l'utilisateur.
    static func courant(dans contexte: ModelContext) -> Objectif {
        if let existant = (try? contexte.fetch(FetchDescriptor<Objectif>()))?.first {
            return existant
        }
        let nouveau = Objectif()
        contexte.insert(nouveau)
        return nouveau
    }
}

// MARK: - Collection personnelle
//
// L'équivalent des collections d'Apple Books : des étagères que l'on compose
// soi-même, en plus des statuts de lecture.

@Model
final class Collection {
    var nom: String = ""
    var symbole: String = "square.stack"
    var dateCreation: Date = Date()

    @Relationship(inverse: \Oeuvre.collections)
    var oeuvres: [Oeuvre] = []

    @Relationship(inverse: \Serie.collections)
    var series: [Serie] = []

    init(nom: String, symbole: String = "square.stack") {
        self.nom = nom
        self.symbole = symbole
    }

    var nombre: Int { oeuvres.count + series.count }
}

/// Étagères calculées automatiquement : elles n'existent pas en base, elles
/// répondent à une question qu'on se pose souvent devant sa bibliothèque.
enum CollectionAuto: String, CaseIterable, Identifiable {
    case seriesIncompletes, coupsDeCoeur, achetesCetteAnnee, jamaisOuverts, pretes

    var id: String { rawValue }

    var nom: String {
        switch self {
        case .seriesIncompletes: return "Séries incomplètes"
        case .coupsDeCoeur: return "Coups de cœur"
        case .achetesCetteAnnee: return "Achetés cette année"
        case .jamaisOuverts: return "Jamais ouverts"
        case .pretes: return "Prêtés"
        }
    }

    var symbole: String {
        switch self {
        case .seriesIncompletes: return "square.stack.3d.up.slash"
        case .coupsDeCoeur: return "heart.fill"
        case .achetesCetteAnnee: return "calendar"
        case .jamaisOuverts: return "books.vertical"
        case .pretes: return "person.badge.clock"
        }
    }

    func exemplaires(_ tous: [Exemplaire]) -> [Exemplaire] {
        let annee = Calendar.current.component(.year, from: .now)
        switch self {
        case .coupsDeCoeur:
            return tous.filter { ($0.note ?? 0) >= 8 }
        case .achetesCetteAnnee:
            return tous.filter {
                guard let achat = $0.dateAchat else { return false }
                return Calendar.current.component(.year, from: achat) == annee
            }
        case .jamaisOuverts:
            return tous.filter { $0.possede && $0.statut == .aLire }
        case .pretes:
            return tous.filter { $0.preteA != nil }
        case .seriesIncompletes:
            return []
        }
    }

    func series(_ toutes: [Serie]) -> [Serie] {
        switch self {
        case .seriesIncompletes:
            return toutes.filter { !$0.tomes.isEmpty && $0.nbPossedes < $0.tomes.count }
        default:
            return []
        }
    }
}

// MARK: - Badge gagné

@Model
final class BadgeGagne {
    var typeRaw: String = ""
    var date: Date = Date()

    init(typeRaw: String) {
        self.typeRaw = typeRaw
    }
}

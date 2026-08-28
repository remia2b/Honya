import Foundation
import SwiftData

// MARK: - Énumérations du domaine

enum TypeOeuvre: String, Codable, CaseIterable, Identifiable, Sendable {
    case livre, manga, bd

    var id: String { rawValue }

    var libelle: String {
        switch self {
        case .livre: return String(localized: "Livre")
        case .manga: return String(localized: "Manga")
        case .bd: return String(localized: "BD")
        }
    }
}

enum StatutLecture: String, Codable, CaseIterable, Identifiable {
    case aLire, enCours, lu, abandonne, wishlist

    var id: String { rawValue }

    var libelle: String {
        switch self {
        case .aLire: return String(localized: "À lire")
        case .enCours: return String(localized: "En cours")
        case .lu: return String(localized: "Lu")
        case .abandonne: return String(localized: "Abandonné")
        case .wishlist: return String(localized: "À acheter")
        }
    }
}

enum FormatLivre: String, Codable, CaseIterable, Identifiable {
    case poche, grandFormat, relie, numerique, audio

    var id: String { rawValue }

    var libelle: String {
        switch self {
        case .poche: return String(localized: "Poche")
        case .grandFormat: return String(localized: "Grand format")
        case .relie: return String(localized: "Relié")
        case .numerique: return String(localized: "Numérique")
        case .audio: return String(localized: "Audio")
        }
    }
}

enum StatutParution: String, Codable, Sendable {
    case enCours, terminee, inconnue

    var libelle: String {
        switch self {
        case .enCours: return String(localized: "En cours de parution")
        case .terminee: return String(localized: "Terminée")
        case .inconnue: return String(localized: "Parution inconnue")
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
    /// Identité stable pour les futures sauvegardes cloud. Optionnelle afin
    /// que l'ajout reste une migration légère pour les bibliothèques existantes.
    var cloudID: UUID? = UUID()
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
    /// Résumé de l'édition dans la langue du lecteur (la quatrième de couverture qu'il lirait).
    var resumeLocal: String?
    var anneePublication: Int?
    var pages: Int?
    /// Couverture de repli globale, utilisée seulement sans édition plus précise.
    var couvertureCanoniqueURL: String?
    /// Couverture de l'édition dans la langue du lecteur (celle qu'il voit en librairie).
    var couvertureLocaleURL: String?
    var attributionCouverture: String?
    /// Évite de relancer tous les catalogues à chaque démarrage après une
    /// absence de résultat. Un changement de langue remet cette date à zéro.
    var dernierEssaiEditionLocale: Date?
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

    init(titreOriginal: String = "", auteurs: [String] = [], type: TypeOeuvre = .livre) {
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

    /// Couverture affichée : l'exemplaire réellement scanné d'abord, puis
    /// l'édition locale de la langue du lecteur, enfin le repli global.
    var couvertureAffichee: String? {
        exemplaire?.couverturePersonnelleURL
            ?? exemplaire?.couvertureEditionURL
            ?? couvertureLocaleURL
            ?? couvertureCanoniqueURL
    }

    var resumeAffiche: String? { resumeLocal ?? resume }

    /// Vrai si la requête correspond à l'un des titres connus (toutes langues,
    /// titre original, translittération) ou à un auteur.
    func correspond(_ requete: String) -> Bool {
        let champs = titres.values + [titreOriginal, titreRomaji].compactMap { $0 } + auteurs
        return TexteUtil.contient(champs, requete)
    }
}

// MARK: - Exemplaire (la relation de l'utilisateur à une œuvre)

@Model
final class Exemplaire {
    var cloudID: UUID? = UUID()
    var statutRaw: String = StatutLecture.aLire.rawValue
    var possede: Bool = true
    /// Note sur 10 (permet les demi-étoiles). nil = pas encore noté.
    var note: Int?
    var moods: [String] = []
    var pageCourante: Int = 0
    var formatRaw: String?
    var prixPaye: Double?
    var preteA: String?
    /// Depuis quand le livre est chez quelqu'un d'autre.
    var preteLe: Date?
    /// ISBN de l'édition réellement possédée.
    var isbn: String?
    var langueEdition: String?
    /// Couverture de l'édition réellement scannée, prioritaire à l'affichage.
    var couvertureEditionURL: String?
    /// Photo privée choisie par le lecteur, sans écraser la couverture
    /// officielle de l'édition scannée.
    var couverturePersonnelleURL: String?
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
        let etaitPossede = possede
        statut = nouveau
        possede = nouveau != .wishlist
        if !etaitPossede, possede, dateAchat == nil { dateAchat = Date() }
        if nouveau != .lu { dateFin = nil }
        switch nouveau {
        case .aLire:
            pageCourante = 0
            dateDebut = nil
        case .enCours where dateDebut == nil:
            dateDebut = Date()
        case .lu:
            if dateFin == nil { dateFin = Date() }
            if let pages = oeuvre?.pages { pageCourante = pages }
        case .wishlist:
            pageCourante = 0
            dateDebut = nil
            dateAchat = nil
            preteA = nil
            preteLe = nil
        case .abandonne, .enCours:
            break
        }
    }
}

// MARK: - Série (manga / BD / saga)

@Model
final class Serie {
    var cloudID: UUID? = UUID()
    var nom: String = ""
    /// Noms OFFICIELS par langue, même politique que les titres d'œuvres.
    var noms: [String: String] = [:]
    /// Alias officiels sans langue garantie (synonymes de catalogue). Ils
    /// relient notamment un titre traduit à son titre anglais ou japonais.
    var nomsAlternatifs: [String] = []
    /// Translittération latine (romaji), lisible sans connaître le script d'origine.
    var nomRomaji: String?
    var auteur: String?
    var typeRaw: String = TypeOeuvre.manga.rawValue
    var genres: [String] = []
    var resume: String?
    /// Résumé de l'édition locale (celui de la quatrième de couverture Kana, Glénat…).
    var resumeLocal: String?
    /// Couverture canonique globale de la série.
    var couvertureURL: String?
    var attributionCouverture: String?
    /// Couverture de l'édition locale (Kana, Glénat… pour un lecteur français).
    var couvertureLocaleURL: String?
    var dernierEssaiEditionLocale: Date?
    var tomesTotal: Int?
    var statutParutionRaw: String = StatutParution.inconnue.rawValue
    var chapitresLus: Int = 0
    var chapitresTotal: Int?
    var prochaineSortieNumero: Int?
    var prochaineSortieDate: Date?
    var rappelActive: Bool = false
    /// Identité persistante du rappel. Elle ne dépend ni du titre (modifiable
    /// et localisé), ni du numéro du prochain tome (qui change à chaque sortie).
    var identifiantRappelSortie: String?
    var idAniList: Int?
    var dateAjout: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \Tome.serie)
    var tomes: [Tome] = []

    @Relationship(deleteRule: .cascade, inverse: \SessionLecture.serie)
    var sessions: [SessionLecture] = []

    /// Collections personnelles auxquelles cette série appartient.
    var collections: [Collection] = []

    init(nom: String = "", type: TypeOeuvre = .manga) {
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

    /// Même logique que pour une œuvre : on cherche dans tous les noms connus.
    func correspond(_ requete: String) -> Bool {
        let champs = Array(noms.values) + nomsAlternatifs
            + [nom, nomRomaji, auteur].compactMap { $0 }
        return TexteUtil.contient(champs, requete)
    }

    var couvertureAffichee: String? {
        if let propre = couvertureLocaleURL ?? couvertureURL { return propre }
        // Une série créée depuis le scan du tome 2 n'a pas forcément une
        // image « série ». Sa première édition possédée est un meilleur
        // représentant que le placeholder, sans recopier ni fausser la donnée.
        return tomeCouvertureDeRepli?.couvertureAffichee
    }

    var attributionCouvertureAffichee: String? {
        if couvertureLocaleURL != nil || couvertureURL != nil {
            return attributionCouverture
        }
        guard let tome = tomeCouvertureDeRepli,
              tome.couverturePersonnelleURL == nil else { return nil }
        return tome.attributionCouverture
    }

    private var tomeCouvertureDeRepli: Tome? {
        tomesTries.first { $0.possede && $0.couvertureAffichee != nil }
            ?? tomesTries.first { $0.couvertureAffichee != nil }
    }

    /// Statut CHOISI par le lecteur, qui prime sur celui déduit des tomes.
    /// Sans lui, « abandonné » n'existait nulle part pour une série : le
    /// calcul ne peut pas deviner qu'on a décidé d'arrêter.
    var statutManuelRaw: String?
    /// Date civile du dernier choix. Une sortie annoncée après une déclaration
    /// « Lu » peut ainsi rouvrir automatiquement la série le jour venu.
    var statutManuelLe: Date?

    var statutChoisi: StatutLecture? {
        get {
            guard let choisi = statutManuelRaw.flatMap(StatutLecture.init(rawValue:))
            else { return nil }
            if choisi == .lu, let choisiLe = statutManuelLe {
                let nouvelleSortieNonLue = tomes.contains { tome in
                    guard !tome.lu, let sortie = tome.dateSortie else { return false }
                    return DateCivile.estDisponible(sortie)
                        && DateCivile.estApres(sortie, que: choisiLe)
                }
                if nouvelleSortieNonLue { return nil }
            }
            return choisi
        }
        set {
            statutManuelRaw = newValue?.rawValue
            statutManuelLe = newValue == nil ? nil : Date()
        }
    }

    /// Vrai dès que Honya a posé le rayon entier de cette série. Sert de
    /// preuve que tous les numéros annoncés par le catalogue sont présents.
    var rayonComplet: Bool = false
    /// Une passe d'enrichissement local a déjà abouti. Ce drapeau porte le
    /// quota Honya+ séparément de `rayonComplet` : trouver trois tomes d'une
    /// série en cours ne permet pas d'affirmer qu'il n'en existe que trois.
    var rayonEnrichi: Bool = false
    /// `true` si l'automatisation de ce rayon a été ouverte par Honya+.
    /// Les cases déjà créées restent après expiration, mais les futures
    /// ne sont plus matérialisées sauf si une place gratuite se libère.
    var rayonHonyaPlus: Bool = false
    /// Vrai quand le rayon a été demandé mais refusé faute d'abonnement :
    /// la fiche propose alors de l'ouvrir.
    var rayonRefuse: Bool = false

    var resumeAffiche: String? { resumeLocal ?? resume }

    var tomesTries: [Tome] { tomes.sorted { $0.numero < $1.numero } }
    var nbPossedes: Int { tomes.filter(\.possede).count }
    var nbLus: Int { tomes.filter(\.lu).count }

    var prochainAAcheter: Int? {
        tomesTries.first(where: { !$0.possede })?.numero
    }

    /// La série apparaît dans « En cours » si on a commencé sans finir.
    var lectureEnCours: Bool {
        (nbLus > 0 && !estTerminee) || (chapitresLus > 0)
    }

    /// Statut équivalent à celui d'un livre, déduit de l'état des tomes.
    /// C'est lui qui fait vivre les filtres de la bibliothèque pour les séries.
    var statut: StatutLecture {
        // Un choix explicitement affiché « Choisi par vous » est autoritaire.
        // Sans cela, sélectionner « À lire » ou « Liste d'envies » pouvait
        // laisser le libellé calculé « En cours », en contradiction directe
        // avec le menu que le lecteur venait d'utiliser.
        if let statutChoisi { return statutChoisi }
        if estTerminee { return .lu }
        if nbLus > 0 || chapitresLus > 0 { return .enCours }
        if nbPossedes > 0 { return .aLire }
        return .wishlist
    }

    /// Dernière activité de lecture, pour trier « en ce moment ».
    var derniereLecture: Date? {
        let dates = tomes.compactMap(\.dateLu) + sessions.map(\.debut)
        return dates.max()
    }

    /// Tome à lire ensuite : le premier possédé mais pas encore lu.
    var prochainALire: Tome? {
        tomesTries.first {
            $0.possede && !$0.lu
                && $0.dateSortie.map { DateCivile.estDisponible($0) } != false
        }
    }

    /// Tomes déjà en rayon — une date de sortie future est une précommande.
    var tomesParus: [Tome] {
        tomes.filter { $0.dateSortie.map { DateCivile.estDisponible($0) } != false }
    }

    /// Série terminée : tout ce qui est paru est lu. Un tome à paraître
    /// n'empêche pas de fêter — on ne peut pas lire l'avenir.
    var estTerminee: Bool {
        // Un drapeau historique ne suffit pas : sans total annoncé par une
        // source, trois résultats trouvés ne prouvent pas qu'il n'existe que
        // trois tomes. La structure doit couvrir exactement l'intervalle connu.
        guard let total = tomesTotal, total > 0 else { return false }
        let numeros = Set(tomes.map(\.numero))
        guard (1...total).allSatisfy({ numeros.contains($0) }) else { return false }
        let parus = tomesParus
        return !parus.isEmpty && parus.allSatisfy(\.lu)
    }
}

// MARK: - Tome

@Model
final class Tome {
    var cloudID: UUID? = UUID()
    /// À qui ce tome est prêté, et depuis quand. Un tome se prête comme un
    /// livre seul : c'est le même geste, il manquait sur les séries.
    var preteA: String?
    var preteLe: Date?
    /// Un tome qu'on a commencé puis laissé tomber.
    var abandonne: Bool = false

    var numero: Int = 1
    var possede: Bool = false
    var lu: Bool = false
    var dateLu: Date?
    var isbn: String?
    /// Chaque tome est un livre à part entière : son titre, sa couverture, ses pages.
    var titre: String?
    /// Couverture fournie par les catalogues pour cette édition.
    var couvertureURL: String?
    /// Photo privée choisie par le lecteur, prioritaire sans détruire l'URL
    /// officielle : la retirer restaure immédiatement la couverture catalogue.
    var couverturePersonnelleURL: String?
    var attributionCouverture: String?
    var pages: Int?
    /// Protège titre, pages et couverture saisis par le lecteur des purges de
    /// métadonnées dérivées lors d'un changement de langue ou d'une migration.
    var metadonneesManuelles: Bool = false
    /// Date de parution — future pour une précommande : le tome « à paraître ».
    var dateSortie: Date?

    var serie: Serie?

    var couvertureAffichee: String? { couverturePersonnelleURL ?? couvertureURL }

    init(numero: Int, possede: Bool = false, lu: Bool = false) {
        self.numero = numero
        self.possede = possede
        self.lu = lu
    }
}

// MARK: - Session de lecture

@Model
final class SessionLecture {
    var cloudID: UUID? = UUID()
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
        return String(localized: "Lecture")
    }
}

// MARK: - Citation

@Model
final class Citation {
    var cloudID: UUID? = UUID()
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
    var cloudID: UUID? = UUID()
    var minutesParJour: Int = 20
    var defiAnnuelLivres: Int = 26
    /// Langues de lecture préférées, codes ISO ("fr", "en"…). Pilote la recherche et l'affichage des titres.
    var languesLecture: [String] = []
    /// Types d'œuvres qui intéressent l'utilisateur (onboarding).
    var typesPreferes: [String] = [TypeOeuvre.livre.rawValue, TypeOeuvre.manga.rawValue]
    /// Emprunteurs récents, du plus récent au plus ancien. Le prêt actif
    /// reste porté par `Exemplaire` / `Tome` ; cette courte mémoire permet
    /// seulement de reproposer une personne après la restitution du livre.
    var emprunteursRecents: [String] = []

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
    var cloudID: UUID? = UUID()
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
        case .seriesIncompletes: return String(localized: "Séries incomplètes")
        case .coupsDeCoeur: return String(localized: "Coups de cœur")
        case .achetesCetteAnnee: return String(localized: "Achetés cette année")
        case .jamaisOuverts: return String(localized: "Jamais ouverts")
        case .pretes: return String(localized: "Prêtés")
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
        case .pretes:
            // Un tome se prête autant qu'un livre. Sans cette ligne,
            // l'étagère « Prêtés » restait vide alors que la fiche du tome
            // promettait de l'y retrouver.
            return toutes.filter { serie in serie.tomes.contains { $0.preteA != nil } }
        default:
            return []
        }
    }

    /// Les tomes prêtés d'une série, pour l'affichage du détail.
    static func tomesPretes(_ toutes: [Serie]) -> [Tome] {
        toutes.flatMap { $0.tomes }.filter { $0.preteA != nil }
    }
}

// MARK: - Badge gagné

@Model
final class BadgeGagne {
    var cloudID: UUID? = UUID()
    var typeRaw: String = ""
    var date: Date = Date()

    init(typeRaw: String) {
        self.typeRaw = typeRaw
    }
}

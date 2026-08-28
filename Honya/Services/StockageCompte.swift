import Foundation
import Observation
import SwiftData

/// Isole strictement la bibliotheque locale par UUID Supabase.
///
/// Le conteneur en memoire est le seul disponible avant la connexion. Une vue
/// d'authentification ne peut donc jamais interroger, meme brièvement, le store
/// du compte qui vient de se deconnecter.
@MainActor
@Observable
final class StockageCompte {
    static let partage = StockageCompte()
    private static let clePurgesDifferees = "stockageComptePurgesDiffereesV1"

    enum TypeStoreSuppression: String {
        case legacy, dedicated
    }

    static let schema = Schema([
        Oeuvre.self, Exemplaire.self,
        Serie.self, Tome.self,
        SessionLecture.self, Citation.self,
        Objectif.self, BadgeGagne.self, Collection.self,
    ])

    let conteneurBootstrap: ModelContainer
    private(set) var conteneurActif: ModelContainer?
    private(set) var identifiantActif: UUID?
    private(set) var generation = 0
    private(set) var erreur: String?
    private(set) var revendicationLegacyEnAttente = false
    private(set) var identifiantRevendication: UUID?
    private(set) var preferencesActives: UserDefaults?

    /// Dossier autorise pour les photos du compte monte. Il reste disponible
    /// pendant la phase locale d'une suppression, meme apres l'oubli des
    /// identifiants de session par `Compte`.
    private(set) var dossierCouverturesActif: URL?
    private(set) var accepteReferencesCouverturesLegacy = false

    /// Capture durable du store effectivement monte, avant tout appel distant
    /// de suppression. Elle permet une reprise sans relire le sidecar legacy.
    var typeStoreActifPourSuppression: TypeStoreSuppression? {
        guard identifiantActif != nil, conteneurActif != nil else { return nil }
        return accepteReferencesCouverturesLegacy ? .legacy : .dedicated
    }

    private let fichiers = FileManager.default
    private let racineSupport: URL
    private let racineStockage: URL
    private let fichierProprietaireLegacy: URL
    private let urlStoreLegacy: URL

    private init() {
        guard let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            fatalError("Dossier Application Support indisponible.")
        }
        racineSupport = support
        racineStockage = support.appendingPathComponent("HonyaStorage", isDirectory: true)
        fichierProprietaireLegacy = racineStockage
            .appendingPathComponent("legacy-owner-v1", isDirectory: false)

        // C'est exactement l'URL qu'utilisaient les versions precedentes avec
        // `ModelConfiguration(schema:)`. On la garde sur place : copier un
        // store sans ses fichiers WAL/SHM pourrait perdre des donnees.
        urlStoreLegacy = ModelConfiguration(schema: Self.schema).url

        let configuration = ModelConfiguration(
            "bootstrap",
            schema: Self.schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        do {
            conteneurBootstrap = try ModelContainer(
                for: Self.schema,
                configurations: [configuration]
            )
        } catch {
            fatalError("Impossible de creer le stockage temporaire Honya : \(error)")
        }

        // Aucun ModelContainer disque n'est ouvert : les fichiers marques
        // apres une suppression precedente peuvent etre retires sans toucher
        // un SQLite encore utilise par SwiftData.
        purgerSuppressionsDifferees()
    }

    /// Monte le store du compte. La premiere revendication du store historique
    /// exige une session que Supabase vient de verifier ; une association deja
    /// ecrite peut, elle, etre rouverte hors ligne.
    @discardableResult
    func activer(
        identifiantServeur: String,
        sessionVerifiee: Bool
    ) -> Bool {
        do {
            let identifiant = try uuidValide(identifiantServeur)
            if identifiantActif == identifiant, conteneurActif != nil {
                erreur = nil
                return true
            }

            let urlDediee = urlDossierCompte(identifiant)
                .appendingPathComponent("Honya.store", isDirectory: false)
            let compteDedieDejaInitialise = fichiers.fileExists(atPath: urlDediee.path)
                || UserDefaults.standard.bool(forKey: cleRefusLegacy(identifiant))

            // Un compte deja dedie n'a aucun besoin de lire le sidecar legacy.
            // Sa corruption ne doit pas rendre une bibliotheque saine inaccessible.
            if compteDedieDejaInitialise {
                try ouvrirStore(pour: identifiant, forcerDedie: true)
                return true
            }
            let proprietaire = try proprietaireLegacy()
            if proprietaire == nil, !sessionVerifiee {
                // Pas une erreur : le rafraichissement de session en cours
                // rappellera cette methode des qu'il aura abouti.
                return false
            }
            if proprietaire == nil {
                if storeLegacyExiste {
                    // L'ancien store global a pu etre utilise par plusieurs
                    // comptes. Le montrer au premier UUID venu recreerait la
                    // fuite que cette couche supprime : seul le lecteur peut
                    // decider a quel compte il appartient.
                    identifiantRevendication = identifiant
                    revendicationLegacyEnAttente = true
                    erreur = nil
                    return false
                }
                try revendiquerStoreLegacy(par: identifiant)
            }
            try ouvrirStore(pour: identifiant)
            return true
        } catch {
            self.erreur = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func confirmerRevendicationLegacy() -> Bool {
        guard let identifiant = identifiantRevendication else { return false }
        do {
            try revendiquerStoreLegacy(par: identifiant)
            revendicationLegacyEnAttente = false
            identifiantRevendication = nil
            try ouvrirStore(pour: identifiant)
            return true
        } catch {
            self.erreur = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func refuserRevendicationLegacy() -> Bool {
        guard let identifiant = identifiantRevendication else { return false }
        UserDefaults.standard.set(true, forKey: cleRefusLegacy(identifiant))
        do {
            revendicationLegacyEnAttente = false
            identifiantRevendication = nil
            try ouvrirStore(pour: identifiant, forcerDedie: true)
            return true
        } catch {
            self.erreur = error.localizedDescription
            return false
        }
    }

    /// Une suppression interrompue doit retrouver exactement le store de sa
    /// cible, y compris apres que les jetons ont ete oublies. La cible provient
    /// de l'intention durable ecrite avant l'appel serveur.
    @discardableResult
    func activerPourSuppression(
        identifiantServeur: String?,
        typeStockage: TypeStoreSuppression?
    ) -> Bool {
        do {
            if let identifiantServeur, !identifiantServeur.isEmpty {
                let identifiant = try uuidValide(identifiantServeur)
                switch typeStockage {
                case .legacy:
                    // Ce type a ete capture pendant que ce store exact etait
                    // monte, avant le POST de suppression distant.
                    try ouvrir(
                        identifiant: identifiant,
                        url: urlStoreLegacy,
                        dossierCouvertures: racineSupport
                            .appendingPathComponent("Couvertures", isDirectory: true),
                        accepteLegacy: true
                    )
                case .dedicated:
                    try ouvrirStore(pour: identifiant, forcerDedie: true)
                case nil:
                    // Migration d'une intention ecrite avant la capture du
                    // type. Le chemin dedie reste independant du sidecar.
                    let urlDediee = urlDossierCompte(identifiant)
                        .appendingPathComponent("Honya.store", isDirectory: false)
                    let avaitChoisiUnStoreDedie = fichiers.fileExists(atPath: urlDediee.path)
                        || UserDefaults.standard.bool(forKey: cleRefusLegacy(identifiant))
                    if !avaitChoisiUnStoreDedie,
                       try proprietaireLegacy() == nil {
                        try revendiquerStoreLegacy(par: identifiant)
                    }
                    try ouvrirStore(
                        pour: identifiant,
                        forcerDedie: avaitChoisiUnStoreDedie
                    )
                }
            } else {
                // Migration d'une tres ancienne phase de nettoyage local, qui
                // ne persistait pas encore l'UUID Supabase.
                try ouvrir(
                    identifiant: nil,
                    url: urlStoreLegacy,
                    dossierCouvertures: racineSupport
                        .appendingPathComponent("Couvertures", isDirectory: true),
                    accepteLegacy: true
                )
            }
            return true
        } catch {
            self.erreur = error.localizedDescription
            return false
        }
    }

    func desactiver() {
        SauvegardeCloud.partage.desactiver()
        conteneurActif = nil
        identifiantActif = nil
        preferencesActives = nil
        preferencesActivesSuite = nil
        CompteurScans.partage.activer(preferences: nil)
        dossierCouverturesActif = nil
        accepteReferencesCouverturesLegacy = false
        revendicationLegacyEnAttente = false
        identifiantRevendication = nil
        erreur = nil
        generation &+= 1
        Task { await ImageCharge.partage.vider() }
    }

    /// Force la recreation des `@Query` apres une restauration atomique. Le
    /// conteneur reste identique, mais aucune vue ne conserve une selection
    /// ou un modele provenant de la revision remplacee.
    func signalerRemplacementDesDonnees() {
        guard conteneurActif != nil else { return }
        generation &+= 1
        Task { await ImageCharge.partage.vider() }
    }

    func effacerErreur() {
        erreur = nil
    }

    func effacerPreferencesActives() {
        guard let preferencesActives,
              let domaine = preferencesActivesSuite else { return }
        preferencesActives.removePersistentDomain(forName: domaine)
    }

    /// Le store ne peut pas etre supprime pendant que le contexte appelant de
    /// la suppression le retient encore. On enregistre donc sa cible, puis le
    /// prochain lancement la purge avant toute ouverture disque.
    func programmerPurgeApresSuppression() {
        guard let identifiantActif else { return }
        var valeurs = UserDefaults.standard.stringArray(
            forKey: Self.clePurgesDifferees
        ) ?? []
        let texte = identifiantActif.uuidString.lowercased()
        // Le type du store est connu tant qu'il est encore monte. Le persister
        // permet au prochain lancement de supprimer un legacy dont le sidecar
        // serait devenu illisible, sans jamais deviner a quel compte il etait.
        let type = typeStoreActifPourSuppression ?? .dedicated
        let cible = texte + "|" + type.rawValue
        valeurs.removeAll { $0 == texte || $0.hasPrefix(texte + "|") }
        valeurs.append(cible)
        UserDefaults.standard.set(valeurs, forKey: Self.clePurgesDifferees)
    }

    // MARK: - Choix immuable du store

    private func ouvrirStore(
        pour identifiant: UUID,
        forcerDedie: Bool = false
    ) throws {
        let proprietaire = forcerDedie ? nil : try proprietaireLegacy()
        let estProprietaireLegacy = !forcerDedie && proprietaire == identifiant
        let url: URL
        let dossierCouvertures: URL

        if estProprietaireLegacy {
            url = urlStoreLegacy
            dossierCouvertures = racineSupport
                .appendingPathComponent("Couvertures", isDirectory: true)
        } else {
            let dossierCompte = urlDossierCompte(identifiant)
            try fichiers.createDirectory(
                at: dossierCompte,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            )
            url = dossierCompte.appendingPathComponent("Honya.store", isDirectory: false)
            dossierCouvertures = dossierCompte
                .appendingPathComponent("Couvertures", isDirectory: true)
        }

        try ouvrir(
            identifiant: identifiant,
            url: url,
            dossierCouvertures: dossierCouvertures,
            accepteLegacy: estProprietaireLegacy
        )
    }

    private func ouvrir(
        identifiant: UUID?,
        url: URL,
        dossierCouvertures: URL,
        accepteLegacy: Bool
    ) throws {
        if identifiantActif == identifiant, conteneurActif != nil { return }

        let configuration = ModelConfiguration(
            identifiant.map { "compte-\($0.uuidString.lowercased())" } ?? "legacy-suppression",
            schema: Self.schema,
            url: url,
            cloudKitDatabase: .none
        )
        let nouveau = try ModelContainer(
            for: Self.schema,
            configurations: [configuration]
        )

        // Le nouveau conteneur est entierement ouvert avant de remplacer
        // l'ancien. Aucune vue ne voit un etat intermediaire.
        conteneurActif = nouveau
        identifiantActif = identifiant
        if let identifiant {
            let suite = nomSuitePreferences(identifiant)
            preferencesActives = UserDefaults(suiteName: suite)
            preferencesActivesSuite = suite
            if accepteLegacy, let preferencesActives {
                migrerPreferencesLegacy(vers: preferencesActives)
            }
        } else {
            preferencesActives = nil
            preferencesActivesSuite = nil
        }
        dossierCouverturesActif = dossierCouvertures
        accepteReferencesCouverturesLegacy = accepteLegacy
        CompteurScans.partage.activer(preferences: preferencesActives)
        erreur = nil
        generation &+= 1
        Task { await ImageCharge.partage.vider() }
    }

    private func proprietaireLegacy() throws -> UUID? {
        guard fichiers.fileExists(atPath: fichierProprietaireLegacy.path) else {
            return nil
        }
        let donnees = try Data(contentsOf: fichierProprietaireLegacy)
        guard let texte = String(data: donnees, encoding: .utf8)?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), let uuid = UUID(uuidString: texte) else {
            throw Erreur.proprietaireLegacyCorrompu
        }
        return uuid
    }

    private func purgerSuppressionsDifferees() {
        let defaults = UserDefaults.standard
        let valeurs = defaults.stringArray(forKey: Self.clePurgesDifferees) ?? []
        guard !valeurs.isEmpty else { return }
        var aConserver: [String] = []

        for texte in valeurs {
            let morceaux = texte.split(separator: "|", maxSplits: 1).map(String.init)
            guard let premier = morceaux.first,
                  let identifiant = UUID(uuidString: premier) else { continue }
            let type = morceaux.count == 2 ? morceaux[1] : nil
            do {
                // La copie dediee et ses preferences sont independantes du
                // sidecar : elles sont toujours purgees en premier.
                let dossierDedie = urlDossierCompte(identifiant)
                if fichiers.fileExists(atPath: dossierDedie.path) {
                    try fichiers.removeItem(at: dossierDedie)
                }
                let suite = nomSuitePreferences(identifiant)
                UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
                defaults.removeObject(forKey: cleRefusLegacy(identifiant))

                switch type {
                case "legacy":
                    try supprimerStoreLegacyEtSidecar()
                case "dedicated":
                    break
                default:
                    // Compatibilite avec une intention ecrite par une version
                    // precedente, avant que le type du store soit persiste.
                    if try proprietaireLegacy() == identifiant {
                        try supprimerStoreLegacyEtSidecar()
                    }
                }
            } catch {
                // Une protection de fichiers encore verrouillee au demarrage
                // sera retentee au lancement suivant.
                aConserver.append(texte)
            }
        }

        if aConserver.isEmpty {
            defaults.removeObject(forKey: Self.clePurgesDifferees)
        } else {
            defaults.set(aConserver, forKey: Self.clePurgesDifferees)
        }
    }

    private func supprimerStoreLegacyEtSidecar() throws {
        let chemins = [
            urlStoreLegacy,
            URL(fileURLWithPath: urlStoreLegacy.path + "-wal"),
            URL(fileURLWithPath: urlStoreLegacy.path + "-shm"),
            racineSupport.appendingPathComponent("Couvertures", isDirectory: true),
            fichierProprietaireLegacy,
        ]
        for chemin in chemins where fichiers.fileExists(atPath: chemin.path) {
            try fichiers.removeItem(at: chemin)
        }
    }

    private func revendiquerStoreLegacy(par identifiant: UUID) throws {
        try fichiers.createDirectory(
            at: racineStockage,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        // Ecrit avant l'ouverture du store. Meme si cette ouverture echoue,
        // une autre identite ne pourra jamais revendiquer les anciennes donnees.
        try Data((identifiant.uuidString.lowercased() + "\n").utf8).write(
            to: fichierProprietaireLegacy,
            options: [.atomic, .completeFileProtection]
        )
    }

    private var storeLegacyExiste: Bool {
        let chemins = [
            urlStoreLegacy,
            URL(fileURLWithPath: urlStoreLegacy.path + "-wal"),
            URL(fileURLWithPath: urlStoreLegacy.path + "-shm"),
        ]
        return chemins.contains { fichiers.fileExists(atPath: $0.path) }
    }

    private func urlDossierCompte(_ identifiant: UUID) -> URL {
        racineStockage
            .appendingPathComponent("Comptes", isDirectory: true)
            .appendingPathComponent(identifiant.uuidString.lowercased(), isDirectory: true)
    }

    private func cleRefusLegacy(_ identifiant: UUID) -> String {
        "legacy-store-decline-v1-" + identifiant.uuidString.lowercased()
    }

    private var preferencesActivesSuite: String?

    private func nomSuitePreferences(_ identifiant: UUID) -> String {
        "app.honya.compte." + identifiant.uuidString.lowercased()
    }

    private func migrerPreferencesLegacy(vers destination: UserDefaults) {
        let marqueur = "preferencesLegacyMigreesV1"
        guard !destination.bool(forKey: marqueur) else { return }
        let cles = [
            "onboardingTermine", "editionsLocalesV10", "catalogueCompletV11",
            "editionsVerifieesV49", "langueEditionsV1", "provenanceTomesV1",
            "roueUtilisee", "remiseGagnee", "murAccueil", "scansUtilises",
        ]
        for cle in cles {
            if let valeur = UserDefaults.standard.object(forKey: cle) {
                destination.set(valeur, forKey: cle)
            }
        }
        destination.set(true, forKey: marqueur)
    }

    private func uuidValide(_ texte: String) throws -> UUID {
        guard let uuid = UUID(uuidString: texte.trimmingCharacters(in: .whitespacesAndNewlines))
        else { throw Erreur.identifiantCompteInvalide }
        return uuid
    }

    private enum Erreur: LocalizedError {
        case identifiantCompteInvalide
        case proprietaireLegacyCorrompu

        var errorDescription: String? {
            switch self {
            case .identifiantCompteInvalide:
                return String(localized: "Réponse inattendue du serveur.")
            case .proprietaireLegacyCorrompu:
                return String(localized: "Le stockage local ne peut pas être ouvert en toute sécurité.")
            }
        }
    }
}

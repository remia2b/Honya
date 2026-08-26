import AuthenticationServices
import CryptoKit
import SwiftData
import SwiftUI

/// Le compte Honya. Deux chemins, un seul compte : l'identifiant Apple (rien
/// à retenir) ou une adresse e-mail et un mot de passe. Et toujours la
/// possibilité de se servir de Honya sans compte du tout.
@Observable
@MainActor
final class Compte {
    static let partage = Compte()

    enum Etat: Equatable {
        /// Aucun compte : l'écran de bienvenue, et rien d'autre.
        case indetermine
        case connecte
    }

    enum Methode: String {
        case apple, email
    }

    private(set) var etat: Etat = .indetermine
    private(set) var identifiant: String?
    private(set) var nom: String?
    private(set) var email: String?
    private(set) var methode: Methode = .apple

    /// Nonce de la demande Apple en cours, pour l'échange avec Supabase.
    private var nonceEnCours: String?

    private let defaults = UserDefaults.standard
    private enum Cle {
        static let etat = "compteEtat"
        static let identifiant = "compteIdentifiant"
        static let nom = "compteNom"
        static let email = "compteEmail"
        static let methode = "compteMethode"
        static let jetonAcces = "jetonAcces"
        static let jetonRenouvellement = "jetonRenouvellement"
    }

    private init() {
        identifiant = defaults.string(forKey: Cle.identifiant)
        nom = defaults.string(forKey: Cle.nom)
        email = defaults.string(forKey: Cle.email)
        methode = Methode(rawValue: defaults.string(forKey: Cle.methode) ?? "") ?? .apple
        // Un « invite » enregistré par une version précédente retombe ici
        // sur .indetermine : sans cela, un appareil qui avait choisi de se
        // passer de compte ne reverrait jamais l'écran de bienvenue.
        switch defaults.string(forKey: Cle.etat) {
        case "connecte" where identifiant != nil: etat = .connecte
        default:
            etat = .indetermine
            defaults.removeObject(forKey: Cle.etat)
        }
    }

    var nomAffiche: String {
        if let nom, !nom.isEmpty { return nom }
        if let email, !email.isEmpty { return email }
        return methode == .apple
            ? String(localized: "Compte Apple")
            : String(localized: "Compte Honya")
    }

    var libelleMethode: String {
        methode == .apple
            ? String(localized: "Connexion avec Apple")
            : String(localized: "Adresse e-mail")
    }

    // MARK: - Apple

    /// Prépare la demande Apple : le nonce lie la réponse à cette demande
    /// précise, et permet à Supabase de vérifier le jeton d'identité.
    func preparerDemandeApple(_ requete: ASAuthorizationAppleIDRequest) {
        let brut = Self.nonceAleatoire()
        nonceEnCours = brut
        requete.requestedScopes = [.fullName, .email]
        requete.nonce = Self.empreinte(brut)
    }

    func connecterAvecApple(_ credential: ASAuthorizationAppleIDCredential) async {
        identifiant = credential.user
        methode = .apple
        // Apple ne transmet le nom et l'adresse qu'à la toute première
        // autorisation : on les garde précieusement, sinon ils sont perdus.
        if let complet = credential.fullName {
            let assemble = [complet.givenName, complet.familyName]
                .compactMap { $0 }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
            if !assemble.isEmpty { nom = assemble }
        }
        if let adresse = credential.email, !adresse.isEmpty { email = adresse }

        // Si le serveur est configuré, la session Apple devient une session
        // Honya : les deux chemins mènent au même compte.
        if SupabaseAuth.configure,
           let jeton = credential.identityToken,
           let texte = String(data: jeton, encoding: .utf8) {
            if let session = try? await SupabaseAuth.connecterAvecApple(
                jetonIdentite: texte,
                nonce: nonceEnCours
            ) {
                enregistrer(session)
            }
        }
        nonceEnCours = nil
        finaliserConnexion()
    }

    // MARK: - Adresse e-mail

    /// Renvoie un message à afficher quand la confirmation par courrier est
    /// exigée : dans ce cas il n'y a pas encore de session.
    func inscrire(email adresse: String, motDePasse: String) async throws -> String? {
        let session = try await SupabaseAuth.inscrire(email: adresse, motDePasse: motDePasse)
        guard let session else {
            return String(localized: "Compte créé. Ouvrez le courrier de confirmation, puis connectez-vous.")
        }
        adopter(session, adresse: adresse)
        return nil
    }

    /// L'adresse vient d'être confirmée depuis le lien du courrier. Vaut le
    /// temps d'un message : le lecteur a quitté l'application pour sa boîte
    /// aux lettres, il doit savoir en revenant que c'est allé au bout.
    private(set) var adresseVientDEtreConfirmee = false

    /// Et si le lien n'a pas abouti, on le dit aussi. Revenir de sa boîte aux
    /// lettres devant un écran qui n'a pas bougé est la pire des réponses :
    /// on ne sait pas si l'on doit recommencer, attendre, ou s'inquiéter.
    private(set) var soucisDeConfirmation: String?

    func accuserConfirmation() {
        adresseVientDEtreConfirmee = false
        soucisDeConfirmation = nil
    }

    /// Confirme l'adresse depuis le lien du courrier, et connecte.
    ///
    /// - Returns: vrai si la confirmation a abouti.
    @discardableResult
    func confirmerDepuisLien(_ url: URL) async -> Bool {
        guard let composants = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let elements = composants.queryItems,
              let jeton = elements.first(where: { $0.name == "token_hash" })?.value,
              !jeton.isEmpty
        else {
            // « honya:// » sans jeton : quelqu'un revient depuis la page de
            // confirmation du site, où la vérification a déjà eu lieu. Rien
            // à vérifier ici, mais le message vert lui est dû.
            if url.scheme == "honya", url.host == "confirme" {
                adresseVientDEtreConfirmee = true
                return true
            }
            return false
        }

        let type = elements.first(where: { $0.name == "type" })?.value ?? "signup"
        soucisDeConfirmation = nil
        do {
            let session = try await SupabaseAuth.confirmerAvecJeton(jeton, type: type)
            adopter(session, adresse: session.user?.email ?? email ?? "")
            adresseVientDEtreConfirmee = true
            return true
        } catch {
            // Un lien périmé, déjà utilisé, ou un réseau absent. Dans tous les
            // cas le lecteur doit savoir quoi faire — et il peut toujours
            // refaire partir un courrier.
            soucisDeConfirmation = error.localizedDescription
            return false
        }
    }

    /// Fait repartir le courrier de confirmation vers cette adresse.
    func renvoyerConfirmation(email adresse: String) async throws {
        try await SupabaseAuth.renvoyerConfirmation(email: adresse)
    }

    func connecter(email adresse: String, motDePasse: String) async throws {
        let session = try await SupabaseAuth.connecter(email: adresse, motDePasse: motDePasse)
        adopter(session, adresse: adresse)
    }

    func envoyerReinitialisation(email adresse: String) async throws {
        try await SupabaseAuth.reinitialiserMotDePasse(email: adresse)
    }

    /// La session ouverte par le code, en attente du nouveau mot de passe.
    private var sessionRecuperation: SupabaseAuth.Session?

    /// Première marche du mot de passe oublié : le code vaut preuve. Le
    /// vérifier tout de suite donne un retour immédiat — un code faux se
    /// voit ici, pas après avoir choisi un mot de passe pour rien.
    func verifierCode(email adresse: String, code: String) async throws {
        sessionRecuperation = try await SupabaseAuth.verifierCodeRecuperation(
            email: adresse, code: code
        )
    }

    /// Seconde marche : le nouveau mot de passe est posé et le lecteur entre
    /// dans la foulée — lui redemander de se connecter serait absurde.
    func poserNouveauMotDePasse(_ nouveau: String, email adresse: String) async throws {
        guard let session = sessionRecuperation else {
            throw SupabaseAuth.Souci.message(
                String(localized: "Recommencez : le code n'a pas été vérifié.")
            )
        }
        try await SupabaseAuth.changerMotDePasse(nouveau, jeton: session.access_token)
        adopter(session, adresse: adresse)
        sessionRecuperation = nil
    }

    private func adopter(_ session: SupabaseAuth.Session, adresse: String) {
        identifiant = session.user?.id ?? adresse
        email = session.user?.email ?? adresse
        methode = .email
        enregistrer(session)
        finaliserConnexion()
    }

    // MARK: - Session

    private func enregistrer(_ session: SupabaseAuth.Session) {
        Trousseau.ecrire(session.access_token, cle: Cle.jetonAcces)
        Trousseau.ecrire(session.refresh_token, cle: Cle.jetonRenouvellement)
    }

    private func finaliserConnexion() {
        defaults.set(identifiant, forKey: Cle.identifiant)
        defaults.set(nom, forKey: Cle.nom)
        defaults.set(email, forKey: Cle.email)
        defaults.set(methode.rawValue, forKey: Cle.methode)
        defaults.set("connecte", forKey: Cle.etat)
        etat = .connecte
    }

    func seDeconnecter() {
        if let jeton = Trousseau.lire(Cle.jetonAcces) {
            Task { await SupabaseAuth.deconnecter(jeton: jeton) }
        }
        oublier()
        // Retour à la bienvenue, pas à un mode invité : la bibliothèque reste
        // sur l'appareil, mais l'application redemande un compte.
        defaults.removeObject(forKey: Cle.etat)
        etat = .indetermine
    }

    /// Au lancement : une révocation depuis les Réglages d'iOS doit se voir,
    /// et la session serveur se renouvelle en silence.
    func verifierSession() async {
        guard etat == .connecte else { return }

        if methode == .apple, let identifiant {
            let statut = try? await ASAuthorizationAppleIDProvider()
                .credentialState(forUserID: identifiant)
            if statut == .revoked || statut == .notFound {
                seDeconnecter()
                return
            }
        }
        if SupabaseAuth.configure, let renouvellement = Trousseau.lire(Cle.jetonRenouvellement) {
            if let session = try? await SupabaseAuth.rafraichir(jeton: renouvellement) {
                enregistrer(session)
            }
        }
    }

    // MARK: - Suppression du compte

    /// Efface le compte côté serveur quand il y en a un, puis tout ce que
    /// Honya sait du lecteur sur l'appareil.
    func supprimerCompte(dans contexte: ModelContext) async {
        if SupabaseAuth.configure, let jeton = Trousseau.lire(Cle.jetonAcces) {
            try? await SupabaseAuth.supprimerCompte(jeton: jeton)
        }
        effacerDonnees(dans: contexte)
        oublier()
        for cle in ["compteEtat", "onboardingTermine", "editionsLocalesV10", "catalogueCompletV11"] {
            defaults.removeObject(forKey: cle)
        }
        etat = .indetermine
    }

    private func effacerDonnees(dans contexte: ModelContext) {
        try? contexte.delete(model: Oeuvre.self)
        try? contexte.delete(model: Exemplaire.self)
        try? contexte.delete(model: Serie.self)
        try? contexte.delete(model: Tome.self)
        try? contexte.delete(model: SessionLecture.self)
        try? contexte.delete(model: Citation.self)
        try? contexte.delete(model: BadgeGagne.self)
        try? contexte.delete(model: Collection.self)
        try? contexte.delete(model: Objectif.self)
        try? contexte.save()
    }

    private func oublier() {
        identifiant = nil
        nom = nil
        email = nil
        defaults.removeObject(forKey: Cle.identifiant)
        defaults.removeObject(forKey: Cle.nom)
        defaults.removeObject(forKey: Cle.email)
        defaults.removeObject(forKey: Cle.methode)
        Trousseau.effacer(Cle.jetonAcces)
        Trousseau.effacer(Cle.jetonRenouvellement)
    }

    // MARK: - Nonce

    private static func nonceAleatoire(longueur: Int = 32) -> String {
        let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var octets = [UInt8](repeating: 0, count: longueur)
        _ = SecRandomCopyBytes(kSecRandomDefault, longueur, &octets)
        return String(octets.map { alphabet[Int($0) % alphabet.count] })
    }

    private static func empreinte(_ texte: String) -> String {
        SHA256.hash(data: Data(texte.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

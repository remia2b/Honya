import AuthenticationServices
import SwiftData
import SwiftUI

/// Le compte Honya, c'est l'identifiant Apple du lecteur : rien à retenir,
/// aucun mot de passe à confier, et le nom comme l'adresse ne quittent jamais
/// l'appareil. On garde aussi la porte ouverte : on peut se servir de Honya
/// sans compte du tout.
@Observable
@MainActor
final class Compte {
    static let partage = Compte()

    enum Etat: Equatable {
        /// Premier lancement : l'écran de bienvenue décide.
        case indetermine
        /// Le lecteur a choisi de rester sans compte.
        case invite
        case connecte
    }

    private(set) var etat: Etat = .indetermine
    private(set) var identifiant: String?
    private(set) var nom: String?
    private(set) var email: String?

    private let defaults = UserDefaults.standard
    private enum Cle {
        static let etat = "compteEtat"
        static let identifiant = "compteIdentifiant"
        static let nom = "compteNom"
        static let email = "compteEmail"
    }

    private init() {
        identifiant = defaults.string(forKey: Cle.identifiant)
        nom = defaults.string(forKey: Cle.nom)
        email = defaults.string(forKey: Cle.email)
        switch defaults.string(forKey: Cle.etat) {
        case "connecte" where identifiant != nil: etat = .connecte
        case "invite": etat = .invite
        default: etat = .indetermine
        }
    }

    /// Nom affiché dans les réglages — le prénom suffit, sinon l'adresse.
    var nomAffiche: String {
        if let nom, !nom.isEmpty { return nom }
        if let email, !email.isEmpty { return email }
        return "Compte Apple"
    }

    // MARK: - Connexion

    func connecter(_ credential: ASAuthorizationAppleIDCredential) {
        identifiant = credential.user
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

        defaults.set(identifiant, forKey: Cle.identifiant)
        defaults.set(nom, forKey: Cle.nom)
        defaults.set(email, forKey: Cle.email)
        defaults.set("connecte", forKey: Cle.etat)
        etat = .connecte
    }

    func continuerSansCompte() {
        defaults.set("invite", forKey: Cle.etat)
        etat = .invite
    }

    func seDeconnecter() {
        oublier()
        defaults.set("invite", forKey: Cle.etat)
        etat = .invite
    }

    /// Rouvre l'écran de bienvenue sans rien effacer : le lecteur sans compte
    /// qui veut finalement s'en créer un garde évidemment sa bibliothèque.
    func revoirLaBienvenue() {
        defaults.removeObject(forKey: Cle.etat)
        etat = .indetermine
    }

    /// Vérifie au lancement que l'identifiant Apple est toujours valable :
    /// si le lecteur a révoqué Honya depuis les Réglages d'iOS, on le sait.
    func verifierSession() async {
        guard etat == .connecte, let identifiant else { return }
        let fournisseur = ASAuthorizationAppleIDProvider()
        let statut = try? await fournisseur.credentialState(forUserID: identifiant)
        if statut == .revoked || statut == .notFound {
            seDeconnecter()
        }
    }

    // MARK: - Suppression du compte

    /// Efface le compte ET tout ce que Honya sait du lecteur : la
    /// bibliothèque, les sessions, les badges, les étagères, les réglages.
    func supprimerCompte(dans contexte: ModelContext) {
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

        oublier()
        for cle in ["compteEtat", "onboardingTermine", "editionsLocalesV10", "catalogueCompletV11"] {
            defaults.removeObject(forKey: cle)
        }
        etat = .indetermine
    }

    private func oublier() {
        identifiant = nil
        nom = nil
        email = nil
        defaults.removeObject(forKey: Cle.identifiant)
        defaults.removeObject(forKey: Cle.nom)
        defaults.removeObject(forKey: Cle.email)
    }
}

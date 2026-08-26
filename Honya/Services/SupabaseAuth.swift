import Foundation

/// L'authentification Supabase en REST pur — aucune dépendance à greffer dans
/// le projet Xcode. On ne parle qu'à l'API GoTrue du projet Honya (un projet
/// Supabase distinct de tout autre : base, utilisateurs et clés séparés).
enum SupabaseAuth {

    struct Session: Codable {
        let access_token: String
        let refresh_token: String
        let expires_at: Double?
        let user: Utilisateur?
    }

    struct Utilisateur: Codable {
        let id: String
        let email: String?
    }

    enum Souci: LocalizedError {
        case nonConfigure
        /// Le compte existe mais son adresse n'a jamais été confirmée. Un cas
        /// à part : c'est le seul dont on sort en renvoyant un courrier.
        case adresseNonConfirmee
        case message(String)

        var errorDescription: String? {
            switch self {
            case .nonConfigure:
                return String(localized: "Les comptes par adresse e-mail ne sont pas encore configurés dans cette version.")
            case .adresseNonConfirmee:
                return String(localized: "Confirmez d'abord votre adresse : un courrier vous attend.")
            case .message(let texte):
                return texte
            }
        }
    }

    static var configure: Bool {
        !Secrets.supabaseURL.isEmpty && !Secrets.supabaseCleAnon.isEmpty
    }

    // MARK: - Créer un compte, se connecter

    /// Inscription par adresse e-mail. Si le projet demande la confirmation
    /// par courrier, aucune session n'est renvoyée : on le dit clairement.
    /// Où atterrit le lecteur après avoir confirmé son adresse.
    ///
    /// Dit explicitement à chaque envoi plutôt que laissé au réglage du
    /// projet : sans lui, GoTrue retombe sur son « Site URL » par défaut —
    /// localhost:3000 — et le lien du courrier ouvre une page morte alors
    /// que la confirmation, elle, a réussi.
    private static var retourConfirmation: String {
        // Le site parle deux langues ; on renvoie le lecteur dans la sienne.
        let langue = Langues.codeAppareil.hasPrefix("fr") ? "fr" : "en"
        return "https://www.honya.app/" + langue + "/confirme/"
    }

    static func inscrire(email: String, motDePasse: String) async throws -> Session? {
        let reponse: Session = try await appeler(
            "/auth/v1/signup?redirect_to=" + chiffrer(retourConfirmation),
            corps: ["email": email, "password": motDePasse]
        )
        return reponse.access_token.isEmpty ? nil : reponse
    }

    /// Une adresse glissée dans une requête doit être échappée.
    private static func chiffrer(_ texte: String) -> String {
        texte.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? texte
    }

    static func connecter(email: String, motDePasse: String) async throws -> Session {
        try await appeler(
            "/auth/v1/token?grant_type=password",
            corps: ["email": email, "password": motDePasse]
        )
    }

    /// Connexion avec Apple : le jeton d'identité obtenu nativement est
    /// échangé contre une session Supabase, pour que les deux chemins
    /// aboutissent au même compte.
    static func connecterAvecApple(jetonIdentite: String, nonce: String?) async throws -> Session {
        var corps: [String: String] = ["provider": "apple", "id_token": jetonIdentite]
        if let nonce { corps["nonce"] = nonce }
        return try await appeler("/auth/v1/token?grant_type=id_token", corps: corps)
    }

    static func rafraichir(jeton: String) async throws -> Session {
        try await appeler(
            "/auth/v1/token?grant_type=refresh_token",
            corps: ["refresh_token": jeton]
        )
    }

    // MARK: - Mot de passe oublié

    static func reinitialiserMotDePasse(email: String) async throws {
        _ = try await brut(
            chemin: "/auth/v1/recover",
            methode: "POST",
            corps: ["email": email],
            jeton: nil
        )
    }

    /// Échange le code reçu par courrier contre une session.
    ///
    /// On passe par un code et non par un lien : un lien suppose que
    /// l'application sache se faire rouvrir depuis Safari — schéma d'URL ou
    /// domaine associé — et renvoie le lecteur hors de l'écran où il était.
    /// Un code se recopie sans quitter Honya.
    static func verifierCodeRecuperation(
        email: String, code: String
    ) async throws -> Session {
        try await appeler(
            "/auth/v1/verify",
            corps: ["type": "recovery", "email": email, "token": code]
        )
    }

    /// Pose le nouveau mot de passe sur le compte de la session en cours.
    static func changerMotDePasse(_ nouveau: String, jeton: String) async throws {
        _ = try await brut(
            chemin: "/auth/v1/user",
            methode: "PUT",
            corps: ["password": nouveau],
            jeton: jeton
        )
    }

    /// Renvoie le courrier de confirmation d'inscription.
    ///
    /// Le premier courrier se perd, s'efface ou part dans les indésirables ;
    /// sans ce renvoi, le compte reste créé mais inutilisable à jamais.
    static func renvoyerConfirmation(email: String) async throws {
        _ = try await brut(
            chemin: "/auth/v1/resend?redirect_to=" + chiffrer(retourConfirmation),
            methode: "POST",
            corps: ["type": "signup", "email": email],
            jeton: nil
        )
    }

    // MARK: - Déconnexion et suppression

    static func deconnecter(jeton: String) async {
        _ = try? await brut(chemin: "/auth/v1/logout", methode: "POST", corps: [:], jeton: jeton)
    }

    /// Suppression réelle du compte côté serveur. S'appuie sur une fonction
    /// Postgres `supprimer_mon_compte()` en SECURITY DEFINER : le client n'a
    /// jamais besoin d'une clé d'administration.
    static func supprimerCompte(jeton: String) async throws {
        _ = try await brut(
            chemin: "/rest/v1/rpc/supprimer_mon_compte",
            methode: "POST",
            corps: [:],
            jeton: jeton
        )
    }

    // MARK: - Plomberie

    private static func appeler<T: Decodable>(
        _ chemin: String,
        corps: [String: String]
    ) async throws -> T {
        let donnees = try await brut(chemin: chemin, methode: "POST", corps: corps, jeton: nil)
        do {
            return try JSONDecoder().decode(T.self, from: donnees)
        } catch {
            throw Souci.message(String(localized: "Réponse inattendue du serveur."))
        }
    }

    private static func brut(
        chemin: String,
        methode: String,
        corps: [String: String],
        jeton: String?
    ) async throws -> Data {
        guard configure, let url = URL(string: Secrets.supabaseURL + chemin) else {
            throw Souci.nonConfigure
        }
        var requete = URLRequest(url: url)
        requete.httpMethod = methode
        requete.setValue("application/json", forHTTPHeaderField: "Content-Type")
        requete.setValue(Secrets.supabaseCleAnon, forHTTPHeaderField: "apikey")
        requete.setValue(
            "Bearer \(jeton ?? Secrets.supabaseCleAnon)",
            forHTTPHeaderField: "Authorization"
        )
        requete.httpBody = try JSONSerialization.data(withJSONObject: corps)
        requete.timeoutInterval = 25

        let (donnees, reponse) = try await URLSession.shared.data(for: requete)
        let code = (reponse as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            // Le compte non confirmé se distingue : c'est le seul refus qui
            // se répare, en refaisant partir le courrier.
            let texte = String(data: donnees, encoding: .utf8)?.lowercased() ?? ""
            if texte.contains("not confirmed") { throw Souci.adresseNonConfirmee }
            throw Souci.message(messageLisible(donnees, code: code))
        }
        return donnees
    }

    /// Traduit les erreurs de l'API en français, sans jargon.
    private static func messageLisible(_ donnees: Data, code: Int) -> String {
        let brut = (try? JSONSerialization.jsonObject(with: donnees)) as? [String: Any]
        let texte = (brut?["msg"] as? String)
            ?? (brut?["error_description"] as? String)
            ?? (brut?["message"] as? String)
            ?? (brut?["error"] as? String)
            ?? ""

        let minuscule = texte.lowercased()
        if minuscule.contains("invalid login") || minuscule.contains("invalid credentials") {
            return String(localized: "Adresse e-mail ou mot de passe incorrect.")
        }
        if minuscule.contains("already registered") || minuscule.contains("already exists") {
            return String(localized: "Un compte existe déjà avec cette adresse. Connectez-vous.")
        }
        if minuscule.contains("password") && minuscule.contains("least") {
            return String(localized: "Le mot de passe doit faire au moins 6 caractères.")
        }
        if minuscule.contains("email") && minuscule.contains("invalid") {
            return String(localized: "Cette adresse e-mail ne semble pas valide.")
        }
        if minuscule.contains("not confirmed") {
            return String(localized: "Confirmez d'abord votre adresse : un courrier vous attend.")
        }
        if minuscule.contains("rate limit") || code == 429 {
            return String(localized: "Trop de tentatives. Réessayez dans quelques minutes.")
        }
        return texte.isEmpty
            ? String(localized: "La connexion a échoué (erreur \(code)).")
            : texte
    }
}

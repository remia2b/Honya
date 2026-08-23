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
        case message(String)

        var errorDescription: String? {
            switch self {
            case .nonConfigure:
                return "Les comptes par adresse e-mail ne sont pas encore configurés dans cette version."
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
    static func inscrire(email: String, motDePasse: String) async throws -> Session? {
        let reponse: Session = try await appeler(
            "/auth/v1/signup",
            corps: ["email": email, "password": motDePasse]
        )
        return reponse.access_token.isEmpty ? nil : reponse
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
            throw Souci.message("Réponse inattendue du serveur.")
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
            return "Adresse e-mail ou mot de passe incorrect."
        }
        if minuscule.contains("already registered") || minuscule.contains("already exists") {
            return "Un compte existe déjà avec cette adresse. Connectez-vous."
        }
        if minuscule.contains("password") && minuscule.contains("least") {
            return "Le mot de passe doit faire au moins 6 caractères."
        }
        if minuscule.contains("email") && minuscule.contains("invalid") {
            return "Cette adresse e-mail ne semble pas valide."
        }
        if minuscule.contains("not confirmed") {
            return "Confirmez d'abord votre adresse : un courrier vous attend."
        }
        if minuscule.contains("rate limit") || code == 429 {
            return "Trop de tentatives. Réessayez dans quelques minutes."
        }
        return texte.isEmpty ? "La connexion a échoué (erreur \(code))." : texte
    }
}

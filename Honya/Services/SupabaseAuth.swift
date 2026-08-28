import CryptoKit
import Foundation

/// L'authentification Supabase en REST pur — aucune dépendance à greffer dans
/// le projet Xcode. On ne parle qu'à l'API GoTrue du projet Honya (un projet
/// Supabase distinct de tout autre : base, utilisateurs et clés séparés).
enum SupabaseAuth {

    /// La langue du client est conservée dans `user_metadata` dès la création
    /// du compte. Les modèles de courriel Supabase peuvent ainsi rendre leur
    /// contenu avec `{{ .Data.language }}` au lieu d'imposer le français à
    /// tous les lecteurs.
    private struct CorpsInscription: Encodable, Sendable {
        struct Profil: Encodable, Sendable {
            let language: String
        }

        let email: String
        let password: String
        let data: Profil
    }

    struct Session: Codable, Sendable {
        let access_token: String
        let refresh_token: String
        let expires_at: Double?
        let user: Utilisateur?
    }

    struct Utilisateur: Codable, Sendable {
        let id: String
        let email: String?
    }

    struct SauvegardeBibliothequeDistante: Sendable {
        let contenu: BibliothequeSnapshotV1
        let version: Int
        let empreinte: String
        let revision: Int64
        let modifie_le: String
    }

    private struct ReponseSauvegardeBibliotheque: Decodable, Sendable {
        let contenu_base64: String
        let version: Int
        let empreinte: String
        let revision: Int64
        let modifie_le: String
    }

    enum Souci: LocalizedError {
        case nonConfigure
        /// Le serveur a explicitement refusé le jeton de renouvellement.
        /// À distinguer d'une panne réseau : seul ce cas ferme la session.
        case sessionInvalide
        /// Réponse HTTP reçue et donc définitive, avec son statut conservé.
        /// Les erreurs de transport restent des `URLError` et signalent une
        /// issue ambiguë pour une opération idempotente.
        case http(code: Int, message: String)
        /// Le compte existe mais son adresse n'a jamais été confirmée. Un cas
        /// à part : c'est le seul dont on sort en renvoyant un courrier.
        case adresseNonConfirmee
        /// Le serveur possede une revision plus recente que celle lue par ce
        /// client. Elle doit etre presentee au lecteur, jamais ecrasee.
        case conflitSauvegarde
        case message(String)

        var errorDescription: String? {
            switch self {
            case .nonConfigure:
                return String(localized: "Les comptes par adresse e-mail ne sont pas encore configurés dans cette version.")
            case .sessionInvalide:
                return String(localized: "La connexion n'a pas abouti. Réessayez dans un instant.")
            case .http(_, let message):
                return message
            case .adresseNonConfirmee:
                return String(localized: "Confirmez d'abord votre adresse : un courrier vous attend.")
            case .conflitSauvegarde:
                return String(localized: "La sauvegarde a changé sur un autre appareil.")
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
        let donnees = try await brut(
            chemin: "/auth/v1/signup?redirect_to=" + chiffrer(retourConfirmation),
            methode: "POST",
            corps: CorpsInscription(
                email: email,
                password: motDePasse,
                data: .init(language: Langues.codeAppareil)
            ),
            jeton: nil
        )
        // Deux réponses possibles, toutes deux des succès : la session
        // complète quand le projet n'exige pas de confirmation, ou le seul
        // utilisateur créé quand un courrier de confirmation part — sans
        // access_token. Exiger la session dans ce second cas faisait
        // afficher « Réponse inattendue du serveur » à une inscription qui
        // avait parfaitement réussi, le courrier déjà en route.
        guard let session = try? JSONDecoder().decode(Session.self, from: donnees),
              !session.access_token.isEmpty
        else { return nil }
        return session
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

    /// Confirme une adresse à partir du jeton haché porté par le lien du
    /// courrier, et ouvre la session dans la foulée.
    ///
    /// C'est ce qui permet au lien d'ouvrir l'APPLICATION plutôt que le site :
    /// le courrier ne pointe plus vers Supabase — qui redirigerait, et une
    /// redirection ne déclenche jamais un lien universel — mais directement
    /// vers honya.app, une adresse que le système reconnaît comme nôtre. La
    /// vérification, elle, se fait ici.
    static func confirmerAvecJeton(
        _ jetonHache: String, type: String
    ) async throws -> Session {
        try await appeler(
            "/auth/v1/verify",
            corps: ["type": type, "token_hash": jetonHache]
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

    /// Demande a Supabase quelle identite porte reellement un jeton d'acces.
    /// Les operations destructrices l'utilisent au dernier moment : un UUID
    /// conserve localement ne suffit jamais a choisir le compte a supprimer.
    static func lireUtilisateur(jeton: String) async throws -> Utilisateur {
        let donnees = try await brutEncode(
            chemin: "/auth/v1/user",
            methode: "GET",
            corps: Data(),
            jeton: jeton
        )
        do {
            return try JSONDecoder().decode(Utilisateur.self, from: donnees)
        } catch {
            throw Souci.message(String(localized: "Réponse inattendue du serveur."))
        }
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
        _ = try? await brut(
            chemin: "/auth/v1/logout",
            methode: "POST",
            corps: [String: String](),
            jeton: jeton
        )
    }

    /// Suppression réelle du compte côté serveur. S'appuie sur une fonction
    /// Postgres `supprimer_mon_compte()` en SECURITY DEFINER : le client n'a
    /// jamais besoin d'une clé d'administration.
    static func supprimerCompte(jeton: String, cle: UUID) async throws {
        _ = try await brut(
            chemin: "/rest/v1/rpc/supprimer_mon_compte",
            methode: "POST",
            corps: ["p_cle": cle.uuidString.lowercased()],
            jeton: jeton
        )
    }

    /// Reçu sans donnée personnelle, consultable grâce à sa clé UUID
    /// imprévisible. Il tranche une perte de réponse après le POST : `true`
    /// signifie que suppression distante et reçu ont été validés dans la
    /// même transaction PostgreSQL.
    static func suppressionConfirmee(cle: UUID) async throws -> Bool {
        let donnees = try await brut(
            chemin: "/rest/v1/rpc/suppression_compte_confirmee",
            methode: "POST",
            corps: ["p_cle": cle.uuidString.lowercased()],
            jeton: nil
        )
        do {
            return try JSONDecoder().decode(Bool.self, from: donnees)
        } catch {
            throw Souci.message(String(localized: "Réponse inattendue du serveur."))
        }
    }

    // MARK: - Sauvegarde de la bibliotheque

    private struct CorpsSauvegardeBibliotheque: Encodable, Sendable {
        let p_contenu: String
        let p_version: Int
        let p_empreinte: String
        let p_revision_attendue: Int64
    }

    static func lireSauvegardeBibliotheque(
        jeton: String
    ) async throws -> SauvegardeBibliothequeDistante? {
        let donnees = try await brut(
            chemin: "/rest/v1/rpc/lire_ma_sauvegarde_bibliotheque",
            methode: "POST",
            corps: [String: String](),
            jeton: jeton
        )
        if String(data: donnees, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) == "null" {
            return nil
        }
        return try decoderEtVerifierSauvegarde(donnees)
    }

    static func enregistrerSauvegardeBibliotheque(
        _ export: ExporteurBibliothequeSnapshotV1.Resultat,
        revisionAttendue: Int64,
        jeton: String
    ) async throws -> SauvegardeBibliothequeDistante {
        let donnees = try await brut(
            chemin: "/rest/v1/rpc/enregistrer_ma_sauvegarde_bibliotheque",
            methode: "POST",
            corps: CorpsSauvegardeBibliotheque(
                p_contenu: export.donnees.base64EncodedString(),
                p_version: BibliothequeSnapshotV1.versionActuelle,
                p_empreinte: export.empreinteSHA256,
                p_revision_attendue: revisionAttendue
            ),
            jeton: jeton
        )
        return try decoderEtVerifierSauvegarde(donnees)
    }

    private static func decoderEtVerifierSauvegarde(
        _ donnees: Data
    ) throws -> SauvegardeBibliothequeDistante {
        let filaire: ReponseSauvegardeBibliotheque
        do {
            filaire = try JSONDecoder().decode(
                ReponseSauvegardeBibliotheque.self,
                from: donnees
            )
        } catch {
            throw Souci.message(String(localized: "Réponse inattendue du serveur."))
        }
        guard filaire.version == BibliothequeSnapshotV1.versionActuelle,
              filaire.revision > 0,
              filaire.contenu_base64.count <= 26_666_668,
              let canoniques = Data(base64Encoded: filaire.contenu_base64),
              canoniques.count <= 20_000_000
        else { throw Souci.message(String(localized: "Réponse inattendue du serveur.")) }

        let empreinte = SHA256.hash(data: canoniques)
            .map { String(format: "%02x", $0) }
            .joined()
        guard empreinte == filaire.empreinte else {
            throw Souci.message(String(localized: "Réponse inattendue du serveur."))
        }
        let contenu: BibliothequeSnapshotV1
        do {
            contenu = try RestaurateurBibliothequeSnapshotV1.decoder(canoniques)
        } catch {
            throw Souci.message(String(localized: "Réponse inattendue du serveur."))
        }
        guard contenu.version == filaire.version else {
            throw Souci.message(String(localized: "Réponse inattendue du serveur."))
        }
        return SauvegardeBibliothequeDistante(
            contenu: contenu,
            version: filaire.version,
            empreinte: filaire.empreinte,
            revision: filaire.revision,
            modifie_le: filaire.modifie_le
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

    private static func brut<Corps: Encodable & Sendable>(
        chemin: String,
        methode: String,
        corps: Corps,
        jeton: String?
    ) async throws -> Data {
        try await brutEncode(
            chemin: chemin,
            methode: methode,
            corps: JSONEncoder().encode(corps),
            jeton: jeton
        )
    }

    private static func brutEncode(
        chemin: String,
        methode: String,
        corps: Data,
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
        requete.httpBody = corps
        requete.timeoutInterval = 25

        let (donnees, reponse) = try await URLSession.shared.data(for: requete)
        let code = (reponse as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            // Le compte non confirmé se distingue : c'est le seul refus qui
            // se répare, en refaisant partir le courrier.
            let texte = String(data: donnees, encoding: .utf8)?.lowercased() ?? ""
            if texte.contains("revision_conflict") { throw Souci.conflitSauvegarde }
            if texte.contains("not confirmed") { throw Souci.adresseNonConfirmee }
            if (code == 400 || code == 401), chemin.contains("grant_type=refresh_token") {
                throw Souci.sessionInvalide
            }
            if code == 401, jeton != nil { throw Souci.sessionInvalide }
            throw Souci.http(code: code, message: messageLisible(donnees, code: code))
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

import AuthenticationServices
import CryptoKit
import SwiftData
import SwiftUI

/// Le compte Honya. Deux chemins, un seul compte : l'identifiant Apple (rien
/// à retenir) ou une adresse e-mail et un mot de passe.
@Observable
@MainActor
final class Compte {
    static let partage = Compte()

    enum Etat: Equatable {
        /// Aucun choix encore effectué : l'écran de bienvenue.
        case indetermine
        case connecte
    }

    enum Methode: String {
        case apple, email
    }

    private(set) var etat: Etat = .indetermine
    private(set) var identifiant: String?
    /// UUID du compte Supabase, distinct de l'identifiant privé Apple.
    /// Il permet de vérifier qu'une réauthentification destinée à terminer
    /// une suppression ouvre bien le même compte.
    private(set) var identifiantServeur: String?
    private(set) var nom: String?
    private(set) var email: String?
    private(set) var methode: Methode = .apple
    /// Vrai uniquement apres une authentification ou un renouvellement que
    /// Supabase vient d'accepter dans ce processus. Une preference locale ne
    /// peut jamais revendiquer seule l'ancien store SwiftData.
    private(set) var sessionVerifiee = false
    /// Invalide toute verification asynchrone commencee pour une ancienne
    /// identite avant une deconnexion/reconnexion rapide.
    private var generationSession = 0
    private var tacheRenouvellement: Task<SupabaseAuth.Session, Error>?
    private var compteTacheRenouvellement: String?
    private var ticketTacheRenouvellement: UUID?
    /// Une suppression possède deux validations indépendantes. Les persister
    /// séparément évite les deux fenêtres de crash : avant la réponse du
    /// serveur, puis avant le `save()` SwiftData.
    private enum PhaseSuppression: String {
        case aucune, distante, locale
    }
    private var phaseSuppression: PhaseSuppression = .aucune
    var suppressionEnAttente: Bool { phaseSuppression != .aucune }
    /// Empêche deux scènes ou deux reprises de lancer simultanément la même
    /// transaction. `@MainActor` est réentrant dès le premier `await` : un
    /// simple test de phase ne suffit donc pas à lui seul.
    private(set) var suppressionEnCours = false
    private(set) var suppressionReconnexionRequise = false
    private(set) var erreurRepriseSuppression: String?

    /// Nonce de la demande Apple en cours, pour l'échange avec Supabase.
    private var nonceEnCours: String?
    /// Réagit immédiatement si l'accès « Se connecter avec Apple » est retiré
    /// depuis Réglages, sans attendre le prochain lancement.
    private var observateurRevocationApple: NSObjectProtocol?

    private let defaults = UserDefaults.standard
    private enum Cle {
        static let etat = "compteEtat"
        static let identifiant = "compteIdentifiant"
        static let identifiantServeur = "compteIdentifiantServeur"
        static let nom = "compteNom"
        static let email = "compteEmail"
        static let methode = "compteMethode"
        static let jetonAcces = "jetonAcces"
        static let jetonRenouvellement = "jetonRenouvellement"
        static let phaseSuppression = "phaseSuppressionCompte"
        static let ancienDrapeauSuppression = "suppressionLocaleEnAttente"
        static let cleSuppression = "suppressionCompteCle"
        static let cibleSuppressionServeur = "suppressionCompteCibleServeur"
        static let cibleSuppressionIdentifiant = "suppressionCompteCibleIdentifiant"
        static let cibleSuppressionEmail = "suppressionCompteCibleEmail"
        static let cibleSuppressionMethode = "suppressionCompteCibleMethode"
        static let cibleSuppressionStockage = "suppressionCompteCibleStockage"
    }

    private init() {
        phaseSuppression = PhaseSuppression(
            rawValue: defaults.string(forKey: Cle.phaseSuppression) ?? ""
        ) ?? (defaults.bool(forKey: Cle.ancienDrapeauSuppression) ? .locale : .aucune)
        defaults.removeObject(forKey: Cle.ancienDrapeauSuppression)
        if phaseSuppression != .aucune {
            defaults.set(phaseSuppression.rawValue, forKey: Cle.phaseSuppression)
        }
        identifiant = defaults.string(forKey: Cle.identifiant)
        identifiantServeur = defaults.string(forKey: Cle.identifiantServeur)
        nom = defaults.string(forKey: Cle.nom)
        email = defaults.string(forKey: Cle.email)
        methode = Methode(rawValue: defaults.string(forKey: Cle.methode) ?? "") ?? .apple
        switch defaults.string(forKey: Cle.etat) {
        case "connecte" where identifiant != nil: etat = .connecte
        case "invite":
            // Migration des versions qui autorisaient un mode local. Seul le
            // droit d'entrer est retiré : la bibliothèque SwiftData reste
            // intacte et réapparaît après une vraie connexion.
            etat = .indetermine
            defaults.removeObject(forKey: Cle.etat)
        default:
            etat = .indetermine
            defaults.removeObject(forKey: Cle.etat)
        }
        if etat == .connecte,
           (!SupabaseAuth.configure
            || identifiantServeur?.isEmpty != false
            || Trousseau.lire(Cle.jetonRenouvellement) == nil) {
            // Une préférence locale ne vaut jamais un compte. L'entrée exige
            // désormais la configuration Supabase, son UUID utilisateur et un
            // jeton renouvelable ; on force sinon une réauthentification sans
            // toucher à la bibliothèque héritée.
            etat = .indetermine
            defaults.removeObject(forKey: Cle.etat)
        }
        // Une suppression interrompue garde l'ancienne base invisible jusqu'à
        // ce que le prochain lancement ait réellement réussi à la vider.
        if suppressionEnAttente { etat = .indetermine }
        observateurRevocationApple = NotificationCenter.default.addObserver(
            forName: ASAuthorizationAppleIDProvider.credentialRevokedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.seDeconnecter() }
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

    /// Méthode qui a ouvert le compte dont la suppression doit reprendre.
    /// L'écran de réauthentification n'en propose aucune autre : un échange
    /// OIDC Apple peut créer un nouvel utilisateur avant que le client ne voie
    /// qu'il ne correspond pas à la cible.
    var methodeReconnexionSuppression: Methode? {
        guard phaseSuppression == .distante else { return nil }
        return Methode(
            rawValue: defaults.string(forKey: Cle.cibleSuppressionMethode) ?? ""
        )
    }

    var identifiantServeurCibleSuppression: String? {
        defaults.string(forKey: Cle.cibleSuppressionServeur)
    }

    var typeStockageCibleSuppression: StockageCompte.TypeStoreSuppression? {
        defaults.string(forKey: Cle.cibleSuppressionStockage)
            .flatMap(StockageCompte.TypeStoreSuppression.init(rawValue:))
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

    func connecterAvecApple(_ credential: ASAuthorizationAppleIDCredential) async throws {
        defer { nonceEnCours = nil }
        guard SupabaseAuth.configure else { throw SupabaseAuth.Souci.nonConfigure }
        if phaseSuppression == .distante {
            // À faire AVANT `grant_type=id_token` : GoTrue est autorisé à
            // créer une identité externe absente pendant cet échange. Refuser
            // ensuite le mauvais UUID laisserait donc un compte orphelin.
            guard methodeReconnexionSuppression == .apple,
                  let cibleApple = defaults.string(
                    forKey: Cle.cibleSuppressionIdentifiant
                  ),
                  !cibleApple.isEmpty,
                  credential.user == cibleApple
            else {
                throw SupabaseAuth.Souci.message(String(localized:
                    "Reconnectez-vous avec le compte dont la suppression a été demandée."
                ))
            }
        }

        // Une connexion affichée comme réussie possède toujours une vraie
        // session serveur. Sans elle, le compte serait impossible à supprimer,
        // sauvegarder ou retrouver sur un autre appareil.
        guard let jeton = credential.identityToken,
              let texte = String(data: jeton, encoding: .utf8)
        else {
            throw SupabaseAuth.Souci.message(
                String(localized: "La connexion n'a pas abouti. Réessayez dans un instant.")
            )
        }
        let session = try await SupabaseAuth.connecterAvecApple(
            jetonIdentite: texte,
            nonce: nonceEnCours
        )
        guard let identifiantServeur = session.user?.id,
              !identifiantServeur.isEmpty else {
            throw SupabaseAuth.Souci.message(
                String(localized: "Réponse inattendue du serveur.")
            )
        }
        try verifierCibleSuppression(
            session: session,
            methodeCandidate: .apple,
            identifiantCandidate: credential.user,
            emailCandidate: credential.email
        )
        enregistrer(session)
        sessionVerifiee = true

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
        finaliserConnexion()
    }

    // MARK: - Adresse e-mail

    /// Renvoie un message à afficher quand la confirmation par courrier est
    /// exigée : dans ce cas il n'y a pas encore de session.
    func inscrire(email adresse: String, motDePasse: String) async throws -> String? {
        guard !suppressionEnAttente else {
            throw SupabaseAuth.Souci.message(String(localized:
                "Reconnectez-vous avec le compte dont la suppression a été demandée."
            ))
        }
        let session = try await SupabaseAuth.inscrire(email: adresse, motDePasse: motDePasse)
        guard let session else {
            return String(localized: "Compte créé. Ouvrez le courrier de confirmation, puis connectez-vous.")
        }
        try adopter(session, adresse: adresse)
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
            // Une page web ne peut pas attester à l'application qu'une adresse
            // a été confirmée. Sans jeton vérifiable, aucun message vert : le
            // site doit transmettre `token_hash` et `type` dans son deep link.
            if url.scheme == "honya", url.host == "confirme" {
                adresseVientDEtreConfirmee = false
                soucisDeConfirmation = String(localized:
                    "Ce lien de confirmation est incomplet. Renvoyez un nouveau courrier."
                )
            }
            return false
        }

        let type = elements.first(where: { $0.name == "type" })?.value ?? "signup"
        soucisDeConfirmation = nil
        do {
            let session = try await SupabaseAuth.confirmerAvecJeton(jeton, type: type)
            // On ne connecte PAS. Confirmer une adresse et ouvrir une session
            // sont deux gestes distincts : les confondre ferait entrer dans le
            // compte quiconque met la main sur le courrier — sur un téléphone
            // prêté, une boîte partagée, un message transféré. Le lecteur
            // revient donc à l'écran de connexion, son adresse déjà inscrite,
            // et donne son mot de passe.
            if let adresse = session.user?.email, !adresse.isEmpty {
                email = adresse
                defaults.set(adresse, forKey: Cle.email)
            }
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
        try adopter(session, adresse: adresse)
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
        let session = try await SupabaseAuth.verifierCodeRecuperation(
            email: adresse, code: code
        )
        try verifierCibleSuppression(
            session: session,
            methodeCandidate: .email,
            identifiantCandidate: session.user?.id,
            emailCandidate: adresse
        )
        sessionRecuperation = session
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
        try adopter(session, adresse: adresse)
        sessionRecuperation = nil
    }

    private func adopter(_ session: SupabaseAuth.Session, adresse: String) throws {
        guard let identifiantServeur = session.user?.id,
              !identifiantServeur.isEmpty else {
            throw SupabaseAuth.Souci.message(
                String(localized: "Réponse inattendue du serveur.")
            )
        }
        try verifierCibleSuppression(
            session: session,
            methodeCandidate: .email,
            identifiantCandidate: session.user?.id,
            emailCandidate: adresse
        )
        identifiant = identifiantServeur
        email = session.user?.email ?? adresse
        methode = .email
        enregistrer(session)
        sessionVerifiee = true
        // Le bandeau vert a fait son travail : la session s'ouvre. Sans cet
        // oubli, il ressortirait à la prochaine déconnexion, à annoncer une
        // confirmation vieille de plusieurs semaines.
        accuserConfirmation()
        finaliserConnexion()
    }

    /// En reprise de suppression, un autre compte ne doit jamais être effacé
    /// par mégarde. L'UUID Supabase est prioritaire ; les identifiants Apple
    /// ou e-mail ne servent que de repli pour une ancienne installation.
    private func verifierCibleSuppression(
        session: SupabaseAuth.Session,
        methodeCandidate: Methode,
        identifiantCandidate: String?,
        emailCandidate: String?
    ) throws {
        guard phaseSuppression == .distante else { return }

        let correspond: Bool
        if let cible = defaults.string(forKey: Cle.cibleSuppressionServeur),
           !cible.isEmpty {
            correspond = session.user?.id == cible
        } else {
            let methodeCible = Methode(
                rawValue: defaults.string(forKey: Cle.cibleSuppressionMethode) ?? ""
            )
            guard methodeCible == methodeCandidate else {
                throw SupabaseAuth.Souci.message(String(localized:
                    "Reconnectez-vous avec le compte dont la suppression a été demandée."
                ))
            }
            switch methodeCandidate {
            case .apple:
                correspond = identifiantCandidate == defaults.string(
                    forKey: Cle.cibleSuppressionIdentifiant
                )
            case .email:
                let cible = defaults.string(forKey: Cle.cibleSuppressionEmail)?.lowercased()
                correspond = (session.user?.email ?? emailCandidate)?.lowercased() == cible
            }
        }

        guard correspond else {
            throw SupabaseAuth.Souci.message(String(localized:
                "Reconnectez-vous avec le compte dont la suppression a été demandée."
            ))
        }
    }

    // MARK: - Session

    private func enregistrer(_ session: SupabaseAuth.Session) {
        if let id = session.user?.id, !id.isEmpty {
            identifiantServeur = id
            defaults.set(id, forKey: Cle.identifiantServeur)
        }
        Trousseau.ecrire(session.access_token, cle: Cle.jetonAcces)
        Trousseau.ecrire(session.refresh_token, cle: Cle.jetonRenouvellement)
    }

    private func finaliserConnexion() {
        defaults.set(identifiant, forKey: Cle.identifiant)
        defaults.set(identifiantServeur, forKey: Cle.identifiantServeur)
        defaults.set(nom, forKey: Cle.nom)
        defaults.set(email, forKey: Cle.email)
        defaults.set(methode.rawValue, forKey: Cle.methode)
        defaults.set("connecte", forKey: Cle.etat)
        suppressionReconnexionRequise = false
        erreurRepriseSuppression = nil
        generationSession &+= 1
        etat = .connecte
    }

    /// Jeton court utilise par les services Supabase apres le montage du
    /// compte. Il n'est jamais expose aux vues ni persiste hors Trousseau.
    func jetonAccesPourAPI(compteAttendu: UUID) throws -> String {
        guard etat == .connecte, !suppressionEnAttente,
              identifiantServeur.flatMap(UUID.init(uuidString:)) == compteAttendu,
              let jeton = Trousseau.lire(Cle.jetonAcces), !jeton.isEmpty
        else { throw SupabaseAuth.Souci.sessionInvalide }
        return jeton
    }

    /// Renouvelle une fois la session lorsqu'une requete de donnees recoit
    /// 401, puis verifie que Supabase renvoie toujours le meme UUID. Un jeton
    /// d'un autre compte ne peut donc jamais acceder au store actuellement
    /// monte, meme apres une rotation de session.
    func renouvelerJetonPourAPI(compteAttendu: UUID) async throws -> String {
        guard etat == .connecte, !suppressionEnAttente,
              let attendu = identifiantServeur, !attendu.isEmpty,
              UUID(uuidString: attendu) == compteAttendu,
              let renouvellement = Trousseau.lire(Cle.jetonRenouvellement)
        else { throw SupabaseAuth.Souci.sessionInvalide }

        let session = try await renouvelerSessionPartagee(
            compteAttendu: attendu,
            jeton: renouvellement
        )
        guard etat == .connecte, !suppressionEnAttente,
              identifiantServeur == attendu,
              let recu = session.user?.id, recu == attendu else {
            throw SupabaseAuth.Souci.sessionInvalide
        }
        enregistrer(session)
        sessionVerifiee = true
        return session.access_token
    }

    func seDeconnecter() {
        if let jeton = Trousseau.lire(Cle.jetonAcces) {
            Task { await SupabaseAuth.deconnecter(jeton: jeton) }
        }
        oublier()
        NotificationsService.annulerTousLesRappelsSortie()
        StockageCompte.partage.desactiver()
        // Retour à la bienvenue : la bibliothèque reste sur l'appareil, mais
        // l'application redemande un compte.
        defaults.removeObject(forKey: Cle.etat)
        etat = .indetermine
    }

    /// Au lancement : une révocation depuis les Réglages d'iOS doit se voir,
    /// et la session serveur se renouvelle en silence.
    func verifierSession() async {
        guard etat == .connecte,
              let identifiantCapture = identifiant,
              let serveurCapture = identifiantServeur,
              !serveurCapture.isEmpty
        else { return }
        let methodeCapture = methode
        let generationCapture = generationSession

        func porteeToujoursValide() -> Bool {
            generationSession == generationCapture
                && etat == .connecte
                && !suppressionEnAttente
                && identifiant == identifiantCapture
                && identifiantServeur == serveurCapture
                && methode == methodeCapture
        }

        if methodeCapture == .apple {
            let statut = try? await ASAuthorizationAppleIDProvider()
                .credentialState(forUserID: identifiantCapture)
            guard porteeToujoursValide() else { return }
            if statut == .revoked || statut == .notFound {
                seDeconnecter()
                return
            }
        }
        if SupabaseAuth.configure, let renouvellement = Trousseau.lire(Cle.jetonRenouvellement) {
            do {
                let session = try await renouvelerSessionPartagee(
                    compteAttendu: serveurCapture,
                    jeton: renouvellement
                )
                guard porteeToujoursValide() else { return }
                guard let serveur = session.user?.id,
                      !serveur.isEmpty,
                      serveurCapture == serveur else {
                    seDeconnecter()
                    return
                }
                enregistrer(session)
                sessionVerifiee = true
            } catch SupabaseAuth.Souci.sessionInvalide {
                // Un jeton explicitement refusé ne redeviendra jamais valide.
                // Une simple panne réseau, en revanche, conserve la session
                // locale pour que la bibliothèque reste utilisable hors ligne.
                if porteeToujoursValide() { seDeconnecter() }
            } catch {
                // Réseau absent ou serveur momentanément indisponible.
            }
        }
    }

    // MARK: - Suppression du compte

    /// Efface le compte côté serveur quand il y en a un, puis tout ce que
    /// Honya sait du lecteur sur l'appareil.
    func supprimerCompte(dans contexte: ModelContext) async throws {
        guard !suppressionEnAttente, !suppressionEnCours else { return }
        guard let compteAttendu = identifiantServeur,
              UUID(uuidString: compteAttendu) != nil,
              contexteSuppressionValide(
                contexte,
                compteAttendu: compteAttendu
              ) else {
            throw SupabaseAuth.Souci.sessionInvalide
        }
        suppressionEnCours = true
        defer { suppressionEnCours = false }

        // Il n'existe plus de compte purement local. En cas de build mal
        // configuré, ne jamais effacer seulement l'iPhone en laissant le compte
        // distant intact.
        guard SupabaseAuth.configure else { throw SupabaseAuth.Souci.nonConfigure }

        let cle = UUID()
        preparerSuppressionDistante(cle: cle)

        // Le serveur passe en premier : une panne réseau ne doit jamais
        // effacer uniquement l'iPhone tout en laissant le compte utilisable.
        do {
            try await supprimerCompteDistant(
                cle: cle,
                contexte: contexte,
                compteAttendu: compteAttendu
            )
            guard contexteSuppressionValide(
                contexte,
                compteAttendu: compteAttendu
            ) else { throw SupabaseAuth.Souci.sessionInvalide }
        } catch {
            let confirmation = await suppressionConfirmee(cle: cle)
            guard contexteSuppressionValide(
                contexte,
                compteAttendu: compteAttendu
            ) else { throw SupabaseAuth.Souci.sessionInvalide }
            if confirmation == true {
                passerAuNettoyageLocal()
                try terminerNettoyageLocal(dans: contexte)
                return
            }

            if let souci = error as? SupabaseAuth.Souci,
               case .sessionInvalide = souci {
                if confirmation == false {
                    // Le reçu répond explicitement « non supprimé » : les
                    // anciens jetons ne prouvent plus l'identité, une
                    // réauthentification du même compte est alors nécessaire.
                    suppressionReconnexionRequise = true
                    erreurRepriseSuppression = nil
                } else {
                    // Reçu injoignable : le POST a peut-être réussi et le 401
                    // peut justement signifier que le compte n'existe plus.
                    // Ne jamais recréer un utilisateur via une réauth dans ce
                    // doute ; conserver la clé et proposer simplement Retry.
                    phaseSuppression = .distante
                    suppressionReconnexionRequise = false
                    erreurRepriseSuppression = error.localizedDescription
                }
            } else if Self.refusDistantDefinitif(error) {
                let message = error.localizedDescription
                annulerSuppressionDistante()
                // La racine a déjà démonté Réglages dès la phase distante :
                // l'alerte locale ne peut plus porter cette erreur.
                erreurRepriseSuppression = message
            } else {
                // Timeout, annulation ou réponse 5xx : le POST a pu être
                // validé malgré la perte de réponse. La clé et les jetons
                // restent intacts ; l'app masque les données et vérifiera le
                // reçu avant tout nouvel essai.
                phaseSuppression = .distante
                erreurRepriseSuppression = error.localizedDescription
            }
            throw error
        }

        guard contexteSuppressionValide(
            contexte,
            compteAttendu: compteAttendu
        ) else { throw SupabaseAuth.Souci.sessionInvalide }
        passerAuNettoyageLocal()
        try terminerNettoyageLocal(dans: contexte)
    }

    /// Reprise idempotente après une interruption. Une phase distante retente
    /// d'abord Supabase ; une phase locale ne touche plus jamais au réseau.
    @discardableResult
    func reprendreSuppression(dans contexte: ModelContext) async -> Bool {
        guard suppressionEnAttente else { return true }
        guard !suppressionEnCours else { return false }
        suppressionEnCours = true
        defer { suppressionEnCours = false }

        let compteAttendu = identifiantServeurCibleSuppression
        guard contexteSuppressionValide(
            contexte,
            compteAttendu: compteAttendu
        ) else {
            erreurRepriseSuppression = String(localized:
                "La connexion n'a pas abouti. Réessayez dans un instant."
            )
            return false
        }

        if phaseSuppression == .distante {
            guard let compteAttendu, let cle = cleSuppression else {
                erreurRepriseSuppression = String(localized:
                    "La connexion n'a pas abouti. Réessayez dans un instant."
                )
                suppressionReconnexionRequise = true
                return false
            }

            if await suppressionConfirmee(cle: cle) == true {
                guard contexteSuppressionValide(
                    contexte,
                    compteAttendu: compteAttendu
                ) else { return false }
                passerAuNettoyageLocal()
            } else {
                guard contexteSuppressionValide(
                    contexte,
                    compteAttendu: compteAttendu
                ) else { return false }
                do {
                    try await supprimerCompteDistant(
                        cle: cle,
                        contexte: contexte,
                        compteAttendu: compteAttendu
                    )
                    guard contexteSuppressionValide(
                        contexte,
                        compteAttendu: compteAttendu
                    ) else { return false }
                } catch {
                    let confirmation = await suppressionConfirmee(cle: cle)
                    guard contexteSuppressionValide(
                        contexte,
                        compteAttendu: compteAttendu
                    ) else { return false }
                    if confirmation == true {
                        passerAuNettoyageLocal()
                    } else {
                        if let souci = error as? SupabaseAuth.Souci,
                           case .sessionInvalide = souci {
                            if confirmation == false {
                                // Le reçu confirme que la suppression n'a pas
                                // eu lieu : seulement ici, réauthentifier.
                                suppressionReconnexionRequise = true
                                erreurRepriseSuppression = nil
                            } else {
                                // `nil` est une panne de vérification, jamais
                                // la preuve que le compte existe encore.
                                suppressionReconnexionRequise = false
                                erreurRepriseSuppression = error.localizedDescription
                            }
                        } else if Self.refusDistantDefinitif(error) {
                            // La requête a été refusée avant suppression (RPC
                            // absente, droits mal configurés, corps invalide…).
                            // Masquer éternellement une bibliothèque intacte
                            // ne répare rien : on annule l'intention, restaure
                            // la session locale et présente l'erreur globale.
                            annulerSuppressionDistante()
                            restaurerEtatPersiste()
                            erreurRepriseSuppression = error.localizedDescription
                        } else {
                            erreurRepriseSuppression = error.localizedDescription
                        }
                        return false
                    }
                }
                if phaseSuppression == .distante { passerAuNettoyageLocal() }
            }
        }

        do {
            try terminerNettoyageLocal(dans: contexte)
            return true
        } catch {
            erreurRepriseSuppression = error.localizedDescription
            return false
        }
    }

    private var cleSuppression: UUID? {
        defaults.string(forKey: Cle.cleSuppression).flatMap { UUID(uuidString: $0) }
    }

    private func preparerSuppressionDistante(cle: UUID) {
        // Publiée en mémoire AVANT le premier `await` : une deuxième scène ne
        // peut pas remplacer la clé pendant que le premier POST est en vol.
        phaseSuppression = .distante
        suppressionReconnexionRequise = false
        erreurRepriseSuppression = nil
        defaults.set(cle.uuidString.lowercased(), forKey: Cle.cleSuppression)
        defaults.set(identifiantServeur, forKey: Cle.cibleSuppressionServeur)
        defaults.set(identifiant, forKey: Cle.cibleSuppressionIdentifiant)
        defaults.set(email?.lowercased(), forKey: Cle.cibleSuppressionEmail)
        defaults.set(methode.rawValue, forKey: Cle.cibleSuppressionMethode)
        defaults.set(
            StockageCompte.partage.typeStoreActifPourSuppression?.rawValue,
            forKey: Cle.cibleSuppressionStockage
        )
        // Persisté avant le POST ; un crash recharge cette phase au lancement.
        defaults.set(PhaseSuppression.distante.rawValue, forKey: Cle.phaseSuppression)
    }

    private func annulerSuppressionDistante() {
        let cles = [
            Cle.phaseSuppression, Cle.cleSuppression,
            Cle.cibleSuppressionServeur, Cle.cibleSuppressionIdentifiant,
            Cle.cibleSuppressionEmail, Cle.cibleSuppressionMethode,
            Cle.cibleSuppressionStockage,
        ]
        for cle in cles { defaults.removeObject(forKey: cle) }
        phaseSuppression = .aucune
        suppressionReconnexionRequise = false
        erreurRepriseSuppression = nil
    }

    /// Au lancement, une suppression en attente force temporairement l'état
    /// `.indetermine`. Si le serveur refuse définitivement l'opération avant
    /// d'avoir supprimé le compte, on rétablit l'état qui était persisté.
    private func restaurerEtatPersiste() {
        switch defaults.string(forKey: Cle.etat) {
        case "connecte" where identifiant != nil:
            etat = .connecte
        case "invite":
            // Même migration lors d'une reprise de suppression : ne jamais
            // restaurer un accès invité devenu interdit.
            defaults.removeObject(forKey: Cle.etat)
            etat = .indetermine
        default:
            etat = .indetermine
        }
    }

    func accuserErreurRepriseSuppression() {
        guard !suppressionEnAttente else { return }
        erreurRepriseSuppression = nil
    }

    private static func refusDistantDefinitif(_ error: Error) -> Bool {
        guard let souci = error as? SupabaseAuth.Souci else { return false }
        switch souci {
        case .sessionInvalide, .nonConfigure, .adresseNonConfirmee,
             .conflitSauvegarde, .message(_):
            return true
        case .http(let code, _):
            return (400..<500).contains(code) && ![408, 429].contains(code)
        }
    }

    private func suppressionConfirmee(cle: UUID) async -> Bool? {
        try? await SupabaseAuth.suppressionConfirmee(cle: cle)
    }

    private func supprimerCompteDistant(
        cle: UUID,
        contexte: ModelContext,
        compteAttendu: String
    ) async throws {
        guard SupabaseAuth.configure else { throw SupabaseAuth.Souci.nonConfigure }
        guard phaseSuppression == .distante,
              defaults.string(forKey: Cle.cibleSuppressionServeur) == compteAttendu,
              contexteSuppressionValide(
                contexte,
                compteAttendu: compteAttendu
              ) else {
            throw SupabaseAuth.Souci.sessionInvalide
        }
        var jeton = Trousseau.lire(Cle.jetonAcces)
        if let renouvellement = Trousseau.lire(Cle.jetonRenouvellement) {
            do {
                let session = try await renouvelerSessionPartagee(
                    compteAttendu: compteAttendu,
                    jeton: renouvellement
                )
                guard contexteSuppressionValide(
                        contexte,
                        compteAttendu: compteAttendu
                      ) else { throw CancellationError() }
                guard phaseSuppression == .distante,
                      defaults.string(forKey: Cle.cibleSuppressionServeur) == compteAttendu,
                      session.user?.id == compteAttendu else {
                    // Ne jamais retomber sur l'ancien access token apres une
                    // reponse de refresh portant une autre identite.
                    jeton = nil
                    throw SupabaseAuth.Souci.sessionInvalide
                }
                enregistrer(session)
                jeton = session.access_token
            } catch SupabaseAuth.Souci.sessionInvalide {
                // Le jeton d'accès peut encore être valable. Le reçu, jamais
                // un simple 401, tranchera après l'appel final.
            }
        }
        guard contexteSuppressionValide(
            contexte,
            compteAttendu: compteAttendu
        ) else { throw CancellationError() }
        guard let jeton else {
            throw SupabaseAuth.Souci.sessionInvalide
        }
        // Validation serveur fail-close du jeton finalement retenu, y compris
        // le fallback encore valable lorsque le refresh token a expire.
        let utilisateur = try await SupabaseAuth.lireUtilisateur(jeton: jeton)
        guard contexteSuppressionValide(
                contexte,
                compteAttendu: compteAttendu
              ),
              phaseSuppression == .distante,
              defaults.string(forKey: Cle.cibleSuppressionServeur) == compteAttendu,
              utilisateur.id == compteAttendu else {
            throw SupabaseAuth.Souci.sessionInvalide
        }
        try await SupabaseAuth.supprimerCompte(jeton: jeton, cle: cle)
        guard contexteSuppressionValide(
            contexte,
            compteAttendu: compteAttendu
        ) else { throw CancellationError() }
    }

    private func passerAuNettoyageLocal() {
        phaseSuppression = .locale
        defaults.set(PhaseSuppression.locale.rawValue, forKey: Cle.phaseSuppression)
        suppressionReconnexionRequise = false
        erreurRepriseSuppression = nil
        oublier()
        defaults.removeObject(forKey: Cle.etat)
        etat = .indetermine
    }

    private func terminerNettoyageLocal(dans contexte: ModelContext) throws {
        guard contexteSuppressionValide(
            contexte,
            compteAttendu: identifiantServeurCibleSuppression
        ) else { throw SupabaseAuth.Souci.sessionInvalide }
        // Le compte serveur n'existe plus. Si save() échoue, `.locale` reste
        // persisté et l'app demeure bloquée jusqu'à une reprise réussie.
        do {
            try effacerDonnees(dans: contexte)
            finaliserSuppressionLocale()
        } catch {
            erreurRepriseSuppression = error.localizedDescription
            throw error
        }
    }

    /// L'intention durable désigne l'UUID, mais le contexte reçu par une vue
    /// peut appartenir à l'ancien store. Avant et après chaque suspension, on
    /// exige donc aussi l'identité exacte du `mainContext` actuellement monté.
    /// Le cas sans UUID ne concerne que la migration d'une très ancienne phase
    /// locale, ouverte explicitement par `activerPourSuppression`.
    private func contexteSuppressionValide(
        _ contexte: ModelContext,
        compteAttendu: String?
    ) -> Bool {
        let stockage = StockageCompte.partage
        guard let contexteActif = stockage.conteneurActif?.mainContext,
              contexte === contexteActif else { return false }
        if let compteAttendu {
            guard let identifiant = UUID(uuidString: compteAttendu) else {
                return false
            }
            return stockage.identifiantActif == identifiant
        }
        return phaseSuppression == .locale && stockage.identifiantActif == nil
    }

    private func effacerDonnees(dans contexte: ModelContext) throws {
        do {
            try contexte.delete(model: Oeuvre.self)
            try contexte.delete(model: Exemplaire.self)
            try contexte.delete(model: Serie.self)
            try contexte.delete(model: Tome.self)
            try contexte.delete(model: SessionLecture.self)
            try contexte.delete(model: Citation.self)
            try contexte.delete(model: BadgeGagne.self)
            try contexte.delete(model: Collection.self)
            try contexte.delete(model: Objectif.self)
            try contexte.save()
            // Les photos de couvertures sont des données utilisateur au même
            // titre que la bibliothèque SwiftData : une suppression de compte
            // doit également les effacer du conteneur privé.
            try CouverturesPersonnelles.supprimerToutes()
        } catch {
            contexte.rollback()
            throw error
        }
    }

    private func oublier() {
        generationSession &+= 1
        tacheRenouvellement?.cancel()
        tacheRenouvellement = nil
        compteTacheRenouvellement = nil
        ticketTacheRenouvellement = nil
        identifiant = nil
        identifiantServeur = nil
        nom = nil
        email = nil
        defaults.removeObject(forKey: Cle.identifiant)
        defaults.removeObject(forKey: Cle.identifiantServeur)
        defaults.removeObject(forKey: Cle.nom)
        defaults.removeObject(forKey: Cle.email)
        defaults.removeObject(forKey: Cle.methode)
        Trousseau.effacer(Cle.jetonAcces)
        Trousseau.effacer(Cle.jetonRenouvellement)
        sessionVerifiee = false
    }

    /// Une seule rotation de refresh token a la fois pour un UUID donne. Les
    /// appels de lancement, de sauvegarde et de suppression partagent cette
    /// tache afin qu'une reponse plus ancienne ne remplace jamais les jetons
    /// issus d'une rotation plus recente.
    private func renouvelerSessionPartagee(
        compteAttendu: String,
        jeton: String
    ) async throws -> SupabaseAuth.Session {
        if let tacheRenouvellement,
           compteTacheRenouvellement == compteAttendu {
            return try await tacheRenouvellement.value
        }
        guard identifiantServeur == compteAttendu else {
            throw SupabaseAuth.Souci.sessionInvalide
        }

        tacheRenouvellement?.cancel()
        let ticket = UUID()
        let tache = Task {
            try await SupabaseAuth.rafraichir(jeton: jeton)
        }
        tacheRenouvellement = tache
        compteTacheRenouvellement = compteAttendu
        ticketTacheRenouvellement = ticket

        do {
            let session = try await tache.value
            if ticketTacheRenouvellement == ticket {
                tacheRenouvellement = nil
                compteTacheRenouvellement = nil
                ticketTacheRenouvellement = nil
            }
            return session
        } catch {
            if ticketTacheRenouvellement == ticket {
                tacheRenouvellement = nil
                compteTacheRenouvellement = nil
                ticketTacheRenouvellement = nil
            }
            throw error
        }
    }

    private func finaliserSuppressionLocale() {
        NotificationsService.annulerTousLesRappelsSortie()
        StockageCompte.partage.programmerPurgeApresSuppression()
        StockageCompte.partage.effacerPreferencesActives()
        oublier()
        let clesUtilisateur = [
            Cle.etat,
            "onboardingTermine", "apparence",
            "editionsLocalesV10", "catalogueCompletV11",
            "editionsVerifieesV49", "langueEditionsV1",
            "provenanceTomesV1",
            "roueUtilisee", "remiseGagnee", "honyaPlus",
            "murAccueil", "scansUtilises",
            Cle.phaseSuppression, Cle.ancienDrapeauSuppression,
            Cle.cleSuppression, Cle.cibleSuppressionServeur,
            Cle.cibleSuppressionIdentifiant, Cle.cibleSuppressionEmail,
            Cle.cibleSuppressionMethode, Cle.cibleSuppressionStockage,
        ]
        for cle in clesUtilisateur { defaults.removeObject(forKey: cle) }
        phaseSuppression = .aucune
        suppressionReconnexionRequise = false
        erreurRepriseSuppression = nil
        etat = .indetermine
        StockageCompte.partage.desactiver()
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

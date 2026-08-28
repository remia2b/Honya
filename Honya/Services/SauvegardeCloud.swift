import Foundation
import Observation
import SwiftData

/// Sauvegarde de compte v1 : un snapshot complet, versionne et controle par
/// revision dans Supabase. Ce n'est pas encore une fusion en temps reel : en
/// cas de divergence de deux appareils, le lecteur choisit explicitement la
/// copie a conserver.
@MainActor
@Observable
final class SauvegardeCloud {
    static let partage = SauvegardeCloud()

    enum Etat: Equatable {
        case inactive
        case synchronisation
        case aJour(Date)
        case restauree
        case conflit
        case erreur(String)
    }

    private(set) var etat: Etat = .inactive
    private(set) var operationEnCours = false

    private var identifiantCompte: UUID?
    private var operation = UUID()
    private var distanteEnConflit: SupabaseAuth.SauvegardeBibliothequeDistante?
    private var derniereTentative: Date?

    private let cleEmpreinte = "sauvegardeCloudEmpreinteV1"
    private let cleRevision = "sauvegardeCloudRevisionV1"

    private init() {}

    func desactiver() {
        operation = UUID()
        identifiantCompte = nil
        distanteEnConflit = nil
        derniereTentative = nil
        operationEnCours = false
        etat = .inactive
    }

    /// Compare la copie locale a la copie Supabase. Une absence distante cree
    /// la premiere sauvegarde ; un store local vide restaure automatiquement.
    /// Aucune copie non vide n'en ecrase une autre sans choix du lecteur.
    func synchroniser(
        compte identifiant: UUID,
        contexte: ModelContext,
        forcer: Bool = false
    ) async {
        guard porteeValide(identifiant, contexte: contexte),
              !operationEnCours else { return }
        if distanteEnConflit != nil { return }
        if !forcer, let derniereTentative,
           Date().timeIntervalSince(derniereTentative) < 60 {
            return
        }

        identifiantCompte = identifiant
        derniereTentative = Date()
        operationEnCours = true
        etat = .synchronisation
        let ticket = UUID()
        operation = ticket
        defer {
            if operation == ticket { operationEnCours = false }
        }

        do {
            let locale = try ExporteurBibliothequeSnapshotV1.exporter(depuis: contexte)
            let distante = try await lireDistante(compte: identifiant)
            guard porteeValide(
                identifiant,
                contexte: contexte,
                ticket: ticket
            ) else { return }

            guard let distante else {
                let creee = try await envoyer(
                    locale,
                    revisionAttendue: 0,
                    compte: identifiant
                )
                guard porteeValide(
                    identifiant,
                    contexte: contexte,
                    ticket: ticket
                ) else { return }
                memoriser(creee)
                etat = .aJour(Date())
                return
            }

            if locale.empreinteSHA256 == distante.empreinte {
                memoriser(distante)
                etat = .aJour(Date())
                return
            }

            let empreinteConnue = preferences?.string(forKey: cleEmpreinte)
            if empreinteConnue == distante.empreinte {
                // La copie distante est exactement notre dernier point de
                // depart : seules les donnees locales ont change.
                let envoyee = try await envoyer(
                    locale,
                    revisionAttendue: distante.revision,
                    compte: identifiant
                )
                guard porteeValide(
                    identifiant,
                    contexte: contexte,
                    ticket: ticket
                ) else { return }
                memoriser(envoyee)
                etat = .aJour(Date())
            } else if empreinteConnue == nil, snapshotLocalVide(locale.snapshot) {
                // Nouveau store / nouvelle installation : aucune base locale
                // n'a jamais ete synchronisee, la copie du compte est donc la
                // seule donnee utilisateur connue.
                _ = try RestaurateurBibliothequeSnapshotV1.restaurer(
                    snapshot: distante.contenu,
                    dans: contexte
                )
                guard porteeValide(
                    identifiant,
                    contexte: contexte,
                    ticket: ticket
                ) else { return }
                memoriser(distante)
                marquerOnboardingSiNecessaire(distante.contenu)
                etat = .restauree
                StockageCompte.partage.signalerRemplacementDesDonnees()
            } else {
                // Pas de base commune prouvable, ou le serveur a avance : le
                // choix est visible et volontaire.
                distanteEnConflit = distante
                etat = .conflit
            }
        } catch SupabaseAuth.Souci.conflitSauvegarde {
            await chargerConflitApresCourse(
                compte: identifiant,
                contexte: contexte,
                ticket: ticket
            )
        } catch {
            guard porteeValide(
                identifiant,
                contexte: contexte,
                ticket: ticket
            ) else { return }
            etat = .erreur(messageUtilisateur(error))
        }
    }

    /// Choix explicite : la copie locale devient la nouvelle revision cloud.
    func conserverCetAppareil(contexte: ModelContext) async {
        guard let identifiant = identifiantCompte,
              let distante = distanteEnConflit,
              porteeValide(identifiant, contexte: contexte),
              !operationEnCours else { return }
        operationEnCours = true
        // Le conflit doit rester l'ecran racine pendant l'envoi. Repasser en
        // `.synchronisation` remonterait l'application et autoriserait des
        // modifications concurrentes avant que le choix soit termine.
        etat = .conflit
        let ticket = UUID()
        operation = ticket
        defer {
            if operation == ticket { operationEnCours = false }
        }
        do {
            let locale = try ExporteurBibliothequeSnapshotV1.exporter(depuis: contexte)
            let envoyee = try await envoyer(
                locale,
                revisionAttendue: distante.revision,
                compte: identifiant
            )
            guard porteeValide(
                identifiant,
                contexte: contexte,
                ticket: ticket
            ) else { return }
            distanteEnConflit = nil
            memoriser(envoyee)
            etat = .aJour(Date())
        } catch SupabaseAuth.Souci.conflitSauvegarde {
            await chargerConflitApresCourse(
                compte: identifiant,
                contexte: contexte,
                ticket: ticket
            )
        } catch {
            guard porteeValide(
                identifiant,
                contexte: contexte,
                ticket: ticket
            ) else { return }
            etat = .erreur(messageUtilisateur(error))
        }
    }

    /// Choix explicite et confirme par l'interface : remplace atomiquement le
    /// store local par la revision distante deja validee et conservee en memoire.
    func restaurerLaSauvegarde(contexte: ModelContext) async {
        guard let identifiant = identifiantCompte,
              let distante = distanteEnConflit,
              porteeValide(identifiant, contexte: contexte),
              !operationEnCours else { return }
        operationEnCours = true
        // La restauration peut supprimer la copie locale. Garder l'ecran de
        // conflit bloque jusqu'au dernier controle de revision evite toute
        // modification locale pendant cette fenetre critique.
        etat = .conflit
        let ticket = UUID()
        operation = ticket
        defer {
            if operation == ticket { operationEnCours = false }
        }
        do {
            guard let actuelle = try await lireDistante(compte: identifiant) else {
                throw SupabaseAuth.Souci.message(
                    String(localized: "Réponse inattendue du serveur.")
                )
            }
            guard porteeValide(
                identifiant,
                contexte: contexte,
                ticket: ticket
            ) else { return }
            guard actuelle.revision == distante.revision,
                  actuelle.empreinte == distante.empreinte else {
                distanteEnConflit = actuelle
                etat = .conflit
                return
            }
            _ = try RestaurateurBibliothequeSnapshotV1.remplacer(
                snapshot: actuelle.contenu,
                dans: contexte
            )
            guard porteeValide(
                identifiant,
                contexte: contexte,
                ticket: ticket
            ) else { return }
            distanteEnConflit = nil
            memoriser(actuelle)
            marquerOnboardingSiNecessaire(actuelle.contenu)
            etat = .restauree
            StockageCompte.partage.signalerRemplacementDesDonnees()
        } catch {
            guard porteeValide(
                identifiant,
                contexte: contexte,
                ticket: ticket
            ) else { return }
            etat = .erreur(messageUtilisateur(error))
        }
    }

    func reessayer(compte: UUID, contexte: ModelContext) async {
        guard porteeValide(compte, contexte: contexte) else { return }
        if case .erreur = etat {
            distanteEnConflit = nil
            derniereTentative = nil
        }
        await synchroniser(compte: compte, contexte: contexte, forcer: true)
    }

    // MARK: - API authentifiee

    private func lireDistante(compte: UUID) async throws
        -> SupabaseAuth.SauvegardeBibliothequeDistante? {
        let jeton = try Compte.partage.jetonAccesPourAPI(compteAttendu: compte)
        do {
            return try await SupabaseAuth.lireSauvegardeBibliotheque(jeton: jeton)
        } catch SupabaseAuth.Souci.sessionInvalide {
            guard porteeValide(compte) else { throw CancellationError() }
            let renouvele = try await Compte.partage.renouvelerJetonPourAPI(
                compteAttendu: compte
            )
            guard porteeValide(compte) else { throw CancellationError() }
            return try await SupabaseAuth.lireSauvegardeBibliotheque(jeton: renouvele)
        }
    }

    private func envoyer(
        _ locale: ExporteurBibliothequeSnapshotV1.Resultat,
        revisionAttendue: Int64,
        compte: UUID
    ) async throws -> SupabaseAuth.SauvegardeBibliothequeDistante {
        let jeton = try Compte.partage.jetonAccesPourAPI(compteAttendu: compte)
        do {
            return try await SupabaseAuth.enregistrerSauvegardeBibliotheque(
                locale,
                revisionAttendue: revisionAttendue,
                jeton: jeton
            )
        } catch SupabaseAuth.Souci.sessionInvalide {
            guard porteeValide(compte) else { throw CancellationError() }
            let renouvele = try await Compte.partage.renouvelerJetonPourAPI(
                compteAttendu: compte
            )
            guard porteeValide(compte) else { throw CancellationError() }
            return try await SupabaseAuth.enregistrerSauvegardeBibliotheque(
                locale,
                revisionAttendue: revisionAttendue,
                jeton: renouvele
            )
        }
    }

    private func chargerConflitApresCourse(
        compte: UUID,
        contexte: ModelContext,
        ticket: UUID
    ) async {
        do {
            let distante = try await lireDistante(compte: compte)
            guard porteeValide(
                compte,
                contexte: contexte,
                ticket: ticket
            ) else { return }
            distanteEnConflit = distante
            etat = distante == nil
                ? .erreur(String(localized: "Réponse inattendue du serveur."))
                : .conflit
        } catch {
            guard porteeValide(
                compte,
                contexte: contexte,
                ticket: ticket
            ) else { return }
            etat = .erreur(messageUtilisateur(error))
        }
    }

    // MARK: - Etat local

    /// Les erreurs de structure servent au diagnostic, mais leurs noms de
    /// relations et UUID ne doivent jamais arriver tels quels dans une autre
    /// langue. Les restaurateurs font rollback avant de les propager : ce
    /// message peut donc garantir que la copie locale est restee intacte.
    private func messageUtilisateur(_ error: Error) -> String {
        if error is RestaurateurBibliothequeSnapshotV1.Erreur
            || error is ErreurBibliothequeSnapshotV1
            || error is IdentifiantsCloud.Erreur {
            return String(localized:
                "La sauvegarde n'a pas pu être terminée. Votre bibliothèque locale est intacte."
            )
        }
        return error.localizedDescription
    }

    private var preferences: UserDefaults? {
        StockageCompte.partage.preferencesActives
    }

    private func memoriser(_ distante: SupabaseAuth.SauvegardeBibliothequeDistante) {
        preferences?.set(distante.empreinte, forKey: cleEmpreinte)
        preferences?.set(distante.revision, forKey: cleRevision)
    }

    private func marquerOnboardingSiNecessaire(_ snapshot: BibliothequeSnapshotV1) {
        if !snapshotLocalVide(snapshot) {
            preferences?.set(true, forKey: "onboardingTermine")
        }
    }

    private func snapshotLocalVide(_ snapshot: BibliothequeSnapshotV1) -> Bool {
        guard snapshot.oeuvres.isEmpty,
              snapshot.exemplaires.isEmpty,
              snapshot.series.isEmpty,
              snapshot.tomes.isEmpty,
              snapshot.sessions.isEmpty,
              snapshot.citations.isEmpty,
              snapshot.collections.isEmpty,
              snapshot.badges.isEmpty,
              snapshot.objectifs.count <= 1
        else { return false }
        guard let objectif = snapshot.objectifs.first else { return true }
        return objectif.minutesParJour == 20
            && objectif.defiAnnuelLivres == 26
            && objectif.languesLecture.isEmpty
            && objectif.typesPreferes == [
                TypeOeuvre.livre.rawValue,
                TypeOeuvre.manga.rawValue,
            ]
            && objectif.emprunteursRecents.isEmpty
    }

    private func porteeValide(_ identifiant: UUID, ticket: UUID? = nil) -> Bool {
        if let ticket, operation != ticket { return false }
        guard StockageCompte.partage.identifiantActif == identifiant,
              Compte.partage.etat == .connecte,
              Compte.partage.identifiantServeur.flatMap(UUID.init(uuidString:)) == identifiant
        else { return false }
        return true
    }

    /// Un UUID identique ne suffit pas : une vue conserve parfois l'ancien
    /// `ModelContext` pendant que la racine remonte le store du compte. Toute
    /// lecture, restauration ou sauvegarde doit viser le contexte actuellement
    /// publié par `StockageCompte`, sinon l'opération s'annule sans effet.
    private func porteeValide(
        _ identifiant: UUID,
        contexte: ModelContext,
        ticket: UUID? = nil
    ) -> Bool {
        guard porteeValide(identifiant, ticket: ticket),
              let contexteActif = StockageCompte.partage
                .conteneurActif?.mainContext
        else { return false }
        return contexte === contexteActif
    }
}

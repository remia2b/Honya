import Foundation
import Observation
import StoreKit

/// Les abonnements Honya+, tels que l'App Store les connaît.
///
/// Aucun prix n'est écrit ici. Ils viennent tous de l'App Store, dans la
/// monnaie et la langue du lecteur — un tarif codé dans l'application serait
/// faux dès le deuxième pays, et illégal dans plusieurs.
///
/// Tant que les articles n'existent pas dans App Store Connect, `articles`
/// reste vide et l'achat est indisponible. Aucun tarif ni droit de secours
/// n'est inventé localement.
@Observable
@MainActor
final class Boutique {
    static let partage = Boutique()

    /// Ce que l'on vend.
    ///
    /// La remise de la roue n'est pas un rabais appliqué à l'abonnement
    /// annuel : c'est un abonnement distinct, moins cher, placé dans le même
    /// groupe. C'est la seule façon d'afficher un prix réduit sans serveur de
    /// signature, et le groupe interdit de cumuler les deux.
    enum Formule: String, CaseIterable, Identifiable {
        case mensuel      = "app.honya.plus.mensuel"
        case annuel       = "app.honya.plus.annuel"
        case vie          = "app.honya.plus.vie"
        case annuelRemise = "app.honya.plus.annuel.remise"

        var id: String { rawValue }

        /// La remise ne se montre qu'à qui l'a gagnée.
        static var auCatalogue: [Formule] { [.mensuel, .annuel, .vie] }

        var nom: String {
            switch self {
            case .mensuel: return String(localized: "Mensuel")
            case .annuel, .annuelRemise: return String(localized: "Annuel")
            case .vie: return String(localized: "À vie")
            }
        }

        var detail: String {
            switch self {
            case .mensuel: return String(localized: "sans engagement")
            case .annuel: return String(localized: "l'année entière")
            case .annuelRemise: return String(localized: "votre remise appliquée")
            case .vie: return String(localized: "une seule fois")
            }
        }
    }

    /// Les articles chargés depuis l'App Store, vides tant qu'ils n'existent
    /// pas encore côté Apple.
    private(set) var articles: [Formule: Product] = [:]
    /// L'abonnement est-il actif — la seule question qui compte pour les vues.
    private(set) var abonne = false
    /// Formule réellement reconnue par Apple, distincte du simple booléen :
    /// un achat à vie n'est pas un abonnement à gérer dans Réglages.
    private(set) var formuleActive: Formule?
    private(set) var expiration: Date?
    private(set) var droitsVerifies = false
    private(set) var chargement = true
    private(set) var achatEnCours: Formule?
    private(set) var restaurationEnCours = false
    private(set) var formulesAvecEssai: Set<Formule> = []
    private(set) var souci: String?

    var operationEnCours: Bool { achatEnCours != nil || restaurationEnCours }
    var achatAVie: Bool { abonne && formuleActive == .vie }
    var abonnementRenouvelableActif: Bool {
        abonne && formuleActive != nil && formuleActive != .vie
    }

    /// Une veille qui tourne pour toute la durée de vie de l'application —
    /// elle n'est jamais annulée, la boutique étant un partagé unique.
    ///
    /// Un achat peut aboutir hors de l'écran d'abonnement — validation
    /// parentale accordée plus tard, achat commencé sur un autre appareil,
    /// renouvellement. Sans cette veille, l'application ne l'apprendrait
    /// qu'au prochain lancement.
    private var veille: Task<Void, Never>?
    private var veilleExpiration: Task<Void, Never>?

    private init() {
        veille = Task { [weak self] in
            for await resultat in Transaction.updates {
                guard let transaction = try? Self.verifier(resultat) else { continue }
                await transaction.finish()
                await self?.relireLesDroits()
            }
        }
        Task {
            await charger()
            await relireLesDroits()
        }
    }

    // MARK: - Le catalogue

    func charger() async {
        chargement = true
        defer { chargement = false }
        do {
            let trouves = try await Product.products(for: Formule.allCases.map(\.rawValue))
            var table: [Formule: Product] = [:]
            for article in trouves {
                if let formule = Formule(rawValue: article.id) { table[formule] = article }
            }
            articles = table
            var essais: Set<Formule> = []
            for (formule, article) in table {
                guard let abonnement = article.subscription,
                      abonnement.introductoryOffer != nil,
                      await abonnement.isEligibleForIntroOffer
                else { continue }
                essais.insert(formule)
            }
            formulesAvecEssai = essais
            souci = nil
        } catch {
            // Pas de message rouge pour autant : sans réseau, l'écran garde
            // son affichage d'attente. Une erreur ne s'affiche que si le
            // lecteur tente réellement d'acheter.
            articles = [:]
        }
    }

    // MARK: - L'achat

    /// - Returns: vrai si l'abonnement est actif au retour.
    @discardableResult
    func acheter(_ formule: Formule) async -> Bool {
        // Défense centrale : achat et restauration sont une seule file. Le
        // MainActor réserve l'opération avant le premier `await`, donc deux
        // taps rapides ne peuvent pas ouvrir deux feuilles StoreKit.
        guard !operationEnCours else { return false }
        achatEnCours = formule
        defer { achatEnCours = nil }

        if !droitsVerifies { await relireLesDroits() }
        guard !abonne else {
            souci = nil
            return true
        }
        guard let article = articles[formule] else {
            souci = String(localized: "Cette offre n'est pas disponible pour le moment.")
            return false
        }
        souci = nil

        do {
            switch try await article.purchase() {
            case .success(let resultat):
                let transaction = try Self.verifier(resultat)
                await transaction.finish()
                await relireLesDroits()
                return abonne

            case .pending:
                // Un achat en attente d'accord parental : ce n'est pas un
                // échec, et la veille le rattrapera quand il aboutira.
                souci = String(localized: "Votre achat attend une validation. Il s'activera tout seul.")
                return false

            case .userCancelled:
                return false

            @unknown default:
                return false
            }
        } catch {
            souci = error.localizedDescription
            return false
        }
    }

    /// Rendre à un lecteur ce qu'il a déjà payé — sur un nouvel appareil, ou
    /// après une réinstallation. Obligatoire : l'App Store refuse une
    /// application qui vend un abonnement sans offrir de le restaurer.
    func restaurer() async {
        guard !operationEnCours else { return }
        souci = nil
        restaurationEnCours = true
        defer { restaurationEnCours = false }
        do {
            try await AppStore.sync()
            await relireLesDroits()
            if !abonne {
                souci = String(localized: "Aucun achat à restaurer sur ce compte.")
            }
        } catch {
            souci = error.localizedDescription
        }
    }

    // MARK: - Les droits

    /// L'unique source de vérité : ce qu'Apple reconnaît à ce compte, ici et
    /// maintenant. On ne retient jamais « il a acheté » dans un fichier local
    /// — un abonnement expire, se rembourse, se résilie.
    func relireLesDroits() async {
        var formuleTrouvee: Formule?
        var expirationTrouvee: Date?
        let maintenant = Date()
        for await resultat in Transaction.currentEntitlements {
            guard let transaction = try? Self.verifier(resultat) else { continue }
            guard let formule = Formule(rawValue: transaction.productID),
                  transaction.revocationDate == nil
            else { continue }
            if let expiration = transaction.expirationDate,
               expiration <= maintenant { continue }

            // Le non-consommable à vie prime sur une ancienne souscription.
            if formule == .vie
                || formuleTrouvee == nil
                || (formuleTrouvee != .vie
                    && (transaction.expirationDate ?? .distantPast)
                        > (expirationTrouvee ?? .distantPast)) {
                formuleTrouvee = formule
                expirationTrouvee = transaction.expirationDate
            }
        }
        let actif = formuleTrouvee != nil
        formuleActive = formuleTrouvee
        expiration = expirationTrouvee
        abonne = actif
        Droits.partage.appliquer(plus: actif)
        droitsVerifies = true
        programmerRelecture(a: expirationTrouvee)
    }

    private func programmerRelecture(a date: Date?) {
        veilleExpiration?.cancel()
        guard let date, date > Date() else {
            veilleExpiration = nil
            return
        }
        veilleExpiration = Task { [weak self] in
            let attente = max(1, date.timeIntervalSinceNow + 1)
            try? await Task.sleep(for: .seconds(attente))
            guard !Task.isCancelled else { return }
            await self?.relireLesDroits()
        }
    }

    /// Une transaction non signée par Apple n'existe pas.
    private static func verifier<T>(_ resultat: VerificationResult<T>) throws -> T {
        switch resultat {
        case .verified(let valeur): return valeur
        case .unverified: throw ErreurBoutique.signatureInvalide
        }
    }

    enum ErreurBoutique: LocalizedError {
        case signatureInvalide

        var errorDescription: String? {
            String(localized: "Cet achat n'a pas pu être vérifié auprès de l'App Store.")
        }
    }

    // MARK: - Ancienne remise de test

    private static let cleRemise = "remiseGagnee"

    /// Conservé uniquement pour que les anciens aperçus restent lisibles.
    /// Une promotion App Store doit être configurée par Apple et ne peut pas
    /// être accordée par un simple booléen local dans le parcours de vente.
    var remiseGagnee: Bool {
        UserDefaults.standard.bool(forKey: Self.cleRemise)
    }

    func accorderLaRemise() {
        UserDefaults.standard.set(true, forKey: Self.cleRemise)
    }

    // MARK: - Les montants affichés

    func prix(_ formule: Formule) -> String {
        articles[formule]?.displayPrice ?? "—"
    }

    /// Durée localisée d'un éventuel essai réellement offert et éligible.
    func dureeEssai(_ formule: Formule) -> String? {
        guard formulesAvecEssai.contains(formule),
              let offre = articles[formule]?.subscription?.introductoryOffer,
              offre.paymentMode == .freeTrial else { return nil }

        let valeur = offre.period.value * offre.periodCount
        var composants = DateComponents()
        let unite: NSCalendar.Unit
        switch offre.period.unit {
        case .day:
            composants.day = valeur
            unite = .day
        case .week:
            composants.weekOfMonth = valeur
            unite = .weekOfMonth
        case .month:
            composants.month = valeur
            unite = .month
        case .year:
            composants.year = valeur
            unite = .year
        @unknown default:
            return nil
        }
        let format = DateComponentsFormatter()
        format.allowedUnits = unite
        format.unitsStyle = .full
        format.maximumUnitCount = 1
        return format.string(from: composants)
    }

    /// La remise réelle, en pourcentage entier, déduite des deux prix.
    ///
    /// Elle n'est pas écrite en dur : le jour où le tarif réduit change dans
    /// App Store Connect, la roue et l'écran de gain suivent d'eux-mêmes. Deux
    /// chiffres qui se contredisent sur un écran de vente, c'est une plainte.
    var pourcentageRemise: Int {
        guard let plein = articles[.annuel]?.price,
              let reduit = articles[.annuelRemise]?.price,
              plein > 0 else { return 0 }
        let taux = (plein - reduit) / plein * 100
        return Int(NSDecimalNumber(decimal: taux).doubleValue.rounded())
    }

    /// La promotion issue de l'ancienne roue n'entre plus dans le parcours
    /// d'achat. Les offres visibles sont exclusivement les produits publics.
    var formulesVisibles: [Formule] {
        Formule.auCatalogue
    }
}

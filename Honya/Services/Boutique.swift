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
/// reste vide : l'écran Honya+ le voit et retombe sur son affichage
/// d'attente. Rien ne casse, rien ne ment.
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
    private(set) var chargement = true
    private(set) var achatEnCours: Formule?
    private(set) var souci: String?

    /// Une veille qui tourne pour toute la durée de vie de l'application —
    /// elle n'est jamais annulée, la boutique étant un partagé unique.
    ///
    /// Un achat peut aboutir hors de l'écran d'abonnement — validation
    /// parentale accordée plus tard, achat commencé sur un autre appareil,
    /// renouvellement. Sans cette veille, l'application ne l'apprendrait
    /// qu'au prochain lancement.
    private var veille: Task<Void, Never>?

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
        guard let article = articles[formule] else {
            souci = String(localized: "Cette offre n'est pas disponible pour le moment.")
            return false
        }
        souci = nil
        achatEnCours = formule
        defer { achatEnCours = nil }

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
        souci = nil
        achatEnCours = nil
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
        var actif = false
        for await resultat in Transaction.currentEntitlements {
            guard let transaction = try? Self.verifier(resultat) else { continue }
            guard Formule(rawValue: transaction.productID) != nil else { continue }
            if transaction.revocationDate == nil { actif = true }
        }
        abonne = actif
        Droits.partage.appliquer(plus: actif)
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

    // MARK: - La remise de la roue

    private static let cleRemise = "remiseGagnee"

    /// La roue a-t-elle été gagnée — donc le tarif réduit doit-il s'afficher.
    var remiseGagnee: Bool {
        UserDefaults.standard.bool(forKey: Self.cleRemise)
    }

    func accorderLaRemise() {
        UserDefaults.standard.set(true, forKey: Self.cleRemise)
    }

    // MARK: - Les montants affichés hors de l'écran d'abonnement

    /// Les tarifs d'attente, le temps que les articles existent dans App Store
    /// Connect. Ils ne servent qu'aux versions de test : dès que l'App Store
    /// répond, ce sont ses prix qui s'affichent, dans la monnaie du lecteur.
    private static let prixDAttente: [Formule: String] = [
        .mensuel: "4,99 €", .annuel: "29,99 €",
        .annuelRemise: "17,99 €", .vie: "69,99 €",
    ]

    func prix(_ formule: Formule) -> String {
        articles[formule]?.displayPrice ?? Self.prixDAttente[formule] ?? ""
    }

    /// La remise réelle, en pourcentage entier, déduite des deux prix.
    ///
    /// Elle n'est pas écrite en dur : le jour où le tarif réduit change dans
    /// App Store Connect, la roue et l'écran de gain suivent d'eux-mêmes. Deux
    /// chiffres qui se contredisent sur un écran de vente, c'est une plainte.
    var pourcentageRemise: Int {
        guard let plein = articles[.annuel]?.price,
              let reduit = articles[.annuelRemise]?.price,
              plein > 0 else { return 40 }
        let taux = (plein - reduit) / plein * 100
        return Int(NSDecimalNumber(decimal: taux).doubleValue.rounded())
    }

    /// Les formules à montrer, remise comprise si elle a été gagnée. Si le
    /// tarif réduit n'existe pas encore côté App Store, l'annuel plein reste
    /// en place : jamais de trou dans la liste.
    var formulesVisibles: [Formule] {
        guard remiseGagnee, articles[.annuelRemise] != nil else { return Formule.auCatalogue }
        return [.mensuel, .annuelRemise, .vie]
    }
}

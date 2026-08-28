import Foundation
import Observation
import SwiftUI

/// Où s'arrête le gratuit.
///
/// Un seul endroit pour tous les seuils : les ajuster après le lancement doit
/// être une ligne à changer, pas une chasse dans dix fichiers.
///
/// Principe de découpe : on ne taxe jamais le geste — lire, ranger à la main,
/// terminer un livre — mais l'automatisation et la mémoire longue se paient.
enum Limites {
    /// Plafond gratuit de la bibliothèque ; les éléments existants restent
    /// toujours consultables quand il est atteint.
    static let tomes = 200
    /// Rayons dont toute la continuation est utilisable automatiquement.
    static let seriesCompletes = 3
    /// Sur un rayon qui dépasse les trois séries offertes, une première rangée
    /// reste réellement utilisable. Les volumes suivants sont visibles et
    /// consultables, mais leur rangement automatique demande Honya+.
    static let tomesApercuSerie = 3
    /// De quoi essayer le scan sur une vraie pile de livres avant Honya+.
    static let scans = 10
    static let etageres = 2
    static let citations = 5
    static let alertesSortie = 1
    /// Les sessions ne sont jamais coupées ; c'est leur mémoire qui est courte.
    static let joursHistorique = 7

    /// Combien il en reste avant le mur, pour les compteurs affichés.
    static func reste(_ utilises: Int, sur plafond: Int) -> Int {
        max(0, plafond - utilises)
    }
}

// MARK: - Le compteur de scans

/// Le seul quota qui ne se déduit pas des données : on compte les ISBN
/// effectivement reconnus par la caméra. Une recherche sans résultat ou déjà
/// présente dans le lot rend son crédit, et la saisie d'un ISBN au clavier
/// reste gratuite.
@Observable
@MainActor
final class CompteurScans {
    static let partage = CompteurScans()

    /// Identifie le débit précis à rendre. La génération empêche une recherche
    /// encore en vol de rembourser le compteur d'un autre compte après une
    /// déconnexion/reconnexion.
    struct Debit: Sendable {
        fileprivate let identifiant: UUID?
        fileprivate let generation: UUID
    }

    private(set) var utilises: Int
    private var preferences: UserDefaults?
    private var generation = UUID()
    private var debitsEnCours: Set<UUID> = []

    private init() {
        utilises = 0
    }

    func activer(preferences: UserDefaults?) {
        self.preferences = preferences
        generation = UUID()
        debitsEnCours.removeAll()
        utilises = preferences?.integer(forKey: "scansUtilises") ?? 0
    }

    var reste: Int { Limites.reste(utilises, sur: Limites.scans) }
    var autorise: Bool { Droits.partage.plus || reste > 0 }

    @discardableResult
    func enregistrer() -> Debit {
        guard !Droits.partage.plus else {
            return Debit(identifiant: nil, generation: generation)
        }
        let identifiant = UUID()
        debitsEnCours.insert(identifiant)
        utilises += 1
        preferences?.set(utilises, forKey: "scansUtilises")
        return Debit(identifiant: identifiant, generation: generation)
    }

    func confirmer(_ debit: Debit) {
        guard debit.generation == generation,
              let identifiant = debit.identifiant else { return }
        debitsEnCours.remove(identifiant)
    }

    func rembourser(_ debit: Debit) {
        guard debit.generation == generation,
              let identifiant = debit.identifiant,
              debitsEnCours.remove(identifiant) != nil,
              utilises > 0 else { return }
        utilises -= 1
        preferences?.set(utilises, forKey: "scansUtilises")
    }
}

// MARK: - Présenter Honya+ depuis n'importe quel verrou

extension View {
    /// Ouvre l'écran Honya+ quand `visible` passe à vrai. Le même écran partout :
    /// une seule vue à faire évoluer quand StoreKit arrivera.
    func ecranHonyaPlus(_ visible: Binding<Bool>, verrou: Verrou? = nil) -> some View {
        sheet(isPresented: visible) { HonyaPlusView(verrou: verrou) }
    }
}

// MARK: - Le compteur discret sous un bouton

/// « 3 sur 5 » — visible avant le mur, jamais après. Montrer le compteur dès le
/// premier usage évite que la limite ne soit une mauvaise surprise.
struct CompteurLimite: View {
    let utilises: Int
    let plafond: Int

    var body: some View {
        if !Droits.partage.plus {
            Text("\(utilises) sur \(plafond)")
                .font(.caption2.weight(.medium))
                .foregroundStyle(
                    // Le ternaire force les deux branches au même type : .tertiary
                    // est un ShapeStyle, pas une Color.
                    utilises >= plafond
                        ? AnyShapeStyle(Couleurs.accent)
                        : AnyShapeStyle(.tertiary)
                )
        }
    }
}

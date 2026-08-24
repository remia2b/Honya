import Foundation
import SwiftUI

/// Où s'arrête le gratuit.
///
/// Un seul endroit pour tous les seuils : les ajuster après le lancement doit
/// être une ligne à changer, pas une chasse dans dix fichiers.
///
/// Principe de découpe : on ne taxe jamais le geste — lire, ranger à la main,
/// terminer un livre — mais l'automatisation et la mémoire longue se paient.
enum Limites {
    /// Vingt fois le plafond de Bookly : un chiffre qu'on affiche fièrement.
    static let tomes = 200
    /// Rayons remplis automatiquement. Au-delà, on ajoute tome par tome.
    static let seriesCompletes = 3
    /// De quoi comprendre que le scan est magique.
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

/// Le seul quota qui ne se déduit pas des données : on compte les scans faits.
@Observable
@MainActor
final class CompteurScans {
    static let partage = CompteurScans()

    private(set) var utilises: Int

    private init() {
        utilises = UserDefaults.standard.integer(forKey: "scansUtilises")
    }

    var reste: Int { Limites.reste(utilises, sur: Limites.scans) }

    var autorise: Bool { Droits.partage.plus || reste > 0 }

    func enregistrer() {
        guard !Droits.partage.plus else { return }
        utilises += 1
        UserDefaults.standard.set(utilises, forKey: "scansUtilises")
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

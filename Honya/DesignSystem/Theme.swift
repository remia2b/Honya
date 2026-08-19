import SwiftUI

// MARK: - Couleurs Honya
// Papier & encre = couleurs système (elles suivent le mode sombre).
// L'accent (« orange Books ») vient du catalogue d'assets : #E05E00 clair / #FF9E45 sombre.

enum Couleurs {
    static let accent = Color.accentColor

    static let lu = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.357, green: 0.780, blue: 0.467, alpha: 1)   // #5BC777
            : UIColor(red: 0.118, green: 0.494, blue: 0.243, alpha: 1)   // #1E7E3E
    })

    static let aLire = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.435, green: 0.698, blue: 1.000, alpha: 1)   // #6FB2FF
            : UIColor(red: 0.039, green: 0.400, blue: 0.761, alpha: 1)   // #0A66C2
    })

    static let wishlist = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.898, green: 0.514, blue: 0.706, alpha: 1)   // #E583B4
            : UIColor(red: 0.706, green: 0.271, blue: 0.494, alpha: 1)   // #B4457E
    })

    static let abandonne = Color.secondary
}

extension StatutLecture {
    var couleur: Color {
        switch self {
        case .aLire: return Couleurs.aLire
        case .enCours: return Couleurs.accent
        case .lu: return Couleurs.lu
        case .abandonne: return Couleurs.abandonne
        case .wishlist: return Couleurs.wishlist
        }
    }

    var symbole: String {
        switch self {
        case .aLire: return "book.closed"
        case .enCours: return "book"
        case .lu: return "checkmark.circle.fill"
        case .abandonne: return "xmark.circle"
        case .wishlist: return "heart"
        }
    }
}

// MARK: - Typographie
// Deux voix, comme Apple Books : le serif (New York) pour les titres d'écrans,
// les titres d'œuvres et les grands chiffres ; SF Pro pour l'interface.

extension Font {
    /// Grand titre d'écran, à la Apple Books.
    static var titreEcran: Font { .system(size: 30, weight: .semibold, design: .serif) }

    /// Titre d'œuvre.
    static func titreOeuvre(_ taille: CGFloat = 20) -> Font {
        .system(size: taille, weight: .semibold, design: .serif)
    }

    /// Grands chiffres (objectif, stats).
    static func chiffreSerif(_ taille: CGFloat) -> Font {
        .system(size: taille, weight: .medium, design: .serif)
    }
}

// MARK: - En-tête d'écran serif réutilisable

struct EnteteEcran<Accessoire: View>: View {
    let titre: LocalizedStringKey
    var sousTitre: String?
    @ViewBuilder var accessoire: Accessoire

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                if let sousTitre {
                    Text(sousTitre)
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                }
                Text(titre)
                    .font(.titreEcran)
            }
            Spacer()
            accessoire
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }
}

extension EnteteEcran where Accessoire == EmptyView {
    init(titre: LocalizedStringKey, sousTitre: String? = nil) {
        self.titre = titre
        self.sousTitre = sousTitre
        self.accessoire = EmptyView()
    }
}

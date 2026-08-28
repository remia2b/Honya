import SwiftUI

/// Ce qui a fait apparaître l'écran Honya+.
///
/// L'écran ne vend jamais « l'abonnement » en général : il vend la chose
/// exacte qui manque à cette seconde, avec les livres concernés sous les yeux.
/// Un lecteur bloqué sur sa 4ᵉ série voit SA série, pas une illustration.
struct Verrou {
    var titre: LocalizedStringKey
    /// Déjà traduit et interpolé par l'appelant : il contient des noms d'œuvres.
    var detail: String
    /// Les couvertures à montrer. Vide → on retombe sur le symbole.
    var couvertures: [String] = []
    var symbole: String = "lock.fill"

    // MARK: - Les verrous de Honya

    static func serie(nom: String, tomes: Int, couvertures: [String]) -> Verrou {
        Verrou(
            titre: "Votre 4ᵉ série",
            detail: String(localized: "Honya peut poser les \(tomes) tomes de « \(nom) » à votre place, dates de sortie comprises. Comme il l'a fait pour les trois précédentes."),
            couvertures: couvertures,
            symbole: "books.vertical.fill"
        )
    }

    static func scan(couvertures: [String] = []) -> Verrou {
        Verrou(
            titre: "Vos dix scans sont passés",
            detail: String(localized: "Le code-barres remplit tout : titre, couverture, pages, en une seconde. La recherche à la main, elle, reste toujours gratuite."),
            couvertures: couvertures,
            symbole: "barcode.viewfinder"
        )
    }

    static func etagere(couvertures: [String] = []) -> Verrou {
        Verrou(
            titre: "Une troisième étagère",
            detail: String(localized: "Vos deux étagères sont pleines. Honya+ les libère toutes, pour ranger vos livres exactement comme vous le voulez."),
            couvertures: couvertures,
            symbole: "square.grid.2x2.fill"
        )
    }

    static func citation(couvertures: [String] = []) -> Verrou {
        Verrou(
            titre: "Vos phrases méritent mieux",
            detail: String(localized: "Cinq citations gardées, et celles-ci restent à vous pour toujours. Honya+ enlève le compteur."),
            couvertures: couvertures,
            symbole: "quote.opening"
        )
    }

    static func alerte(nom: String, couvertures: [String] = []) -> Verrou {
        Verrou(
            titre: "Être prévenu pour toutes vos séries",
            detail: String(localized: "Honya suit déjà une série pour vous. Avec Honya+, il vous prévient à chaque nouveau tome de « \(nom) » — et de toutes les autres."),
            couvertures: couvertures,
            symbole: "bell.badge.fill"
        )
    }

    static func pret(titre livre: String, couvertures: [String] = []) -> Verrou {
        Verrou(
            titre: "Se souvenir de vos prêts",
            detail: String(localized: "À qui vous avez confié « \(livre) », et depuis quand. Le livre part sur l'étagère « Prêtés » jusqu'à son retour."),
            couvertures: couvertures,
            symbole: "person.badge.clock.fill"
        )
    }

    static func statistiques(couvertures: [String] = []) -> Verrou {
        Verrou(
            titre: "Vos semaines passées vous attendent",
            detail: String(localized: "Vos statistiques sur tout l'historique"),
            couvertures: couvertures,
            symbole: "chart.bar.fill"
        )
    }

    static func bibliotheque(couvertures: [String] = []) -> Verrou {
        Verrou(
            titre: "Votre collection dépasse le gratuit",
            detail: String(localized: "Deux cents tomes rangés — vingt fois ce qu'offrent les autres. Honya+ enlève le plafond ; tout ce qui est déjà là reste accessible."),
            couvertures: couvertures,
            symbole: "books.vertical.fill"
        )
    }
}

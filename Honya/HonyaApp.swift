import SwiftUI
import SwiftData

@main
struct HonyaApp: App {
    let conteneur: ModelContainer

    @AppStorage("onboardingTermine") private var onboardingTermine = false

    init() {
        let schema = Schema([
            Oeuvre.self, Exemplaire.self,
            Serie.self, Tome.self,
            SessionLecture.self, Citation.self,
            Objectif.self, BadgeGagne.self, Collection.self,
        ])
        // Stockage local. Pour activer la sync iCloud plus tard :
        // ModelConfiguration(schema: schema, cloudKitDatabase: .automatic) + capability iCloud/CloudKit.
        let configuration = ModelConfiguration(schema: schema)
        do {
            conteneur = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Impossible d'ouvrir la base Honya : \(error)")
        }
        // Cache réseau généreux : les couvertures passent par URLSession.
        URLCache.shared = URLCache(memoryCapacity: 40_000_000, diskCapacity: 400_000_000)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if onboardingTermine {
                    RacineView()
                } else {
                    OnboardingView()
                }
            }
        }
        .modelContainer(conteneur)
    }
}

// MARK: - Aperçus : conteneur en mémoire + petites données de démo

@MainActor
enum Apercu {
    static let conteneur: ModelContainer = {
        let schema = Schema([
            Oeuvre.self, Exemplaire.self, Serie.self, Tome.self,
            SessionLecture.self, Citation.self, Objectif.self, BadgeGagne.self, Collection.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let conteneur = try! ModelContainer(for: schema, configurations: [config])
        peupler(conteneur.mainContext)
        return conteneur
    }()

    static func peupler(_ contexte: ModelContext) {
        let dune = Oeuvre(titreOriginal: "Dune", auteurs: ["Frank Herbert"], type: .livre)
        dune.titres = ["fr": "Dune", "en": "Dune"]
        dune.pages = 412
        dune.genres = ["Science-fiction"]
        dune.anneePublication = 1965
        let exDune = Exemplaire(statut: .enCours)
        exDune.pageCourante = 264
        exDune.dateDebut = Calendar.current.date(byAdding: .day, value: -12, to: .now)
        dune.exemplaire = exDune
        contexte.insert(dune)

        let vents = Oeuvre(titreOriginal: "The Name of the Wind", auteurs: ["Patrick Rothfuss"], type: .livre)
        vents.titres = ["fr": "Le Nom du vent", "en": "The Name of the Wind"]
        vents.pages = 662
        vents.genres = ["Fantasy"]
        let exVents = Exemplaire(statut: .aLire)
        exVents.aSuivre = true
        vents.exemplaire = exVents
        contexte.insert(vents)

        let vinland = Serie(nom: "Vinland Saga", type: .manga)
        vinland.auteur = "Makoto Yukimura"
        vinland.tomesTotal = 27
        vinland.statutParution = .enCours
        vinland.genres = ["Manga", "Historique"]
        vinland.chapitresLus = 218
        vinland.prochaineSortieNumero = 28
        vinland.prochaineSortieDate = Calendar.current.date(byAdding: .month, value: 2, to: .now)
        for n in 1...27 {
            let tome = Tome(numero: n, possede: n <= 21, lu: n <= 18)
            if tome.lu { tome.dateLu = Calendar.current.date(byAdding: .day, value: -n, to: .now) }
            vinland.tomes.append(tome)
        }
        contexte.insert(vinland)

        for jours in 0..<9 {
            let session = SessionLecture(
                debut: Calendar.current.date(byAdding: .day, value: -jours, to: .now)!,
                dureeSecondes: [1450, 2600, 900, 3100, 1200, 2000, 600, 1800, 2400][jours],
                pagesLues: [18, 32, 10, 41, 15, 25, 8, 22, 30][jours]
            )
            session.oeuvre = dune
            contexte.insert(session)
        }
    }
}

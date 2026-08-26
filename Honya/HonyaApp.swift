import SwiftUI
import SwiftData

@main
struct HonyaApp: App {
    let conteneur: ModelContainer

    @AppStorage("onboardingTermine") private var onboardingTermine = false
    @AppStorage("apparence") private var apparence: ApparenceHonya = .systeme
    @State private var compte = Compte.partage

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

    /// Écran demandé en ligne de commande, pour photographier l'application
    /// sur simulateur sans avoir à naviguer. Jamais compilé en production.
    private var ecranDemande: String? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let position = arguments.firstIndex(of: "--ecran"),
              arguments.indices.contains(position + 1)
        else { return nil }
        return arguments[position + 1]
        #else
        return nil
        #endif
    }

    @ViewBuilder
    private func ecranDeCapture(_ nom: String) -> some View {
        switch nom {
        case "honyaPlus":
            HonyaPlusView()
        case "verrou", "verrouSerie":
            HonyaPlusView(verrou: .serie(
                nom: "Chainsaw Man", tomes: 27, couvertures: Apercu.couvertures
            ))
        case "verrouScan":
            HonyaPlusView(verrou: .scan(couvertures: Apercu.couvertures))
        case "verrouEtagere":
            HonyaPlusView(verrou: .etagere(couvertures: Apercu.couvertures))
        case "verrouCitation":
            HonyaPlusView(verrou: .citation(couvertures: Apercu.couvertures))
        case "verrouAlerte":
            HonyaPlusView(verrou: .alerte(nom: "One Piece", couvertures: Apercu.couvertures))
        case "verrouPret":
            HonyaPlusView(verrou: .pret(titre: "Dune", couvertures: Apercu.couvertures))
        case "verrouBibliotheque":
            HonyaPlusView(verrou: .bibliotheque(couvertures: Apercu.couvertures))
        case "verrouStats":
            HonyaPlusView(verrou: .statistiques(couvertures: Apercu.couvertures))
        case "email":
            BienvenueView(surLEmail: true)
        case "clavierTest":
            // Le banc : le formulaire s'ouvre, le focus se pose sur
            // l'e-mail, puis bascule vers le mot de passe et revient,
            // pendant que la CI photographie en rafale.
            BienvenueView(surLEmail: true)
                .task {
                    func focus(_ champ: String) {
                        NotificationCenter.default.post(
                            name: Notification.Name("honya.banc.focus"),
                            object: nil,
                            userInfo: ["champ": champ]
                        )
                    }
                    try? await Task.sleep(for: .seconds(3))
                    focus("email")
                    for _ in 0..<3 {
                        try? await Task.sleep(for: .seconds(3))
                        focus("motDePasse")
                        try? await Task.sleep(for: .seconds(3))
                        focus("email")
                    }
                }
        case "oubli":
            BienvenueView(surLOubli: "demande")
        case "oubliCode":
            BienvenueView(surLOubli: "code")
        case "oubliNouveau":
            BienvenueView(surLOubli: "nouveau")
        case "onboarding":
            OnboardingView()
        case "onboarding2":
            OnboardingView(etapeDepart: 1)
        case "onboarding3":
            OnboardingView(etapeDepart: 2)
        case "motdepasse":
            BienvenueView(surLOubli: "mdp")
        case "bienvenue":
            BienvenueView()
        case "reglages":
            ReglagesView()
        case "decouverte":
            DecouverteView()
        case "roue":
            RoueSheet()
        case "perdu":
            RoueSheet(etapeDepart: "perdu")
        case "gain":
            RoueSheet(etapeDepart: "gain")
        default:
            RacineView()
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let ecranDemande {
                    ecranDeCapture(ecranDemande)
                } else {
                switch compte.etat {
                case .indetermine:
                    BienvenueView()
                        .transition(.opacity)
                case .connecte:
                    if onboardingTermine {
                        RacineView()
                    } else {
                        OnboardingView()
                    }
                }
                }
            }
            .animation(.easeInOut(duration: 0.35), value: compte.etat)
            .preferredColorScheme(apparence.schema)
            // Le lien de confirmation venu du courrier, accueilli a la
            // racine : il peut arriver que l'application soit deja ouverte,
            // sur n'importe quel ecran.
            //
            // Les DEUX portes, car elles ne s'ouvrent pas dans les memes cas :
            // onOpenURL recoit le schema « honya:// », onContinueUserActivity
            // recoit les liens universels — et selon que l'application dormait
            // ou tournait deja, c'est l'une ou l'autre qui sonne.
            .onOpenURL { url in
                Task { await compte.confirmerDepuisLien(url) }
            }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activite in
                guard let url = activite.webpageURL else { return }
                Task { await compte.confirmerDepuisLien(url) }
            }
            .task {
                await compte.verifierSession()
                // Toucher la boutique la met en route : elle charge le
                // catalogue et ouvre la veille des transactions. Sans cela,
                // un renouvellement ou un achat fait ailleurs ne serait vu
                // qu'à l'ouverture de l'écran d'abonnement.
                await Boutique.partage.relireLesDroits()
            }
        }
        .modelContainer(conteneur)
    }
}

// MARK: - Aperçus : conteneur en mémoire + petites données de démo

@MainActor
enum Apercu {
    /// Trois couvertures réelles, pour les aperçus et les captures d'écran :
    /// un verrou dessiné sur des cases vides ne se juge pas.
    static let couvertures = [
        "https://is1-ssl.mzstatic.com/image/thumb/Publication122/v4/f8/d6/07/f8d6075e-7bc9-abef-0c21-89652f8875ba/9782820350480-001-x.jpeg/400x400bb.jpg",
        "https://is1-ssl.mzstatic.com/image/thumb/Publication6/v4/47/ad/ec/47adec6f-1a55-e9f0-a242-19c2e749dc74/9782331009532-X.jpg/400x400bb.jpg",
        "https://is1-ssl.mzstatic.com/image/thumb/Publication113/v4/a6/89/a3/a689a3a6-2d9a-8afb-96fe-29ffcc5aebe6/9782809492002-001-x.jpeg/400x400bb.jpg",
    ]

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

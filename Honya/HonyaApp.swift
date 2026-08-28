import SwiftUI
import SwiftData

@main
struct HonyaApp: App {
    @AppStorage("apparence") private var apparence: ApparenceHonya = .systeme
    @Environment(\.scenePhase) private var phaseScene
    @State private var compte = Compte.partage
    @State private var boutique = Boutique.partage
    @State private var stockage = StockageCompte.partage
    @State private var repriseSuppressionEnCours = false

    init() {
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
            HonyaPlusView(verrou: .bibliotheque(couvertures: Apercu.couvertures))
        case "verrouEtagere":
            HonyaPlusView(verrou: .etagere(couvertures: Apercu.couvertures))
        case "verrouCitation":
            HonyaPlusView(verrou: .citation(couvertures: Apercu.couvertures))
        case "verrouAlerte":
            HonyaPlusView(verrou: .serie(
                nom: "One Piece", tomes: 112, couvertures: Apercu.couvertures
            ))
        case "verrouPret":
            HonyaPlusView(verrou: .pret(titre: "Dune", couvertures: Apercu.couvertures))
        case "verrouBibliotheque":
            HonyaPlusView(verrou: .bibliotheque(couvertures: Apercu.couvertures))
        case "verrouStats":
            HonyaPlusView(verrou: .statistiques(couvertures: Apercu.couvertures))
        case "scanner":
            // Le cas réel : plusieurs éditions scannées en rafale, dont
            // 9782749958194 (Instinct, tome 2). Une absence de catalogue
            // propose un nouvel essai et une fiche manuelle portant exactement
            // le code lu — jamais une déduction depuis un ISBN voisin.
            ScannerSheet(apercuISBN: [
                "9782749958187", "9782382881903", "9782749958194",
            ])
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

    private var ecranRepriseSuppression: some View {
        let operationEnCours = repriseSuppressionEnCours || compte.suppressionEnCours
        return VStack(spacing: 16) {
            if operationEnCours {
                ProgressView()
            }
            Text("Supprimer mon compte")
                .font(.headline)
            if !operationEnCours {
                Text(
                    compte.erreurRepriseSuppression
                        ?? stockage.erreur
                        ?? String(localized: "La connexion n'a pas abouti. Réessayez dans un instant.")
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Réessayer") {
                    Task { await reprendreSuppression() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(repriseSuppressionEnCours)
            }
        }
        .padding(28)
    }

    @MainActor
    private func reprendreSuppression() async {
        guard compte.suppressionEnAttente, !repriseSuppressionEnCours else { return }
        guard stockage.activerPourSuppression(
            identifiantServeur: compte.identifiantServeurCibleSuppression,
            typeStockage: compte.typeStockageCibleSuppression
        ), let conteneur = stockage.conteneurActif else { return }
        repriseSuppressionEnCours = true
        defer { repriseSuppressionEnCours = false }
        _ = await compte.reprendreSuppression(dans: conteneur.mainContext)
    }

    private var cleActivationStockage: String {
        let connecte = compte.etat == .connecte ? "1" : "0"
        let suppression = compte.suppressionEnAttente ? "1" : "0"
        let verifiee = compte.sessionVerifiee ? "1" : "0"
        return [
            connecte, suppression, verifiee,
            compte.identifiantServeur ?? "-",
            compte.identifiantServeurCibleSuppression ?? "-",
        ].joined(separator: "|")
    }

    @MainActor
    private func activerStockageSiNecessaire() async {
        if compte.suppressionEnAttente {
            guard !compte.suppressionReconnexionRequise else { return }
            await reprendreSuppression()
            return
        }
        guard compte.etat == .connecte,
              let identifiant = compte.identifiantServeur else { return }
        _ = stockage.activer(
            identifiantServeur: identifiant,
            sessionVerifiee: compte.sessionVerifiee
        )
    }

    private var ecranRevendicationLegacy: some View {
        VStack(spacing: 18) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Couleurs.accent)
            Text("Bibliothèque trouvée sur cet iPhone")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("Choisissez si cette ancienne bibliothèque appartient au compte que vous venez de connecter.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Associer cette bibliothèque à mon compte") {
                _ = stockage.confirmerRevendicationLegacy()
            }
            .buttonStyle(.borderedProminent)
            .tint(Couleurs.accent)
            Button("Commencer une nouvelle bibliothèque") {
                _ = stockage.refuserRevendicationLegacy()
            }
            .buttonStyle(.bordered)
        }
        .padding(28)
    }

    private var ecranErreurStockage: some View {
        VStack(spacing: 14) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("La bibliothèque ne peut pas être ouverte.")
                .font(.headline)
            Text(stockage.erreur ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Réessayer") {
                stockage.effacerErreur()
                Task {
                    await compte.verifierSession()
                    await activerStockageSiNecessaire()
                }
            }
            .buttonStyle(.borderedProminent)
            Button("Se déconnecter") { compte.seDeconnecter() }
                .buttonStyle(.bordered)
        }
        .padding(28)
    }

    @ViewBuilder
    private var ecranCompte: some View {
        if stockage.revendicationLegacyEnAttente {
            ecranRevendicationLegacy
        } else if let erreur = stockage.erreur, !erreur.isEmpty {
            ecranErreurStockage
        } else if let texte = compte.identifiantServeur,
                  let identifiant = UUID(uuidString: texte),
                  stockage.identifiantActif == identifiant,
                  let conteneur = stockage.conteneurActif,
                  let preferences = stockage.preferencesActives {
            EspaceCompteView(
                identifiantCompte: identifiant,
                droitsVerifies: boutique.droitsVerifies
            )
                .id(stockage.generation)
                .defaultAppStorage(preferences)
                .modelContainer(conteneur)
        } else {
            VStack(spacing: 12) {
                ProgressView()
                Text("Vérification du compte…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let ecranDemande {
                    ecranDeCapture(ecranDemande)
                        .modelContainer(Apercu.conteneur)
                } else if compte.suppressionEnAttente {
                    // Aucune ancienne donnée ne traverse une suppression
                    // interrompue. Le nettoyage est repris dans la tâche de
                    // lancement et cet écran disparaît seulement après save().
                    if compte.suppressionReconnexionRequise {
                        BienvenueView(connexionSeulement: true)
                    } else {
                        ecranRepriseSuppression
                    }
                } else {
                switch compte.etat {
                case .indetermine:
                    BienvenueView()
                        .transition(.opacity)
                case .connecte:
                    ecranCompte
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
                async let droits: Void = boutique.relireLesDroits()
                if compte.suppressionEnAttente {
                    await reprendreSuppression()
                    _ = await droits
                    return
                }
                // Toucher la boutique la met en route : elle charge le
                // catalogue et ouvre la veille des transactions. Sans cela,
                // un renouvellement ou un achat fait ailleurs ne serait vu
                // qu'à l'ouverture de l'écran d'abonnement.
                // Les droits Apple partent EN MÊME TEMPS que la session : une
                // panne Supabase ne doit jamais laisser un client payé devant
                // des cadenas pendant son attente réseau.
                async let session: Void = compte.verifierSession()
                _ = await (session, droits)
            }
            .task(id: cleActivationStockage) {
                await activerStockageSiNecessaire()
            }
            .onChange(of: phaseScene) { _, phase in
                if phase == .active {
                    Task { await boutique.relireLesDroits() }
                } else if phase == .background,
                          let identifiant = stockage.identifiantActif,
                          let contexte = stockage.conteneurActif?.mainContext {
                    Task {
                        await SauvegardeCloud.partage.synchroniser(
                            compte: identifiant,
                            contexte: contexte,
                            forcer: true
                        )
                    }
                }
            }
            .onChange(of: compte.etat) { _, etat in
                guard etat == .connecte, compte.suppressionEnAttente else { return }
                Task { await reprendreSuppression() }
            }
            // En reprise dans la même session, l'état pouvait déjà valoir
            // `.connecte` : seule cette bascule prouve alors la réauthentification.
            .onChange(of: compte.suppressionReconnexionRequise) { _, requise in
                guard !requise, compte.etat == .connecte,
                      compte.suppressionEnAttente else { return }
                Task { await reprendreSuppression() }
            }
            .alert(
                "Réglages",
                isPresented: Binding(
                    get: {
                        !compte.suppressionEnAttente
                            && compte.erreurRepriseSuppression != nil
                    },
                    set: { visible in
                        if !visible { compte.accuserErreurRepriseSuppression() }
                    }
                )
            ) {
                Button("OK") { compte.accuserErreurRepriseSuppression() }
            } message: {
                Text(compte.erreurRepriseSuppression ?? "")
            }
        }
        .modelContainer(stockage.conteneurBootstrap)
    }
}

/// Ce sous-arbre nait seulement apres le montage du store et de la suite de
/// preferences du bon compte. Tous ses `@Query` et `@AppStorage` sont donc
/// incapables de rester attaches au compte precedent.
private struct EspaceCompteView: View {
    let identifiantCompte: UUID
    let droitsVerifies: Bool
    @AppStorage("onboardingTermine") private var onboardingTermine = false
    @Environment(\.modelContext) private var contexte
    @Query private var series: [Serie]
    @Query private var objectifs: [Objectif]
    @State private var droits = Droits.partage
    @State private var sauvegarde = SauvegardeCloud.partage
    @State private var sauvegardeInitialeTerminee = false
    @State private var confirmationRestaurationCloud = false
    @State private var confirmationSauvegardeLocale = false

    private var cleReconciliationRappels: String {
        let langue = objectifs.first?.languePrincipale ?? Langues.codeAppareil
        return "\(droits.plus)|\(langue)"
    }

    @MainActor
    private func migrerAnciensTomesSiPossible() async {
        switch sauvegarde.etat {
        case .aJour, .restauree:
            break
        default:
            return
        }
        let nombre = ImportService.migrerTomesIsolesLegacy(dans: contexte)
        guard nombre > 0 else { return }
        // La première synchronisation vient d'établir une base commune avec
        // Supabase : publier aussitôt la migration évite que l'ancien modèle
        // réapparaisse sur un autre appareil.
        await sauvegarde.synchroniser(
            compte: identifiantCompte,
            contexte: contexte,
            forcer: true
        )
    }

    var body: some View {
        Group {
            if !droitsVerifies {
                ProgressView()
            } else if !sauvegardeInitialeTerminee {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Restauration de votre bibliothèque…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if case .conflit = sauvegarde.etat {
                conflitSauvegarde
            } else if onboardingTermine {
                RacineView()
            } else {
                OnboardingView()
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if sauvegardeInitialeTerminee,
               case .erreur(let message) = sauvegarde.etat {
                HStack(spacing: 10) {
                    Image(systemName: "icloud.slash")
                    Text(message)
                        .font(.caption)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    Button("Réessayer") {
                        Task {
                            await sauvegarde.reessayer(
                                compte: identifiantCompte,
                                contexte: contexte
                            )
                        }
                    }
                    .font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.ultraThinMaterial)
            }
        }
        .task(id: identifiantCompte) {
            await sauvegarde.synchroniser(
                compte: identifiantCompte,
                contexte: contexte,
                forcer: true
            )
            guard !Task.isCancelled else { return }
            await migrerAnciensTomesSiPossible()
            guard !Task.isCancelled else { return }
            sauvegardeInitialeTerminee = true

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(120))
                guard !Task.isCancelled else { return }
                await sauvegarde.synchroniser(
                    compte: identifiantCompte,
                    contexte: contexte
                )
                await migrerAnciensTomesSiPossible()
            }
        }
        .task(id: cleReconciliationRappels) {
            guard droitsVerifies else { return }
            await NotificationsService.reconcilierRappelsSortie(
                series: series,
                plus: droits.plus,
                langue: objectifs.first?.languePrincipale ?? Langues.codeAppareil
            )
        }
    }

    private var conflitSauvegarde: some View {
        VStack(spacing: 18) {
            Image(systemName: "icloud.and.arrow.down")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Couleurs.accent)
            Text("Deux bibliothèques différentes ont été trouvées")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("Choisissez celle à conserver. Ce choix remplacera l'autre copie.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Conserver cette bibliothèque sur l'iPhone") {
                confirmationSauvegardeLocale = true
            }
            .buttonStyle(.borderedProminent)
            .tint(Couleurs.accent)
            .disabled(sauvegarde.operationEnCours)
            Button("Restaurer la sauvegarde du compte", role: .destructive) {
                confirmationRestaurationCloud = true
            }
            .buttonStyle(.bordered)
            .disabled(sauvegarde.operationEnCours)
            if sauvegarde.operationEnCours { ProgressView() }
        }
        .padding(28)
        .confirmationDialog(
            "Remplacer la bibliothèque de cet iPhone ?",
            isPresented: $confirmationRestaurationCloud,
            titleVisibility: .visible
        ) {
            Button("Restaurer la sauvegarde du compte", role: .destructive) {
                Task { await sauvegarde.restaurerLaSauvegarde(contexte: contexte) }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("La bibliothèque actuelle sera remplacée par la copie sauvegardée dans votre compte.")
        }
        .confirmationDialog(
            "Remplacer la sauvegarde du compte ?",
            isPresented: $confirmationSauvegardeLocale,
            titleVisibility: .visible
        ) {
            Button("Conserver cette bibliothèque sur l'iPhone", role: .destructive) {
                Task { await sauvegarde.conserverCetAppareil(contexte: contexte) }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("La copie de cet iPhone deviendra la nouvelle sauvegarde de votre compte.")
        }
    }
}

// MARK: - Aperçus : conteneur en mémoire + petites données de démo

@MainActor
enum Apercu {
    /// Les captures techniques n'embarquent aucune couverture d'un catalogue
    /// tiers. Les composants affichent leurs placeholders Honya hors ligne.
    static let couvertures: [String] = [
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

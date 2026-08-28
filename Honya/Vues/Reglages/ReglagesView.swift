import SwiftUI
import SwiftData

struct ReglagesView: View {
    @Environment(\.modelContext) private var contexte
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var ouvrirURL
    @Query private var objectifs: [Objectif]

    @AppStorage("apparence", store: .standard)
    private var apparence: ApparenceHonya = .systeme
    @State private var confirmerEffacement = false
    @State private var confirmerSuppressionCompte = false
    @State private var suppressionEnCours = false
    @State private var erreurSuppression: String?
    @State private var compte = Compte.partage
    @State private var plusVisible = false
    @State private var droits = Droits.partage
    @State private var boutique = Boutique.partage
    @State private var sauvegarde = SauvegardeCloud.partage

    private var identifiantCompte: UUID? {
        compte.identifiantServeur.flatMap { UUID(uuidString: $0) }
    }

    private var versionApplication: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "—"
    }

    // MARK: - Compte

    @ViewBuilder
    /// Honya+ en tête des réglages : jusqu'ici l'abonnement ne s'atteignait
    /// qu'en butant sur un verrou, ce qui laissait croire l'app entièrement
    /// gratuite à qui ne butait sur rien.
    private var sectionAbonnement: some View {
        Section {
            Button {
                if boutique.abonnementRenouvelableActif,
                   let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                    ouvrirURL(url)
                } else {
                    plusVisible = true
                }
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: droits.plus ? "checkmark.seal.fill" : "books.vertical.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(
                            LinearGradient(
                                colors: [Couleurs.accent, Couleurs.accent.opacity(0.75)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "Honya+")
                            .font(.system(size: 17, weight: .semibold, design: .serif))
                            .foregroundStyle(.primary)
                        Group {
                            if droits.plus, boutique.achatAVie {
                                Text("Votre accès à vie est actif.")
                            } else if droits.plus {
                                Text("Votre abonnement est actif.")
                            } else {
                                Text("Rayons complets, bibliothèque sans plafond, historique entier.")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if !droits.plus || boutique.abonnementRenouvelableActif {
                        Image(systemName: boutique.abonnementRenouvelableActif
                              ? "arrow.up.right" : "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        }
    }

    private var sectionCompte: some View {
        Section {
            LabeledContent {
                Text(compte.nomAffiche)
                    .foregroundStyle(.secondary)
            } label: {
                Label(compte.libelleMethode, systemImage: "person.crop.circle.fill")
            }
            Button {
                compte.seDeconnecter()
                dismiss()
            } label: {
                Label("Se déconnecter", systemImage: "rectangle.portrait.and.arrow.right")
            }
            Button(role: .destructive) {
                confirmerSuppressionCompte = true
            } label: {
                Label("Supprimer mon compte", systemImage: "person.crop.circle.badge.xmark")
            }
            .disabled(suppressionEnCours)
        } header: {
            Text("Compte")
        } footer: {
            Text("Se déconnecter garde votre bibliothèque locale et sa sauvegarde. Supprimer le compte efface les deux. Pour retirer Honya de votre identifiant Apple, allez dans Réglages > votre nom > Connexion avec Apple.")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                sectionAbonnement
                sectionCompte

                if let objectif = objectifs.first {
                    sectionObjectif(objectif)
                    sectionLangues(objectif)
                }

                Section {
                    Picker(selection: $apparence) {
                        ForEach(ApparenceHonya.allCases) { cas in
                            Label(cas.libelle, systemImage: cas.symbole).tag(cas)
                        }
                    } label: {
                        Label("Apparence", systemImage: "circle.lefthalf.filled")
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("Affichage")
                } footer: {
                    Text("« Système » suit le réglage de votre iPhone.")
                }

                Section("Données") {
                    LabeledContent("Stockage") {
                        Text("iPhone + compte Honya")
                    }
                    LabeledContent("Sauvegarde") {
                        Text(libelleSauvegarde)
                            .foregroundStyle(couleurSauvegarde)
                    }
                    Button("Sauvegarder maintenant") {
                        guard let identifiantCompte else { return }
                        Task {
                            await sauvegarde.reessayer(
                                compte: identifiantCompte,
                                contexte: contexte
                            )
                        }
                    }
                    .disabled(identifiantCompte == nil || sauvegarde.operationEnCours)
                    Text("La bibliothèque est sauvegardée dans votre compte Supabase. Une divergence entre deux appareils demande toujours votre choix avant remplacement.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Tout effacer…", role: .destructive) {
                        confirmerEffacement = true
                    }
                }

                Section("À propos") {
                    LabeledContent("Application", value: "Honya")
                    LabeledContent("Version", value: versionApplication)
                    Link(
                        "Politique de confidentialité",
                        destination: URL(string: "https://www.honya.app/en/privacy/")!
                    )
                    Link(
                        "Conditions d’utilisation",
                        destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
                    )
                    Text("Métadonnées : Open Library et bibliothèques nationales. La provenance des couvertures soumises à attribution figure sur leur fiche.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .ecranHonyaPlus($plusVisible)
            .confirmationDialog(
                "Supprimer votre compte et toutes vos données ?",
                isPresented: $confirmerSuppressionCompte,
                titleVisibility: .visible
            ) {
                if boutique.abonnementRenouvelableActif {
                    Button("Gérer l'abonnement Apple") {
                        if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                            ouvrirURL(url)
                        }
                    }
                }
                Button("Supprimer définitivement", role: .destructive) {
                    Task {
                        suppressionEnCours = true
                        defer { suppressionEnCours = false }
                        do {
                            try await compte.supprimerCompte(dans: contexte)
                            dismiss()
                        } catch {
                            erreurSuppression = error.localizedDescription
                        }
                    }
                }
            } message: {
                Text("Votre bibliothèque, vos sessions, vos badges et vos étagères seront effacés. C'est sans retour. Un abonnement Honya+ reste géré par Apple et doit être résilié séparément.")
            }
            .alert(
                "Réglages",
                isPresented: Binding(
                    get: { erreurSuppression != nil },
                    set: { if !$0 { erreurSuppression = nil } }
                )
            ) {
                Button("Annuler", role: .cancel) { erreurSuppression = nil }
            } message: {
                Text(erreurSuppression ?? "")
            }
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                        .fontWeight(.bold)
                }
            }
            .confirmationDialog(
                "Effacer toute la bibliothèque, les sessions et les badges ? Cette action est définitive.",
                isPresented: $confirmerEffacement,
                titleVisibility: .visible
            ) {
                Button("Tout effacer", role: .destructive, action: toutEffacer)
            }
            .onAppear {
                // Garantit l'existence de l'objectif (premier lancement sans onboarding complet).
                _ = Objectif.courant(dans: contexte)
            }
        }
    }

    private var libelleSauvegarde: String {
        switch sauvegarde.etat {
        case .inactive: return String(localized: "Inactive")
        case .synchronisation: return String(localized: "En cours…")
        case .aJour: return String(localized: "À jour")
        case .restauree: return String(localized: "Restaurée")
        case .conflit: return String(localized: "Choix requis")
        case .erreur: return String(localized: "Indisponible")
        }
    }

    private var couleurSauvegarde: Color {
        switch sauvegarde.etat {
        case .aJour, .restauree: return .green
        case .conflit, .erreur: return .orange
        default: return .secondary
        }
    }

    // MARK: - Objectifs

    private func sectionObjectif(_ objectif: Objectif) -> some View {
        Section("Objectifs") {
            Stepper(value: Binding(
                get: { objectif.minutesParJour },
                set: { objectif.minutesParJour = $0 }
            ), in: 5...180, step: 5) {
                LabeledContent("Lecture quotidienne", value: "\(objectif.minutesParJour) min")
            }
            Stepper(value: Binding(
                get: { objectif.defiAnnuelLivres },
                set: { objectif.defiAnnuelLivres = $0 }
            ), in: 1...365) {
                LabeledContent("Défi annuel", value: "\(objectif.defiAnnuelLivres) lectures")
            }
            Text("Un joker par semaine protège votre série de lecture : une soirée ratée ne brûle pas 40 jours d'effort.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Langues

    private func sectionLangues(_ objectif: Objectif) -> some View {
        Section {
            ForEach(Langues.toutes) { langue in
                let actif = objectif.languesLecture.contains(langue.code)
                Button {
                    if actif {
                        guard objectif.languesLecture.count > 1 else { return }
                        objectif.languesLecture.removeAll { $0 == langue.code }
                    } else {
                        objectif.languesLecture.append(langue.code)
                    }
                } label: {
                    HStack {
                        Text(langue.nomNatif)
                            .foregroundStyle(.primary)
                        Spacer()
                        if actif {
                            Image(systemName: "checkmark")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(Couleurs.accent)
                        }
                    }
                }
            }
        } header: {
            Text("Langues de lecture")
        } footer: {
            Text("La première langue est la principale : la recherche la privilégie et les titres s'affichent dans leur version officielle publiée dans cette langue — jamais de traduction automatique.")
        }
    }

    // MARK: - Effacement

    private func toutEffacer() {
        do {
            try contexte.delete(model: Oeuvre.self)
            try contexte.delete(model: Exemplaire.self)
            try contexte.delete(model: Serie.self)
            try contexte.delete(model: Tome.self)
            try contexte.delete(model: SessionLecture.self)
            try contexte.delete(model: Citation.self)
            try contexte.delete(model: BadgeGagne.self)
            try contexte.delete(model: Collection.self)
            // Les noms d'emprunteurs font partie des données de bibliothèque :
            // « Tout effacer » ne doit laisser aucune donnée personnelle liée
            // aux anciens prêts dans les suggestions.
            for objectif in objectifs { objectif.emprunteursRecents = [] }
            try contexte.save()
            do {
                try CouverturesPersonnelles.supprimerToutes()
            } catch {
                // La bibliothèque est déjà vide et ne peut plus être
                // « rollbackée » après save(). Signaler le résidu permet de
                // relancer Tout effacer et de retenter le nettoyage privé.
                erreurSuppression = error.localizedDescription
                return
            }
            NotificationsService.annulerTousLesRappelsSortie()
            if let identifiantCompte {
                Task {
                    await sauvegarde.synchroniser(
                        compte: identifiantCompte,
                        contexte: contexte,
                        forcer: true
                    )
                }
            }
        } catch {
            // Les suppressions forment une seule opération : si l'enregistrement
            // échoue, on restaure le contexte au lieu de laisser une bibliothèque
            // à moitié vidée.
            contexte.rollback()
            erreurSuppression = error.localizedDescription
        }
    }
}

#Preview {
    ReglagesView()
        .modelContainer(Apercu.conteneur)
}

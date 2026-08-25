import SwiftUI
import SwiftData

struct ReglagesView: View {
    @Environment(\.modelContext) private var contexte
    @Environment(\.dismiss) private var dismiss
    @Query private var objectifs: [Objectif]

    @AppStorage("apparence") private var apparence: ApparenceHonya = .systeme
    @State private var confirmerEffacement = false
    @State private var confirmerSuppressionCompte = false
    @State private var compte = Compte.partage
    @State private var plusVisible = false
    @State private var droits = Droits.partage

    // MARK: - Compte

    @ViewBuilder
    /// Honya+ en tête des réglages : jusqu'ici l'abonnement ne s'atteignait
    /// qu'en butant sur un verrou, ce qui laissait croire l'app entièrement
    /// gratuite à qui ne butait sur rien.
    private var sectionAbonnement: some View {
        Section {
            Button {
                plusVisible = true
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
                        Text(droits.plus
                             ? "Votre abonnement est actif."
                             : "Rayons complets, alertes, historique entier.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if !droits.plus {
                        Image(systemName: "chevron.right")
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
            if compte.etat == .connecte {
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
            } else {
                Label("Aucun compte", systemImage: "person.crop.circle")
                Button {
                    // On revient à la bienvenue SANS rien effacer : la
                    // bibliothèque déjà constituée reste intacte.
                    compte.revoirLaBienvenue()
                    dismiss()
                } label: {
                    Label("Créer un compte ou se connecter", systemImage: "apple.logo")
                }
            }
        } header: {
            Text("Compte")
        } footer: {
            Text(compte.etat == .connecte
                 ? "Supprimer votre compte efface aussi toute votre bibliothèque sur cet appareil. Pour retirer Honya de votre identifiant Apple, allez dans Réglages > votre nom > Connexion avec Apple."
                 : "Vous utilisez Honya sans compte : tout reste sur cet appareil.")
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
                    LabeledContent("Stockage", value: "Sur l'appareil")
                    Text("La synchronisation iCloud (CloudKit) arrive dans une prochaine version — vos données restent à vous.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Tout effacer…", role: .destructive) {
                        confirmerEffacement = true
                    }
                }

                Section("À propos") {
                    LabeledContent("Application", value: "Honya")
                    LabeledContent("Version", value: "1.0")
                    Text("Métadonnées : Google Books, Open Library, AniList. Les couvertures restent la propriété de leurs éditeurs.")
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
                Button("Supprimer définitivement", role: .destructive) {
                    Task {
                        await compte.supprimerCompte(dans: contexte)
                        dismiss()
                    }
                }
            } message: {
                Text("Votre bibliothèque, vos sessions, vos badges et vos étagères seront effacés. C'est sans retour.")
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
            try contexte.delete(model: Serie.self)
            try contexte.delete(model: SessionLecture.self)
            try contexte.delete(model: BadgeGagne.self)
        } catch {
            // L'effacement partiel est signalé au prochain lancement par l'état restant.
        }
    }
}

#Preview {
    ReglagesView()
        .modelContainer(Apercu.conteneur)
}

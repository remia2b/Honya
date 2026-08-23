import SwiftUI
import SwiftData

struct ReglagesView: View {
    @Environment(\.modelContext) private var contexte
    @Environment(\.dismiss) private var dismiss
    @Query private var objectifs: [Objectif]

    @AppStorage("apparence") private var apparence: ApparenceHonya = .systeme
    @AppStorage("cleGoogleBooks") private var cleGoogleBooks = ""
    @State private var confirmerEffacement = false

    var body: some View {
        NavigationStack {
            Form {
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

                Section {
                    TextField("Clé API Google Books", text: $cleGoogleBooks)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.system(.footnote, design: .monospaced))
                } header: {
                    Text("Métadonnées")
                } footer: {
                    Text("Fortement recommandé : sans clé, Google limite les recherches anonymes et les couvertures françaises arrivent mal. Gratuit — console.cloud.google.com → créer un projet → activer « Books API » → Identifiants → Clé API, puis collez-la ici.")
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

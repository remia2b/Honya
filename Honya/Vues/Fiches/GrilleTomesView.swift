import SwiftUI
import SwiftData

/// La grille de tomes, façon Apple Books : chaque tome est un vrai livre avec
/// sa propre couverture — lu, possédé ou manquant se lit d'un coup d'œil, et
/// un tap ouvre une feuille qui dit ce qu'elle fait.
struct GrilleTomesView: View {
    @Bindable var serie: Serie
    let langue: String

    @Environment(\.modelContext) private var contexte

    @State private var tomeChoisi: Tome?
    @State private var reglageRapide: ReglageRapide?

    enum ReglageRapide: String, Identifiable {
        case possedes, lus
        var id: String { rawValue }

        var titre: String {
            switch self {
            case .possedes: return "Possédés jusqu'au tome"
            case .lus: return "Lus jusqu'au tome"
            }
        }

        var couleur: Color {
            switch self {
            case .possedes: return Couleurs.aLire
            case .lus: return Couleurs.lu
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            entete
            if serie.tomes.isEmpty {
                Text("Aucun tome pour l'instant — ajoutez-les avec le bouton ci-dessus.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                grille
                boutonsRapides
            }
        }
        .sheet(item: $tomeChoisi) { tome in
            FeuilleTome(tome: tome, serie: serie, langue: langue)
                .presentationDetents([.height(340)])
        }
        .sheet(item: $reglageRapide) { reglage in
            FeuilleJusquA(serie: serie, reglage: reglage)
                .presentationDetents([.height(320)])
        }
    }

    // MARK: - En-tête

    private var entete: some View {
        HStack {
            EtiquetteCarte("Tomes")
            Spacer()
            Button {
                let prochain = (serie.tomes.map(\.numero).max() ?? 0) + 1
                serie.tomes.append(Tome(numero: prochain))
                if let total = serie.tomesTotal, prochain > total {
                    serie.tomesTotal = prochain
                }
            } label: {
                Label("Ajouter", systemImage: "plus")
                    .font(.caption.weight(.bold))
            }
            .tint(Couleurs.accent)
        }
    }

    // MARK: - Grille de couvertures

    private var grille: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
            spacing: 16
        ) {
            ForEach(serie.tomesTries) { tome in
                Button {
                    tomeChoisi = tome
                } label: {
                    CaseTome(tome: tome, serie: serie, langue: langue)
                }
                .buttonStyle(.plain)
                .task(id: tome.persistentModelID) {
                    await ResolveurTomes.completer(tome, de: serie, langue: langue)
                }
            }
        }
    }

    // MARK: - Réglages rapides

    private var boutonsRapides: some View {
        HStack(spacing: 8) {
            bouton(.possedes, systemImage: "books.vertical.fill", texte: "Possédés jusqu'à…")
            bouton(.lus, systemImage: "checkmark.circle.fill", texte: "Lus jusqu'à…")
        }
    }

    private func bouton(_ reglage: ReglageRapide, systemImage: String, texte: String) -> some View {
        Button {
            reglageRapide = reglage
        } label: {
            Label(texte, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(reglage.couleur.opacity(0.15), in: Capsule())
                .foregroundStyle(reglage.couleur)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Un tome = un livre : sa couverture, son état

private struct CaseTome: View {
    let tome: Tome
    let serie: Serie
    let langue: String

    var body: some View {
        VStack(spacing: 6) {
            // Tant que la vraie couverture du tome n'est pas trouvée, un
            // placeholder généré : jamais la couverture du tome 1 dupliquée.
            CouvertureView(
                urlString: tome.couvertureURL,
                titre: "\(Tomaison.decomposer(serie.nomAffiche(langue)).base)\nTome \(tome.numero)",
                coins: 5,
                manga: serie.type != .livre
            )
            .saturation(tome.possede ? 1 : 0.3)
            .opacity(tome.possede ? 1 : 0.55)
            .overlay {
                // Le pointillé ne sert qu'aux cases SANS couverture : posé
                // par-dessus une vraie couverture, il salissait la grille.
                if !tome.possede && tome.couvertureURL == nil {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(
                            .secondary.opacity(0.5),
                            style: StrokeStyle(lineWidth: 1.2, dash: [5])
                        )
                }
            }
            .overlay(alignment: .topTrailing) {
                if tome.lu {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(.white, Couleurs.lu)
                        .background(Circle().fill(.white).padding(2))
                        .offset(x: 6, y: -6)
                }
            }
            .shadow(color: .black.opacity(tome.possede ? 0.3 : 0.1), radius: 6, y: 3)

            VStack(spacing: 1) {
                Text("Tome \(tome.numero)")
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(tome.possede ? .primary : .secondary)
                if let sortie = tome.dateSortie, sortie > Date() {
                    Text(sortie, format: .dateTime.day().month())
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Couleurs.accent)
                }
            }
        }
        .accessibilityLabel("Tome \(tome.numero)")
        .accessibilityValue(tome.lu ? "lu" : tome.possede ? "possédé" : "manquant")
    }
}

// MARK: - Feuille d'un tome : deux interrupteurs, aucun mystère

private struct FeuilleTome: View {
    @Bindable var tome: Tome
    let serie: Serie
    let langue: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var contexte

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: Binding(
                        get: { tome.possede },
                        set: { nouveau in
                            tome.possede = nouveau
                            if !nouveau { marquerLu(false) }
                        }
                    )) {
                        Label("Je le possède", systemImage: "books.vertical.fill")
                    }
                    .tint(Couleurs.aLire)

                    Toggle(isOn: Binding(
                        get: { tome.lu },
                        set: { marquerLu($0) }
                    )) {
                        Label("Je l'ai lu", systemImage: "checkmark.circle.fill")
                    }
                    .tint(Couleurs.lu)
                } footer: {
                    if let date = tome.dateLu {
                        Text("Lu le \(date.formatted(date: .long, time: .omitted)).")
                    } else if let pages = tome.pages {
                        Text("\(pages) pages.")
                    }
                }

                Section {
                    Button {
                        appliquerJusquIci()
                        dismiss()
                    } label: {
                        Label("Tout marquer lu jusqu'ici", systemImage: "text.badge.checkmark")
                    }
                    Button(role: .destructive) {
                        contexte.delete(tome)
                        dismiss()
                    } label: {
                        Label("Retirer ce tome", systemImage: "trash")
                    }
                }
            }
            .navigationTitle(tome.titre ?? "Tome \(tome.numero)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }.fontWeight(.bold)
                }
            }
        }
    }

    private func marquerLu(_ valeur: Bool) {
        tome.lu = valeur
        tome.dateLu = valeur ? Date() : nil
        if valeur { tome.possede = true }
        BadgesEngine.evaluer(dans: contexte)
        if valeur, serie.estTerminee {
            dismiss()
            Celebrations.partage.feter("Série terminée !")
        }
    }

    private func appliquerJusquIci() {
        for autre in serie.tomes where autre.numero <= tome.numero {
            autre.possede = true
            if !autre.lu {
                autre.lu = true
                autre.dateLu = Date()
            }
        }
        BadgesEngine.evaluer(dans: contexte)
        if serie.estTerminee {
            Celebrations.partage.feter("Série terminée !")
        }
    }
}

// MARK: - Réglage rapide : « j'ai tout jusqu'au tome N »

private struct FeuilleJusquA: View {
    @Bindable var serie: Serie
    let reglage: GrilleTomesView.ReglageRapide

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var contexte
    @State private var numero: Double = 1

    private var maximum: Double { Double(max(serie.tomes.count, 1)) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Text("Tome \(Int(numero))")
                    .font(.chiffreSerif(38))
                    .monospacedDigit()
                    .foregroundStyle(reglage.couleur)

                Slider(value: $numero, in: 1...maximum, step: 1)
                    .tint(reglage.couleur)

                Text(explication)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Spacer()
            }
            .padding(24)
            .navigationTitle(reglage.titre)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Appliquer") {
                        appliquer()
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
        }
        .onAppear {
            let depart = reglage == .possedes ? serie.nbPossedes : serie.nbLus
            numero = Double(max(1, depart))
        }
    }

    private var explication: String {
        switch reglage {
        case .possedes:
            return "Les tomes 1 à \(Int(numero)) seront marqués comme possédés. Les suivants passent en manquants."
        case .lus:
            return "Les tomes 1 à \(Int(numero)) seront marqués comme lus — et donc possédés."
        }
    }

    private func appliquer() {
        let seuil = Int(numero)
        for tome in serie.tomes {
            switch reglage {
            case .possedes:
                tome.possede = tome.numero <= seuil
                if !tome.possede, tome.lu {
                    tome.lu = false
                    tome.dateLu = nil
                }
            case .lus:
                let concerne = tome.numero <= seuil
                if concerne {
                    tome.possede = true
                    if !tome.lu { tome.dateLu = Date() }
                    tome.lu = true
                } else if tome.lu {
                    tome.lu = false
                    tome.dateLu = nil
                }
            }
        }
        BadgesEngine.evaluer(dans: contexte)
        if reglage == .lus, serie.estTerminee {
            Celebrations.partage.feter("Série terminée !")
        }
    }
}

import SwiftUI
import SwiftData

/// La grille de tomes, repensée : des numéros lisibles, un état évident,
/// et surtout des gestes qui se devinent — cocher un tome ouvre une feuille
/// qui dit ce qu'elle fait, au lieu de faire tourner un état caché.
struct GrilleTomesView: View {
    @Bindable var serie: Serie
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
                legende
            }
        }
        .sheet(item: $tomeChoisi) { tome in
            FeuilleTome(tome: tome, serie: serie)
                .presentationDetents([.height(300)])
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

    // MARK: - Grille

    private var grille: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5),
            spacing: 8
        ) {
            ForEach(serie.tomesTries) { tome in
                Button {
                    tomeChoisi = tome
                } label: {
                    CaseTome(tome: tome)
                }
                .buttonStyle(.plain)
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

    private var legende: some View {
        HStack(spacing: 14) {
            item(couleur: Couleurs.lu.opacity(0.22), bord: Couleurs.lu, texte: "Lu")
            item(couleur: Couleurs.aLire.opacity(0.18), bord: Couleurs.aLire, texte: "Possédé")
            item(couleur: .clear, bord: .secondary.opacity(0.45), texte: "Manquant", pointille: true)
        }
        .frame(maxWidth: .infinity)
    }

    private func item(couleur: Color, bord: Color, texte: String, pointille: Bool = false) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(bord, style: StrokeStyle(lineWidth: 1, dash: pointille ? [3] : []))
                .background(RoundedRectangle(cornerRadius: 3).fill(couleur))
                .frame(width: 11, height: 11)
            Text(texte)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Une case de tome : numéro lisible, état évident

private struct CaseTome: View {
    let tome: Tome

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(fond)
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(
                            bordure,
                            style: StrokeStyle(lineWidth: 1.4, dash: tome.possede ? [] : [4])
                        )
                }
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    Text("\(tome.numero)")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                        .foregroundStyle(couleurTexte)
                }

            if tome.lu {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Couleurs.lu)
                    .background(Circle().fill(Color(uiColor: .systemBackground)))
                    .offset(x: 4, y: -4)
            }
        }
        .accessibilityLabel("Tome \(tome.numero)")
        .accessibilityValue(tome.lu ? "lu" : tome.possede ? "possédé" : "manquant")
    }

    private var fond: Color {
        if tome.lu { return Couleurs.lu.opacity(0.22) }
        if tome.possede { return Couleurs.aLire.opacity(0.18) }
        return .clear
    }

    private var bordure: Color {
        if tome.lu { return Couleurs.lu.opacity(0.55) }
        if tome.possede { return Couleurs.aLire.opacity(0.55) }
        return .secondary.opacity(0.45)
    }

    private var couleurTexte: Color {
        if tome.lu { return Couleurs.lu }
        if tome.possede { return Couleurs.aLire }
        return .secondary
    }
}

// MARK: - Feuille d'un tome : deux interrupteurs, aucun mystère

private struct FeuilleTome: View {
    @Bindable var tome: Tome
    let serie: Serie

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
            .navigationTitle("Tome \(tome.numero)")
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
    }
}

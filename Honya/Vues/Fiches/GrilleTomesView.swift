import SwiftUI
import SwiftData
import PhotosUI

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
            case .possedes: return String(localized: "Possédés jusqu'au tome")
            case .lus: return String(localized: "Lus jusqu'au tome")
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
        // Plus de bouton « Ajouter » : le catalogue remplit la série tout
        // seul, sorties futures comprises.
        EtiquetteCarte("Tomes")
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

    private func bouton(
        _ reglage: ReglageRapide,
        systemImage: String,
        texte: LocalizedStringKey
    ) -> some View {
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
                urlString: tome.couvertureAffichee,
                titre: "\(Tomaison.decomposer(serie.nomAffiche(langue)).base)\nTome \(tome.numero)",
                coins: 5,
                manga: serie.type != .livre
            )
            .saturation(tome.possede ? 1 : 0.3)
            .opacity(tome.possede ? 1 : 0.55)
            .overlay {
                // Le pointillé ne sert qu'aux cases SANS couverture : posé
                // par-dessus une vraie couverture, il salissait la grille.
                if !tome.possede && tome.couvertureAffichee == nil {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(
                            .secondary.opacity(0.5),
                            style: StrokeStyle(lineWidth: 1.2, dash: [5])
                        )
                }
            }
            .overlay(alignment: .bottomLeading) {
                // Un tome absent de l'étagère se signale d'un regard.
                if tome.preteA != nil {
                    Image(systemName: "person.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(Couleurs.wishlist, in: Circle())
                        .offset(x: -5, y: 5)
                } else if tome.abandonne {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(Couleurs.abandonne, in: Circle())
                        .offset(x: -5, y: 5)
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
                if let sortie = tome.dateSortie, DateCivile.estAVenir(sortie) {
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
    @State private var pretVisible = false
    @State private var plusVisible = false
    @State private var verrouPlus: Verrou?
    @State private var selecteurCouvertureVisible = false
    @State private var photoCouverture: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(alignment: .top, spacing: 14) {
                        CouvertureView(
                            urlString: tome.couvertureAffichee,
                            titre: tome.titre ?? "Tome \(tome.numero)",
                            auteur: serie.auteur,
                            coins: 6,
                            manga: serie.type != .livre
                        )
                        .frame(width: 76)

                        VStack(alignment: .leading, spacing: 5) {
                            Text(tome.titre ?? "Tome \(tome.numero)")
                                .font(.titreOeuvre(19))
                            if let auteur = serie.auteur, !auteur.isEmpty {
                                Text(auteur)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            if let isbn = tome.isbn {
                                LabeledContent("ISBN", value: isbn)
                            }
                            if let pages = tome.pages {
                                LabeledContent("Pages", value: "\(pages)")
                            }
                            if let date = tome.dateSortie {
                                LabeledContent(
                                    "Date de sortie",
                                    value: date.formatted(date: .abbreviated, time: .omitted)
                                )
                            }
                        }
                        .font(.caption)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Toggle(isOn: Binding(
                        get: { tome.possede },
                        set: { nouveau in
                            if nouveau {
                                guard autoriserPossession([tome]) else { return }
                                tome.possede = true
                            } else {
                                tome.possede = false
                                marquerLu(false)
                                tome.abandonne = false
                                tome.preteA = nil
                                tome.preteLe = nil
                            }
                        }
                    )) {
                        Label("Je le possède", systemImage: "books.vertical.fill")
                    }
                    .tint(Couleurs.aLire)

                    Toggle(isOn: Binding(
                        get: { tome.lu },
                        set: { _ = marquerLu($0) }
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
                    Toggle(isOn: Binding(
                        get: { tome.abandonne },
                        set: { abandonne in
                            if abandonne, !autoriserPossession([tome]) { return }
                            tome.abandonne = abandonne
                            if abandonne {
                                tome.possede = true
                                marquerLu(false)
                                serie.statutChoisi = .abandonne
                            } else {
                                serie.statutChoisi = nil
                            }
                        }
                    )) {
                        Label("Abandonné", systemImage: "xmark.circle")
                    }
                    .tint(Couleurs.abandonne)

                    if let preteA = tome.preteA {
                        HStack {
                            Label("Prêté à \(preteA)", systemImage: "person.fill")
                            Spacer(minLength: 8)
                            Button("Rendu") {
                                tome.preteA = nil
                                tome.preteLe = nil
                            }
                            .buttonStyle(.bordered)
                            .font(.caption.weight(.bold))
                        }
                    } else if tome.possede
                                && tome.dateSortie.map({ DateCivile.estDisponible($0) }) != false {
                        Button {
                            // Prêter est un geste Honya+ ; rendre ne l'est jamais.
                            if Droits.partage.plus {
                                pretVisible = true
                            } else {
                                verrouPlus = .pret(
                                    titre: tome.titre ?? "Tome \(tome.numero)",
                                    couvertures: [tome.couvertureAffichee].compactMap { $0 }
                                )
                                plusVisible = true
                            }
                        } label: {
                            LabelPlus(titre: "Prêter ce tome…", symbole: "person.badge.plus")
                        }
                    }
                }

                Section {
                    Button {
                        if appliquerJusquIci() { dismiss() }
                    } label: {
                        Label("Tout marquer lu jusqu'ici", systemImage: "text.badge.checkmark")
                    }
                    Button(role: .destructive) {
                        let photo = tome.couverturePersonnelleURL
                        contexte.delete(tome)
                        do {
                            try contexte.save()
                            CouverturesPersonnelles.supprimer(photo)
                            dismiss()
                        } catch {
                            contexte.rollback()
                        }
                    } label: {
                        Label("Retirer ce tome", systemImage: "trash")
                    }
                }
            }
            .navigationTitle(tome.titre ?? "Tome \(tome.numero)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button {
                            selecteurCouvertureVisible = true
                        } label: {
                            Label("Modifier", systemImage: "photo.on.rectangle")
                        }
                        if tome.couverturePersonnelleURL != nil {
                            Button(role: .destructive) {
                                retirerCouverturePersonnelle()
                            } label: {
                                Label("Retirer", systemImage: "photo.badge.minus")
                            }
                        }
                    } label: {
                        Image(systemName: "photo")
                    }
                    .accessibilityLabel("Modifier")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }.fontWeight(.bold)
                }
            }
            .sheet(isPresented: $pretVisible) {
                PreterSheet(cible: .tome(tome), titre: tome.titre ?? "Tome \(tome.numero)")
            }
            .ecranHonyaPlus(
                $plusVisible,
                verrou: verrouPlus ?? .pret(
                    titre: tome.titre ?? "Tome \(tome.numero)",
                    couvertures: [tome.couvertureAffichee].compactMap { $0 }
                )
            )
            .photosPicker(
                isPresented: $selecteurCouvertureVisible,
                selection: $photoCouverture,
                matching: .images
            )
            .task(id: photoCouverture) {
                guard let selection = photoCouverture else { return }
                await enregistrerCouvertureChoisie(selection)
            }
        }
    }

    @discardableResult
    private func marquerLu(_ valeur: Bool) -> Bool {
        if valeur, !autoriserPossession([tome]) { return false }
        tome.lu = valeur
        tome.dateLu = valeur ? Date() : nil
        if valeur {
            tome.possede = true
            tome.abandonne = false
        }
        // Modifier la réalité de lecture invalide un statut de série choisi
        // auparavant : `nil` laisse le modèle recalculer Lu / En cours / À lire.
        serie.statutChoisi = nil
        BadgesEngine.evaluer(dans: contexte)
        if valeur, serie.estTerminee {
            dismiss()
            Celebrations.partage.feter("Série terminée !")
        }
        return true
    }

    @discardableResult
    private func appliquerJusquIci() -> Bool {
        let cibles = serie.tomes.filter { $0.numero <= tome.numero }
        guard autoriserPossession(cibles) else { return false }
        for autre in cibles {
            autre.possede = true
            autre.abandonne = false
            if !autre.lu {
                autre.lu = true
                autre.dateLu = Date()
            }
        }
        serie.statutChoisi = nil
        BadgesEngine.evaluer(dans: contexte)
        if serie.estTerminee {
            Celebrations.partage.feter("Série terminée !")
        }
        return true
    }

    private func enregistrerCouvertureChoisie(_ selection: PhotosPickerItem) async {
        defer {
            if photoCouverture == selection { photoCouverture = nil }
        }
        guard let donnees = try? await selection.loadTransferable(type: Data.self),
              !Task.isCancelled,
              photoCouverture == selection else { return }
        let ancienne = tome.couverturePersonnelleURL
        guard let nouvelle = try? CouverturesPersonnelles.enregistrer(donnees) else { return }
        tome.couverturePersonnelleURL = nouvelle
        do {
            try contexte.save()
            CouverturesPersonnelles.supprimer(ancienne)
        } catch {
            tome.couverturePersonnelleURL = ancienne
            CouverturesPersonnelles.supprimer(nouvelle)
        }
    }

    private func retirerCouverturePersonnelle() {
        let ancienne = tome.couverturePersonnelleURL
        guard CouverturesPersonnelles.estPersonnelle(ancienne) else { return }
        tome.couverturePersonnelleURL = nil
        do {
            try contexte.save()
            CouverturesPersonnelles.supprimer(ancienne)
        } catch {
            tome.couverturePersonnelleURL = ancienne
        }
    }

    private func autoriserPossession(_ tomes: [Tome]) -> Bool {
        guard ImportService.autorisePossession(
            des: tomes, de: serie, dans: contexte
        ) else {
            verrouPlus = .bibliotheque(
                couvertures: [tome.couvertureAffichee, serie.couvertureAffichee]
                    .compactMap { $0 }
            )
            plusVisible = true
            return false
        }
        return true
    }
}

// MARK: - Réglage rapide : « j'ai tout jusqu'au tome N »

private struct FeuilleJusquA: View {
    @Bindable var serie: Serie
    let reglage: GrilleTomesView.ReglageRapide

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var contexte
    @State private var numero: Double = 1
    @State private var plusVisible = false

    private var maximum: Double {
        Double(max(serie.tomes.map(\.numero).max() ?? 0, 1))
    }

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
                        if appliquer() { dismiss() }
                    }
                    .fontWeight(.bold)
                }
            }
        }
        .onAppear {
            let depart = serie.tomes
                .filter { reglage == .possedes ? $0.possede : $0.lu }
                .map(\.numero)
                .max() ?? 1
            numero = Double(max(1, depart))
        }
        .ecranHonyaPlus($plusVisible, verrou: .bibliotheque(
            couvertures: [serie.couvertureAffichee].compactMap { $0 }
        ))
    }

    private var explication: String {
        switch reglage {
        case .possedes:
            return String(localized: "Les tomes 1 à \(Int(numero)) seront marqués comme possédés. Les suivants passent en manquants.")
        case .lus:
            return String(localized: "Les tomes 1 à \(Int(numero)) seront marqués comme lus — et donc possédés.")
        }
    }

    @discardableResult
    private func appliquer() -> Bool {
        let seuil = Int(numero)
        let cibles = serie.tomes.filter { $0.numero <= seuil }
        let nombrePossedesProjete: Int
        switch reglage {
        case .possedes:
            nombrePossedesProjete = cibles.count
        case .lus:
            nombrePossedesProjete = serie.tomes.filter {
                $0.possede || $0.numero <= seuil
            }.count
        }
        guard ImportService.autoriseNombrePossedesProjete(
            nombrePossedesProjete, de: serie, dans: contexte
        ) else {
            plusVisible = true
            return false
        }
        for tome in serie.tomes {
            switch reglage {
            case .possedes:
                tome.possede = tome.numero <= seuil
                if !tome.possede {
                    if tome.lu {
                        tome.lu = false
                        tome.dateLu = nil
                    }
                    tome.abandonne = false
                    tome.preteA = nil
                    tome.preteLe = nil
                }
            case .lus:
                let concerne = tome.numero <= seuil
                if concerne {
                    tome.possede = true
                    tome.abandonne = false
                    if !tome.lu { tome.dateLu = Date() }
                    tome.lu = true
                } else if tome.lu {
                    tome.lu = false
                    tome.dateLu = nil
                }
            }
        }
        if reglage == .lus {
            serie.statutChoisi = nil
        }
        BadgesEngine.evaluer(dans: contexte)
        if reglage == .lus, serie.estTerminee {
            Celebrations.partage.feter("Série terminée !")
        }
        return true
    }
}

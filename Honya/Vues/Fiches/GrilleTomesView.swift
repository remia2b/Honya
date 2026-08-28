import SwiftUI
import SwiftData
import PhotosUI

/// La grille de tomes, façon Apple Books : chaque tome est un vrai livre avec
/// sa propre couverture — lu, possédé ou manquant se lit d'un coup d'œil, et
/// un tap ouvre sa fiche dédiée dans la navigation de la série.
struct GrilleTomesView: View {
    @Bindable var serie: Serie
    let langue: String

    @State private var reglageRapide: ReglageRapide?
    @State private var droits = Droits.partage

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
        .sheet(item: $reglageRapide) { reglage in
            FeuilleJusquA(serie: serie, reglage: reglage, langue: langue)
                .presentationDetents([.height(320)])
        }
        .task(id: droits.plus) {
            EditionsLocales.synchroniserAccesRayon(serie)
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
            ForEach(serie.tomesTries, id: \.persistentModelID) { tome in
                NavigationLink {
                    FicheTomeView(tome: tome, serie: serie, langue: langue)
                } label: {
                    CaseTome(
                        tome: tome,
                        serie: serie,
                        langue: langue,
                        verrouille: tomeEstVerrouille(tome)
                    )
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
        .badgeCadenas(contientContinuationVerrouillee)
    }

    /// Le cadenas porte sur l'automatisation du rayon, jamais sur un volume
    /// que le lecteur possède déjà. La première rangée sert d'aperçu gratuit.
    private func tomeEstVerrouille(_ tome: Tome) -> Bool {
        ImportService.tomeVerrouilleParRayon(tome, de: serie)
    }

    private var contientContinuationVerrouillee: Bool {
        ImportService.contientTomeVerrouille(serie.tomes, de: serie)
    }
}

// MARK: - Un tome = un livre : sa couverture, son état

private struct CaseTome: View {
    let tome: Tome
    let serie: Serie
    let langue: String
    let verrouille: Bool

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
                if verrouille {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(Couleurs.accent, in: Circle())
                        .offset(x: 6, y: -6)
                } else if tome.lu {
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
                Group {
                    if verrouille {
                        Text(verbatim: "Honya+")
                    } else {
                        Text(tome.statut.libelle)
                    }
                }
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(verrouille ? Couleurs.accent : tome.statut.couleur)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if let sortie = tome.dateSortie, DateCivile.estAVenir(sortie) {
                    Text(sortie, format: .dateTime.day().month())
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Couleurs.accent)
                }
            }
        }
        .accessibilityLabel("Tome \(tome.numero)")
        .accessibilityValue(Text(verbatim: verrouille ? "Honya+" : tome.statut.libelle))
    }
}

// MARK: - Fiche d'un tome

/// Un tome reste une destination à part entière, qu'il soit possédé, manquant
/// ou situé dans la continuation Honya+. Le cadenas protège uniquement les
/// mutations automatiques du rayon : les métadonnées restent consultables.
struct FicheTomeView: View {
    @Bindable var tome: Tome
    let serie: Serie
    let langue: String

    @Environment(\.modelContext) private var contexte
    @State private var pretVisible = false
    @State private var plusVisible = false
    @State private var verrouPlus: Verrou?
    @State private var selecteurCouvertureVisible = false
    @State private var photoCouverture: PhotosPickerItem?
    @State private var droits = Droits.partage

    var body: some View {
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
                    .frame(width: 86)
                    .saturation(tome.possede ? 1 : 0.45)
                    .opacity(tome.possede ? 1 : 0.72)

                    VStack(alignment: .leading, spacing: 7) {
                        Text(tome.titre ?? "Tome \(tome.numero)")
                            .font(.titreOeuvre(20))
                        Text(serie.nomAffiche(langue))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let auteur = serie.auteur, !auteur.isEmpty {
                            Text(auteur)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        BadgeStatutView(statut: tome.statut)
                    }
                }
                .padding(.vertical, 5)
            }

            Section("Informations") {
                LabeledContent("Tome", value: "\(tome.numero)")
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
                if tome.couverturePersonnelleURL == nil,
                   let attribution = tome.attributionCouverture {
                    LabeledContent("Couverture", value: attribution)
                }
            }

            Section {
                if tomeEstVerrouille {
                    Button {
                        verrouPlus = verrouRayon
                        plusVisible = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "lock.fill")
                                .foregroundStyle(Couleurs.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Poser le rayon entier")
                                    .font(.subheadline.weight(.semibold))
                                Text("Tous les tomes parus et à venir, dates comprises.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    Picker(
                        "Statut",
                        selection: Binding(
                            get: { tome.statut },
                            set: { appliquerStatut($0) }
                        )
                    ) {
                        ForEach(StatutLecture.allCases) { statut in
                            Label(statut.libelle, systemImage: statut.symbole)
                                .tag(statut)
                        }
                    }
                }
            } header: {
                Text("Statut")
            } footer: {
                if let date = tome.dateLu {
                    Text("Lu le \(date.formatted(date: .long, time: .omitted)).")
                }
            }

            Section {
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
                        if droits.plus {
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
                    _ = appliquerJusquIci()
                } label: {
                    Label("Tout marquer lu jusqu'ici", systemImage: "text.badge.checkmark")
                }
                .badgeCadenas(tomesJusquIciContiennentUnVerrou)

                if tome.possede {
                    Button(role: .destructive) {
                        appliquerStatut(.wishlist)
                    } label: {
                        Label("Retirer ce tome", systemImage: "minus.circle")
                    }
                }
            }
        }
        .navigationTitle(tome.titre ?? "Tome \(tome.numero)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
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
        }
        .sheet(isPresented: $pretVisible) {
            PreterSheet(cible: .tome(tome), titre: tome.titre ?? "Tome \(tome.numero)")
        }
        .ecranHonyaPlus(
            $plusVisible,
            verrou: verrouPlus ?? verrouRayon
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
        .task(id: droits.plus) {
            EditionsLocales.synchroniserAccesRayon(serie)
        }
    }

    private func appliquerStatut(_ statut: StatutLecture) {
        if statut != .wishlist, !autoriserPossession([tome]) { return }
        tome.changerStatut(statut)
        // Le statut de la série se déduit de tous ses tomes. Un volume en
        // cours ne doit donc pas écraser l'état des autres par un choix global.
        serie.statutChoisi = nil
        BadgesEngine.evaluer(dans: contexte)
        if statut == .lu, serie.estTerminee {
            Celebrations.partage.feter("Série terminée !")
        }
    }

    @discardableResult
    private func appliquerJusquIci() -> Bool {
        let cibles = serie.tomes.filter { $0.numero <= tome.numero }
        guard autoriserPossession(cibles) else { return false }
        for autre in cibles {
            autre.changerStatut(.lu)
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
        if tomes.contains(where: { tomeEstVerrouille($0) }) {
            verrouPlus = verrouRayon
            plusVisible = true
            return false
        }
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

    private var tomeEstVerrouille: Bool {
        tomeEstVerrouille(tome)
    }

    private func tomeEstVerrouille(_ candidat: Tome) -> Bool {
        ImportService.tomeVerrouilleParRayon(candidat, de: serie)
    }

    private var tomesJusquIciContiennentUnVerrou: Bool {
        serie.tomes.contains {
            $0.numero <= tome.numero && tomeEstVerrouille($0)
        }
    }

    private var verrouRayon: Verrou {
        .serie(
            nom: serie.nomAffiche(langue),
            tomes: serie.tomesTotal ?? serie.tomes.count,
            couvertures: Array(
                serie.tomesTries.compactMap(\.couvertureAffichee).prefix(3)
            )
        )
    }
}

// MARK: - Réglage rapide : « j'ai tout jusqu'au tome N »

private struct FeuilleJusquA: View {
    @Bindable var serie: Serie
    let reglage: GrilleTomesView.ReglageRapide
    let langue: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var contexte
    @State private var numero: Double = 1
    @State private var plusVisible = false
    @State private var verrouPlus: Verrou?
    @State private var droits = Droits.partage

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
        .ecranHonyaPlus(
            $plusVisible,
            verrou: verrouPlus ?? .bibliotheque(
                couvertures: [serie.couvertureAffichee].compactMap { $0 }
            )
        )
        .task(id: droits.plus) {
            EditionsLocales.synchroniserAccesRayon(serie)
        }
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
        if cibles.contains(where: { tomeEstVerrouille($0) }) {
            verrouPlus = verrouRayon
            plusVisible = true
            return false
        }
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
            verrouPlus = .bibliotheque(
                couvertures: [serie.couvertureAffichee].compactMap { $0 }
            )
            plusVisible = true
            return false
        }
        for tome in serie.tomes {
            switch reglage {
            case .possedes:
                if tome.numero <= seuil {
                    if !tome.possede { tome.changerStatut(.aLire) }
                } else {
                    tome.changerStatut(.wishlist)
                }
            case .lus:
                let concerne = tome.numero <= seuil
                if concerne {
                    tome.changerStatut(.lu)
                } else if tome.lu {
                    tome.changerStatut(.aLire)
                }
            }
        }
        serie.statutChoisi = nil
        BadgesEngine.evaluer(dans: contexte)
        if reglage == .lus, serie.estTerminee {
            Celebrations.partage.feter("Série terminée !")
        }
        return true
    }

    private func tomeEstVerrouille(_ tome: Tome) -> Bool {
        ImportService.tomeVerrouilleParRayon(tome, de: serie)
    }

    private var verrouRayon: Verrou {
        .serie(
            nom: serie.nomAffiche(langue),
            tomes: serie.tomesTotal ?? serie.tomes.count,
            couvertures: Array(
                serie.tomesTries.compactMap(\.couvertureAffichee).prefix(3)
            )
        )
    }

}

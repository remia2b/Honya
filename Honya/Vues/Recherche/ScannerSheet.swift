import SwiftUI
import SwiftData
import VisionKit

/// Scanner d'ISBN en rafale : on balaye une étagère entière,
/// chaque code-barres reconnu part chercher ses métadonnées.
struct ScannerSheet: View {
    /// Des codes joués d'avance, pour la CI qui photographie cet écran sans
    /// caméra. Le trajet est celui du vrai scan — catalogues compris — donc
    /// la capture montre aussi ce que la recherche met réellement de temps.
    var apercuISBN: [String] = []
    /// Ce que le lecteur part chercher a la main quand aucun catalogue ne
    /// connait son code-barres. La feuille se referme sur cette recherche.
    var surRechercheManuelle: (String) -> Void = { _ in }

    @Environment(\.modelContext) private var contexte
    @Environment(\.dismiss) private var dismiss

    @State private var trouves: [ResultatRecherche] = []
    /// Les codes lus qu'aucun catalogue ne connaît : on les montre plutôt que
    /// de laisser l'écran muet, et leur crédit de scan est rendu.
    @State private var introuvables: [String] = []
    @State private var scannes: Set<String> = []
    @State private var enRecherche = 0
    @State private var isbnManuel = ""
    @State private var ajoutes: Set<String> = []
    @State private var plusVisible = false
    @State private var compteur = CompteurScans.partage
    @State private var oublisVisibles = false
    /// Les fiches dont la couverture se cherche encore. Le livre est déjà
    /// à l'écran ; seule son image manque.
    @State private var chasseCouverture: Set<String> = []
    /// La recherche a emporter en refermant la feuille.
    @State private var rechercheVoulue = ""

    private var scannerDisponible: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        NavigationStack {
            GeometryReader { cadre in
            VStack(spacing: 0) {
                if scannerDisponible {
                    ScannerISBNRepresentable { code in
                        traiter(code)
                    }
                    // Attraper plusieurs codes d'un coup suppose que plusieurs
                    // livres tiennent dans le cadre : trois cents points fixes
                    // n'en cadraient qu'un seul a la fois.
                    .frame(height: max(300, cadre.size.height * 0.44))
                    .overlay(alignment: .bottom) {
                        VStack(spacing: 6) {
                            Text("Visez le code-barres au dos du livre")
                            if !Droits.partage.plus {
                                Text("\(compteur.reste) scans restants")
                                    .foregroundStyle(compteur.reste == 0 ? Couleurs.accent : .white.opacity(0.75))
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.6), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(.bottom, 12)
                    }
                } else {
                    saisieManuelle
                }

                listeTrouves
            }
            }
            .ecranHonyaPlus($plusVisible, verrou: .scan(
                couvertures: trouves.prefix(3).compactMap(\.couvertureURL)
            ))
            .navigationTitle("Scanner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        // Un seul statut imposé n'allait pas : on scanne une
                        // étagère de livres lus aussi bien qu'une pile à lire.
                        ForEach(StatutLecture.allCases) { statut in
                            Button {
                                ajouterTout(statut)
                            } label: {
                                Label(statut.libelle, systemImage: statut.symbole)
                            }
                        }
                    } label: {
                        Text("Tout ajouter…")
                    }
                    .disabled(trouves.allSatisfy(estAjoute))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminé") { partir(vers: "") }
                    .fontWeight(.bold)
                }
            }
        }
        // Tirer la feuille vers le bas est le geste le plus naturel de
        // l'iPhone — et il emportait silencieusement toute la pile scannée.
        // Tant qu'un livre reconnu n'est pas rangé, seul « Terminé » ferme,
        // et lui prévient.
        .task {
            for code in apercuISBN { traiter(code) }
        }
        .interactiveDismissDisabled(trouves.contains { !estAjoute($0) })
        .sensoryFeedback(.impact(weight: .light), trigger: scannes.count)
        .confirmationDialog(
            "\(oublies) livre(s) scanné(s) ne sont pas encore dans votre bibliothèque.",
            isPresented: $oublisVisibles,
            titleVisibility: .visible
        ) {
            ForEach(StatutLecture.allCases) { statut in
                Button("Tout ajouter — \(statut.libelle)") {
                    ajouterTout(statut)
                    quitter()
                }
            }
            Button("Quitter sans les ajouter", role: .destructive) { quitter() }
            Button("Rester ici", role: .cancel) { rechercheVoulue = "" }
        }
    }

    // MARK: - Repli sans caméra (simulateur, autorisation refusée)

    private var saisieManuelle: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Caméra indisponible ici", systemImage: "camera.badge.ellipsis")
                .font(.subheadline.weight(.semibold))
            Text("Saisissez l'ISBN à la main (13 chiffres, sous le code-barres).")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                TextField("9782…", text: $isbnManuel)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                Button("Chercher") {
                    traiter(isbnManuel)
                    isbnManuel = ""
                }
                .buttonStyle(.borderedProminent)
                .tint(Couleurs.accent)
                .disabled(!ISBNUtil.estValide(isbnManuel))
            }
        }
        .padding(20)
    }

    // MARK: - Liste des livres reconnus

    private var listeTrouves: some View {
        List {
            Section {
                if trouves.isEmpty && enRecherche == 0 {
                    Text("Les livres reconnus apparaîtront ici, prêts à rejoindre la bibliothèque.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if enRecherche > 0 {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Recherche de \(enRecherche) ISBN…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(trouves) { resultat in
                    ligne(resultat)
                }
            } header: {
                // Le catalogue porte les formes du pluriel — « 1 livre
                // reconnu », « 2 livres reconnus », et les quatre formes du
                // russe et du polonais. Coller un « s » ici ne marcherait
                // qu'en français.
                Text(trouves.isEmpty ? "En attente" : "\(trouves.count) livres reconnus")
            }

            if !introuvables.isEmpty {
                Section {
                    ForEach(introuvables, id: \.self) { isbn in
                        ligneIntrouvable(isbn)
                    }
                } footer: {
                    // Les éditions de clubs — France Loisirs et compagnie —
                    // manquent souvent aux catalogues. La recherche par titre
                    // reste le chemin ; et le scan n'a rien coûté.
                    Text("Certaines éditions n'y figurent pas — cherchez le titre à la main. Ces scans n'ont pas été décomptés.")
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    /// Un livre reconnu, mis en page comme une fiche de librairie : la
    /// couverture d'abord, le tome en évidence, l'ISBN en petit pour vérifier
    /// d'un coup d'œil qu'on tient bien la bonne édition.
    private func ligne(_ resultat: ResultatRecherche) -> some View {
        // Le titre brut disait « Solo leveling » sans dire quel tome : la
        // tomaison sépare la série du numéro.
        let (base, numero) = Tomaison.decomposer(resultat.titre)
        return HStack(alignment: .top, spacing: 14) {
            couverture(resultat)
                .frame(width: 54)

            VStack(alignment: .leading, spacing: 5) {
                Text(base)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                // Tome et auteur sur la même ligne : deux renseignements
                // courts qui gaspillaient chacun leur ligne.
                HStack(spacing: 7) {
                    if let numero {
                        Text("Tome \(numero)")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(Couleurs.accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(Couleurs.accent.opacity(0.16), in: Capsule())
                    }
                    if !resultat.auteurs.isEmpty {
                        Text(resultat.auteurs.joined(separator: ", "))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                if let isbn = resultat.isbn {
                    Text(verbatim: isbn)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 0)
            bouton(resultat)
        }
        .padding(.vertical, 5)
    }

    /// La couverture, ou son attente.
    ///
    /// Tant que l'image se cherche encore, on ne montre PAS la couverture de
    /// secours : afficher un dégradé inventé puis le remplacer donne
    /// l'impression que l'application s'est trompée de livre.
    @ViewBuilder
    private func couverture(_ resultat: ResultatRecherche) -> some View {
        if resultat.couvertureURL == nil, chasseCouverture.contains(resultat.id) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(.quaternary)
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                .overlay { ProgressView().controlSize(.small) }
        } else {
            CouvertureView(
                urlString: resultat.couvertureURL,
                titre: resultat.titre,
                auteur: resultat.auteurs.first,
                coins: 5,
                manga: resultat.type != .livre,
                // Une vignette de 54 points n'a que faire d'une image de 1200 :
                // on demandait une affiche pour un timbre.
                cote: 240
            )
        }
    }

    @ViewBuilder
    private func bouton(_ resultat: ResultatRecherche) -> some View {
        if estAjoute(resultat) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 27))
                .foregroundStyle(Couleurs.lu)
                .transition(.scale.combined(with: .opacity))
        } else {
            Menu {
                Button("Je le possède · à lire") { ajouter(resultat, statut: .aLire) }
                Button("Je suis en train de le lire") { ajouter(resultat, statut: .enCours) }
                Button("Je l'ai lu") { ajouter(resultat, statut: .lu) }
                Button("À acheter") { ajouter(resultat, statut: .wishlist) }
                Button("Je l'ai abandonné") { ajouter(resultat, statut: .abandonne) }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 31, height: 31)
                    .background(Couleurs.accent, in: Circle())
            }
        }
    }

    /// Un code qu'aucun catalogue ne connait — et la porte de sortie.
    ///
    /// Le laisser muet revenait a dire au lecteur que son livre n'existe pas.
    /// La ligne l'emmene maintenant a la recherche par titre, avec une piste
    /// quand on en a une.
    private func ligneIntrouvable(_ isbn: String) -> some View {
        let piste = suggestion(pour: isbn)
        return Button {
            partir(vers: piste)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "questionmark.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Introuvable dans les catalogues")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    if piste.isEmpty {
                        Text("Chercher le titre")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Couleurs.accent)
                    } else {
                        Text("Chercher « \(piste) »")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Couleurs.accent)
                            .lineLimit(1)
                    }
                    Text(verbatim: isbn)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }

    /// Ce qu'il faut taper pour retrouver un livre que personne ne reference.
    ///
    /// Les editeurs numerotent leurs tomes a la suite : le tome 2 porte
    /// l'ISBN du tome 1 augmente de un. Quand le lecteur vient justement de
    /// scanner un tome voisin, on sait donc quoi proposer — « Instinct 2 » —
    /// sans rien inventer : c'est une recherche qu'il valide lui-meme, pas
    /// une fiche ajoutee dans son dos.
    private func suggestion(pour isbn: String) -> String {
        guard let inconnu = Int(isbn.prefix(12)) else { return "" }
        for voisin in trouves {
            guard let sonISBN = voisin.isbn, let connu = Int(sonISBN.prefix(12)) else { continue }
            let ecart = inconnu - connu
            // Au-dela de trois rangs ce n'est plus la meme serie mais le
            // catalogue entier de l'editeur : on ne devine plus rien.
            guard ecart != 0, abs(ecart) <= 3 else { continue }
            let (base, numero) = Tomaison.decomposer(voisin.titre)
            guard let numero else { return base }
            let vise = numero + (ecart > 0 ? 1 : -1)
            return vise > 0 ? "\(base) \(vise)" : base
        }
        return ""
    }

    /// Partir, en emportant eventuellement une recherche.
    ///
    /// Partir en laissant des livres reconnus mais non ranges etait la
    /// meilleure facon de croire qu'ils l'etaient : on le dit d'abord.
    private func partir(vers requete: String) {
        rechercheVoulue = requete
        if trouves.contains(where: { !estAjoute($0) }) || enRecherche > 0 {
            oublisVisibles = true
        } else {
            quitter()
        }
    }

    private func quitter() {
        let requete = rechercheVoulue
        dismiss()
        if !requete.isEmpty { surRechercheManuelle(requete) }
    }

    // MARK: - Traitement d'un code

    private func estAjoute(_ resultat: ResultatRecherche) -> Bool {
        ajoutes.contains(resultat.id) || ImportService.existeDeja(resultat, dans: contexte)
    }

    private var oublies: Int {
        trouves.filter { !estAjoute($0) }.count
    }

    private func ajouterTout(_ statut: StatutLecture) {
        for resultat in trouves where !estAjoute(resultat) {
            ImportService.ajouter(resultat, statut: statut, dans: contexte)
            ajoutes.insert(resultat.id)
        }
    }

    private func ajouter(_ resultat: ResultatRecherche, statut: StatutLecture) {
        ImportService.ajouter(resultat, statut: statut, dans: contexte)
        ajoutes.insert(resultat.id)
    }

    private func traiter(_ code: String) {
        let propre = ISBNUtil.normaliser(code)
        guard ISBNUtil.estValide(propre), !scannes.contains(propre) else { return }
        // Le quota s'arrête au scan, jamais à la recherche manuelle : personne
        // n'est empêché d'ajouter un livre, seule la facilité se paie.
        guard compteur.autorise else {
            plusVisible = true
            return
        }
        compteur.enregistrer()
        scannes.insert(propre)
        enRecherche += 1
        Task { @MainActor in
            defer { enRecherche -= 1 }
            guard let resultat = await AgregateurMetadonnees.partage.parISBN(propre) else {
                // Aucun catalogue ne connaît ce code — les éditions de clubs
                // comme France Loisirs n'y figurent souvent pas. Le dire vaut
                // mieux qu'un écran qui reste muet, et le crédit du scan est
                // rendu : on ne fait pas payer une recherche sans résultat.
                if !introuvables.contains(propre) {
                    introuvables.insert(propre, at: 0)
                }
                compteur.rembourser()
                return
            }
            guard !trouves.contains(where: { $0.id == resultat.id }) else { return }
            withAnimation(.snappy(duration: 0.25)) {
                trouves.insert(resultat, at: 0)
            }
            chercherLaCouverture(resultat)
        }
    }

    /// La couverture manquante part se chercher SANS retenir le livre.
    ///
    /// Elle passe par une recherche de titre chez tous les catalogues : le
    /// chemin le plus long de la chaîne, et il bloquait jusqu'ici l'affichage
    /// d'un livre déjà identifié. Le lecteur voit maintenant son titre tout de
    /// suite, et l'image se pose ensuite.
    private func chercherLaCouverture(_ resultat: ResultatRecherche) {
        guard resultat.couvertureURL == nil else { return }
        chasseCouverture.insert(resultat.id)
        Task { @MainActor in
            defer { chasseCouverture.remove(resultat.id) }
            guard let url = await AgregateurMetadonnees.partage
                .couvertureDeSecours(pour: resultat),
                  let rang = trouves.firstIndex(where: { $0.id == resultat.id })
            else { return }
            withAnimation(.snappy(duration: 0.3)) {
                trouves[rang].couvertureURL = url
            }
        }
    }
}

// MARK: - Pont VisionKit

private struct ScannerISBNRepresentable: UIViewControllerRepresentable {
    var surCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8])],
            qualityLevel: .fast,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        if !scanner.isScanning {
            try? scanner.startScanning()
        }
    }

    func makeCoordinator() -> Coordinateur {
        Coordinateur(surCode: surCode)
    }

    final class Coordinateur: NSObject, DataScannerViewControllerDelegate {
        let surCode: (String) -> Void

        init(surCode: @escaping (String) -> Void) {
            self.surCode = surCode
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            lire(addedItems)
        }

        /// Un code-barres entre parfois dans le cadre avant d'etre dechiffre :
        /// VisionKit l'annonce alors une premiere fois sans contenu, puis le
        /// complete. N'ecouter que l'arrivee faisait perdre, sur une pile de
        /// livres, tous ceux dont la lecture avait demande un instant de plus.
        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didUpdate updatedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            lire(updatedItems)
        }

        private func lire(_ items: [RecognizedItem]) {
            for item in items {
                if case .barcode(let code) = item, let valeur = code.payloadStringValue {
                    surCode(valeur)
                }
            }
        }
    }
}

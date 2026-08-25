import SwiftUI
import SwiftData
import VisionKit

/// Scanner d'ISBN en rafale : on balaye une étagère entière,
/// chaque code-barres reconnu part chercher ses métadonnées.
struct ScannerSheet: View {
    @Environment(\.modelContext) private var contexte
    @Environment(\.dismiss) private var dismiss

    @State private var trouves: [ResultatRecherche] = []
    @State private var scannes: Set<String> = []
    @State private var enRecherche = 0
    @State private var isbnManuel = ""
    @State private var ajoutes: Set<String> = []
    @State private var plusVisible = false
    @State private var compteur = CompteurScans.partage
    @State private var oublisVisibles = false

    private var scannerDisponible: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if scannerDisponible {
                    ScannerISBNRepresentable { code in
                        traiter(code)
                    }
                    .frame(height: 300)
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
                    Button("Terminé") {
                        // Partir en laissant des livres reconnus mais non
                        // ajoutés était la meilleure façon de croire qu'ils
                        // étaient rangés : on le dit.
                        if trouves.contains(where: { !estAjoute($0) }) || enRecherche > 0 {
                            oublisVisibles = true
                        } else {
                            dismiss()
                        }
                    }
                    .fontWeight(.bold)
                }
            }
        }
        // Tirer la feuille vers le bas est le geste le plus naturel de
        // l'iPhone — et il emportait silencieusement toute la pile scannée.
        // Tant qu'un livre reconnu n'est pas rangé, seul « Terminé » ferme,
        // et lui prévient.
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
                    dismiss()
                }
            }
            Button("Quitter sans les ajouter", role: .destructive) { dismiss() }
            Button("Rester ici", role: .cancel) {}
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
                    HStack(spacing: 12) {
                        CouvertureView(
                            urlString: resultat.couvertureURL,
                            titre: resultat.titre,
                            coins: 4,
                            manga: resultat.type != .livre
                        )
                            .frame(width: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            // Le titre brut disait « Solo leveling » sans dire
                            // quel tome : la tomaison sépare la série du numéro.
                            let (base, numero) = Tomaison.decomposer(resultat.titre)
                            Text(base)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(2)
                            if let numero {
                                Text("Tome \(numero)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Couleurs.accent)
                            }
                            Text(resultat.auteurs.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            if let isbn = resultat.isbn {
                                Text(isbn)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                        if estAjoute(resultat) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Couleurs.lu)
                        } else {
                            Menu {
                                Button("Je le possède · à lire") { ajouter(resultat, statut: .aLire) }
                                Button("Je suis en train de le lire") { ajouter(resultat, statut: .enCours) }
                                Button("Je l'ai lu") { ajouter(resultat, statut: .lu) }
                                Button("À acheter") { ajouter(resultat, statut: .wishlist) }
                                Button("Je l'ai abandonné") { ajouter(resultat, statut: .abandonne) }
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(Couleurs.accent)
                            }
                        }
                    }
                }
            } header: {
                // Coller un « s » à la main ne marche qu'en français : chaque
                // langue a ses propres règles de pluriel.
                Text(trouves.isEmpty ? "En attente" : "\(trouves.count) livres reconnus")
            }
        }
        .listStyle(.insetGrouped)
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
            guard let resultat = await AgregateurMetadonnees.partage.parISBN(propre) else { return }
            guard !trouves.contains(where: { $0.id == resultat.id }) else { return }
            trouves.insert(resultat, at: 0)
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
            for item in addedItems {
                if case .barcode(let code) = item, let valeur = code.payloadStringValue {
                    surCode(valeur)
                }
            }
        }
    }
}

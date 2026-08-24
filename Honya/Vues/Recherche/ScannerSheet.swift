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
            .ecranHonyaPlus($plusVisible)
            .navigationTitle("Scanner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Tout « À lire »") {
                        for resultat in trouves where !estAjoute(resultat) {
                            ImportService.ajouter(resultat, statut: .aLire, dans: contexte)
                            ajoutes.insert(resultat.id)
                        }
                    }
                    .disabled(trouves.allSatisfy(estAjoute))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminé") { dismiss() }
                        .fontWeight(.bold)
                }
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: scannes.count)
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
                            .frame(width: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(resultat.titre)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
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

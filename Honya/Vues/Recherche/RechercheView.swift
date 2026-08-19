import SwiftUI
import SwiftData

enum PorteeRecherche: String, CaseIterable, Identifiable {
    case livres = "Livres"
    case mangas = "Mangas"
    case bibliotheque = "Ma bibliothèque"

    var id: String { rawValue }
}

/// L'entrée de la bibliothèque : recherche en ligne (Google Books / Open Library / AniList),
/// recherche locale, et scanner ISBN en rafale.
struct RechercheView: View {
    @Environment(\.modelContext) private var contexte
    @Query private var objectifs: [Objectif]
    @Query private var oeuvres: [Oeuvre]
    @Query private var series: [Serie]

    @State private var texte = ""
    @State private var portee: PorteeRecherche = .livres
    @State private var langueChoisie: String?      // nil = langue principale de l'utilisateur
    @State private var toutesLangues = false
    @State private var resultats: [ResultatRecherche] = []
    @State private var enChargement = false
    @State private var scannerVisible = false
    @State private var ajoutes: Set<String> = []
    @FocusState private var champActif: Bool

    private var langue: String { objectifs.first?.languePrincipale ?? "fr" }
    private var langueEffective: String? {
        toutesLangues ? nil : (langueChoisie ?? langue)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    EnteteEcran(titre: "Recherche") {
                        Button { scannerVisible = true } label: {
                            Image(systemName: "barcode.viewfinder")
                                .font(.title2)
                                .foregroundStyle(Couleurs.accent)
                        }
                        .accessibilityLabel("Scanner un ISBN")
                    }

                    champRecherche
                        .padding(.horizontal, 20)

                    Picker("Portée", selection: $portee) {
                        ForEach(PorteeRecherche.allCases) { cas in
                            Text(cas.rawValue).tag(cas)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 20)

                    if portee == .livres {
                        menuLangue
                            .padding(.horizontal, 20)
                    }

                    contenu
                        .padding(.horizontal, 20)
                }
                .padding(.bottom, 24)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
            .scrollDismissesKeyboard(.immediately)
            .sheet(isPresented: $scannerVisible) {
                ScannerSheet()
            }
            .task(id: cleRecherche) {
                await lancerRecherche()
            }
        }
    }

    private var cleRecherche: String {
        "\(texte)|\(portee.rawValue)|\(langueEffective ?? "toutes")"
    }

    // MARK: - Champ de recherche

    private var champRecherche: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Titre, auteur, série…", text: $texte)
                .focused($champActif)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !texte.isEmpty {
                Button {
                    texte = ""
                    resultats = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    private var menuLangue: some View {
        HStack(spacing: 8) {
            Text("Langue des éditions :")
                .font(.caption)
                .foregroundStyle(.secondary)
            Menu {
                ForEach(objectifs.first?.languesLecture ?? ["fr"], id: \.self) { code in
                    Button(code.uppercased()) {
                        langueChoisie = code
                        toutesLangues = false
                    }
                }
                Button("Toutes les langues") { toutesLangues = true }
            } label: {
                HStack(spacing: 4) {
                    Text(toutesLangues ? "Toutes" : (langueEffective ?? langue).uppercased())
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .font(.caption.weight(.bold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(uiColor: .secondarySystemFill), in: Capsule())
            }
            Spacer()
        }
    }

    // MARK: - Contenu

    @ViewBuilder
    private var contenu: some View {
        if enChargement {
            HStack {
                Spacer()
                ProgressView("Recherche…")
                Spacer()
            }
            .padding(.top, 40)
        } else if texte.count < 2 {
            carteInvitation
        } else if portee == .bibliotheque {
            resultatsLocaux
        } else if resultats.isEmpty {
            ContentUnavailableView.search(text: texte)
                .padding(.top, 30)
        } else {
            LazyVStack(spacing: 8) {
                ForEach(resultats) { resultat in
                    RangeeResultat(
                        resultat: resultat,
                        dejaAjoute: ajoutes.contains(resultat.id)
                            || ImportService.existeDeja(resultat, dans: contexte)
                    ) { statut in
                        ImportService.ajouter(resultat, statut: statut, dans: contexte)
                        ajoutes.insert(resultat.id)
                    }
                }
            }
        }
    }

    private var carteInvitation: some View {
        Button { scannerVisible = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "barcode.viewfinder")
                    .font(.system(size: 30))
                    .foregroundStyle(Couleurs.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Scannez toute une étagère")
                        .font(.subheadline.weight(.bold))
                    Text("Le code-barres au dos du livre suffit : titre, couverture et pages arrivent tout seuls, tome après tome.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(16)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Résultats locaux

    private var resultatsLocaux: some View {
        let requete = texte.lowercased()
        let oeuvresTrouvees = oeuvres.filter {
            $0.titre(langue).lowercased().contains(requete)
                || $0.titreOriginal.lowercased().contains(requete)
                || $0.auteurPrincipal.lowercased().contains(requete)
        }
        let seriesTrouvees = series.filter {
            $0.nomAffiche(langue).lowercased().contains(requete)
                || $0.nom.lowercased().contains(requete)
        }
        return LazyVStack(spacing: 8) {
            if oeuvresTrouvees.isEmpty && seriesTrouvees.isEmpty {
                ContentUnavailableView.search(text: texte)
                    .padding(.top, 30)
            }
            ForEach(oeuvresTrouvees) { oeuvre in
                NavigationLink {
                    FicheOeuvreView(oeuvre: oeuvre)
                } label: {
                    ligneLocale(
                        titre: oeuvre.titre(langue),
                        sousTitre: oeuvre.auteurPrincipal,
                        couverture: oeuvre.couvertureCanoniqueURL
                    )
                }
                .buttonStyle(.plain)
            }
            ForEach(seriesTrouvees) { serie in
                NavigationLink {
                    FicheSerieView(serie: serie)
                } label: {
                    ligneLocale(
                        titre: serie.nomAffiche(langue),
                        sousTitre: "\(serie.nbPossedes) possédés · \(serie.nbLus) lus",
                        couverture: serie.couvertureURL
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func ligneLocale(titre: String, sousTitre: String, couverture: String?) -> some View {
        HStack(spacing: 12) {
            CouvertureView(urlString: couverture, titre: titre, coins: 4)
                .frame(width: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(titre).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(sousTitre).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }

    // MARK: - Lancement (avec anti-rebond)

    private func lancerRecherche() async {
        guard portee != .bibliotheque else { return }
        guard texte.count >= 2 else {
            resultats = []
            return
        }
        // Anti-rebond : on attend que la frappe se calme.
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled else { return }

        enChargement = true
        defer { enChargement = false }

        switch portee {
        case .livres:
            resultats = await AgregateurMetadonnees.partage.rechercherLivres(texte, langue: langueEffective)
        case .mangas:
            resultats = await AgregateurMetadonnees.partage.rechercherMangas(texte)
        case .bibliotheque:
            break
        }
    }
}

// MARK: - Rangée de résultat en ligne

private struct RangeeResultat: View {
    let resultat: ResultatRecherche
    let dejaAjoute: Bool
    var surAjout: (StatutLecture) -> Void

    var body: some View {
        HStack(spacing: 12) {
            CouvertureView(
                urlString: resultat.couvertureURL,
                titre: resultat.titre,
                coins: 4
            )
            .frame(width: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(resultat.titre)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                if !resultat.auteurs.isEmpty {
                    Text(resultat.auteurs.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 4) {
                    if resultat.estSerie {
                        Text("Série")
                            .font(.system(size: 9, weight: .heavy))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Couleurs.accent.opacity(0.15), in: Capsule())
                            .foregroundStyle(Couleurs.accent)
                        if let tomes = resultat.tomesTotal {
                            Text("\(tomes) tomes")
                        }
                    }
                    if let annee = resultat.annee { Text(String(annee)) }
                    Text(resultat.source)
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            Spacer()

            if dejaAjoute {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Couleurs.lu)
                    .accessibilityLabel("Déjà dans la bibliothèque")
            } else if resultat.estSerie {
                Button {
                    surAjout(.aLire)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Couleurs.accent)
                }
                .accessibilityLabel("Ajouter la série")
            } else {
                Menu {
                    Button { surAjout(.aLire) } label: {
                        Label("À lire", systemImage: "book.closed")
                    }
                    Button { surAjout(.enCours) } label: {
                        Label("Je le lis en ce moment", systemImage: "book")
                    }
                    Button { surAjout(.lu) } label: {
                        Label("Déjà lu", systemImage: "checkmark.circle")
                    }
                    Button { surAjout(.wishlist) } label: {
                        Label("Wishlist", systemImage: "heart")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Couleurs.accent)
                }
                .accessibilityLabel("Ajouter")
            }
        }
        .padding(10)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .sensoryFeedback(.success, trigger: dejaAjoute)
    }
}

#Preview {
    RechercheView()
        .modelContainer(Apercu.conteneur)
}

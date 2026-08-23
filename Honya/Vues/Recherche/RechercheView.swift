import SwiftUI
import SwiftData

enum PorteeRecherche: String, CaseIterable, Identifiable {
    case tout = "Tout"
    case livres = "Livres"
    case mangas = "Mangas"

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
    @State private var portee: PorteeRecherche = .tout
    @State private var langueChoisie: String?      // nil = langue principale de l'utilisateur
    @State private var toutesLangues = false
    @State private var resultats: [ResultatRecherche] = []
    @State private var enChargement = false
    @State private var scannerVisible = false
    @State private var ajoutes: Set<String> = []
    @State private var tendances: [ResultatRecherche] = []
    @FocusState private var champActif: Bool

    private var langue: String { objectifs.first?.languePrincipale ?? Langues.codeAppareil }
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

                    if portee != .mangas {
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
                ForEach(objectifs.first?.languesLecture ?? [Langues.codeAppareil], id: \.self) { code in
                    Button(Langues.nom(code)) {
                        langueChoisie = code
                        toutesLangues = false
                    }
                }
                Divider()
                Button("Toutes les langues") { toutesLangues = true }
            } label: {
                HStack(spacing: 4) {
                    Text(toutesLangues ? "Toutes" : Langues.nom(langueEffective ?? langue))
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
            suggestions
        } else if resultats.isEmpty && trouvesLocalement.isEmpty {
            ContentUnavailableView.search(text: texte)
                .padding(.top, 30)
        } else {
            LazyVStack(spacing: 8) {
                if !trouvesLocalement.isEmpty {
                    EtiquetteSection(texte: "Déjà dans votre bibliothèque")
                        .padding(.top, 2)
                    resultatsLocaux
                    if !resultats.isEmpty {
                        EtiquetteSection(texte: "Ajouter à la bibliothèque")
                            .padding(.top, 8)
                    }
                }
                ForEach(resultats) { resultat in
                    NavigationLink {
                        ApercuResultatView(resultat: resultat, langue: langue)
                    } label: {
                        RangeeResultat(
                            resultat: resultat,
                            langue: langue,
                            dejaAjoute: ajoutes.contains(resultat.id)
                                || ImportService.existeDeja(resultat, dans: contexte)
                        ) { statut in
                            ImportService.ajouter(resultat, statut: statut, dans: contexte)
                            ajoutes.insert(resultat.id)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Suggestions (avant même de taper)

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 18) {
            carteInvitation

            if !tendances.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    TitreSection(titre: "Populaires en ce moment")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 14) {
                            ForEach(tendances.prefix(12)) { resultat in
                                NavigationLink {
                                    ApercuResultatView(resultat: resultat, langue: langue)
                                } label: {
                                    CouvertureView(
                                        urlString: resultat.couvertureURL,
                                        titre: resultat.titre,
                                        coins: 6
                                    )
                                    .frame(width: 92)
                                    .shadow(color: .black.opacity(0.35), radius: 9, y: 5)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    TitreSection(titre: "Tendances des recherches")
                    ForEach(termesTendance, id: \.self) { terme in
                        Button {
                            texte = terme
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "magnifyingglass")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Couleurs.accent)
                                Text(terme)
                                    .font(.callout)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(.vertical, 9)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
            }
        }
        .task {
            guard tendances.isEmpty else { return }
            tendances = await Decouverte.classement(gratuits: false, langue: langue)
        }
    }

    /// Les titres du top du pays, transformés en termes de recherche propres
    /// (nom de série sans numéro de tome, dédoublonnés).
    private var termesTendance: [String] {
        var vus = Set<String>()
        let bases = tendances.compactMap { resultat -> String? in
            let base = Tomaison.decomposer(resultat.titre).base
            let cle = TexteUtil.normaliser(base)
            guard !cle.isEmpty, vus.insert(cle).inserted else { return nil }
            return base
        }
        return Array(bases.prefix(8))
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

    private var oeuvresLocales: [Oeuvre] {
        texte.count >= 2 ? oeuvres.filter { $0.correspond(texte) } : []
    }

    private var seriesLocales: [Serie] {
        texte.count >= 2 ? series.filter { $0.correspond(texte) } : []
    }

    private var trouvesLocalement: [String] {
        oeuvresLocales.map(\.titreOriginal) + seriesLocales.map(\.nom)
    }

    private var resultatsLocaux: some View {
        let oeuvresTrouvees = oeuvresLocales
        let seriesTrouvees = seriesLocales
        return LazyVStack(spacing: 8) {
            ForEach(oeuvresTrouvees) { oeuvre in
                NavigationLink {
                    FicheOeuvreView(oeuvre: oeuvre)
                } label: {
                    ligneLocale(
                        titre: oeuvre.titre(langue),
                        sousTitre: oeuvre.auteurPrincipal,
                        couverture: oeuvre.couvertureAffichee
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
                        couverture: serie.couvertureAffichee
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
        guard texte.count >= 2 else {
            resultats = []
            return
        }
        // Anti-rebond : on attend que la frappe se calme.
        try? await Task.sleep(for: .milliseconds(220))
        guard !Task.isCancelled else { return }

        enChargement = true
        defer { enChargement = false }

        switch portee {
        case .tout:
            async let livres = AgregateurMetadonnees.partage.rechercherLivres(texte, langue: langueEffective)
            async let mangas = AgregateurMetadonnees.partage.rechercherMangas(texte, langue: langue)
            // Les séries d'abord : c'est ce qu'on cherche le plus souvent par leur nom.
            resultats = await mangas + livres
        case .livres:
            resultats = await AgregateurMetadonnees.partage.rechercherLivres(texte, langue: langueEffective)
        case .mangas:
            resultats = await AgregateurMetadonnees.partage.rechercherMangas(texte, langue: langue)
        }
    }
}

// MARK: - Rangée de résultat en ligne

private struct RangeeResultat: View {
    let resultat: ResultatRecherche
    let langue: String
    let dejaAjoute: Bool
    var surAjout: (StatutLecture) -> Void

    var body: some View {
        HStack(spacing: 12) {
            CouvertureView(
                urlString: resultat.couvertureURL,
                titre: resultat.titreAffiche(langue),
                coins: 4
            )
            .frame(width: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(resultat.titreAffiche(langue))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                if !resultat.auteurs.isEmpty {
                    Text(resultat.auteurs.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 4) {
                    if let numero = Tomaison.decomposer(resultat.titre).numero, !resultat.estSerie {
                        Text("Tome \(numero)")
                            .font(.system(size: 9, weight: .heavy))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Couleurs.lu.opacity(0.15), in: Capsule())
                            .foregroundStyle(Couleurs.lu)
                    }
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
                        Label("Je le possède · à lire", systemImage: "books.vertical.fill")
                    }
                    Button { surAjout(.enCours) } label: {
                        Label("Je suis en train de le lire", systemImage: "book.fill")
                    }
                    Button { surAjout(.lu) } label: {
                        Label("Je l'ai lu", systemImage: "checkmark.circle.fill")
                    }
                    Button { surAjout(.wishlist) } label: {
                        Label("À acheter", systemImage: "cart.fill")
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

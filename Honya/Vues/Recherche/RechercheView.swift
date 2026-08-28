import SwiftUI
import SwiftData

enum PorteeRecherche: String, CaseIterable, Identifiable {
    case tout = "Tout"
    case livres = "Livres"
    case mangas = "Mangas"

    var id: String { rawValue }

    var libelle: String {
        switch self {
        case .tout: return String(localized: "Tout")
        case .livres: return String(localized: "Livres")
        case .mangas: return String(localized: "Mangas")
        }
    }
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
    @State private var ajoutManuelVisible = false
    @State private var plusVisible = false
    @State private var verrouPlus: Verrou?
    @State private var ajoutes: Set<String> = []
    @State private var tendances: [ResultatRecherche] = []
    @FocusState private var champActif: Bool

    private var langue: String { objectifs.first?.languePrincipale ?? Langues.codeAppareil }
    private var languesConfigurees: [String] {
        let configurees = objectifs.first?.languesLecture ?? []
        return configurees.isEmpty ? [langue] : configurees
    }
    private var langueSelectionnee: String {
        guard let langueChoisie, languesConfigurees.contains(langueChoisie) else {
            return langue
        }
        return langueChoisie
    }
    private var langueEffective: String? {
        // Une recherche manga doit toujours cibler une édition dans l'une
        // des langues de lecture configurées. Le mode global « Toutes » reste
        // disponible pour les livres et la recherche mixte.
        if portee == .mangas || !toutesLangues {
            return langueSelectionnee
        }
        return nil
    }
    /// Langue utilisée par les lignes et les fiches. En mode « toutes », la
    /// langue principale reste le meilleur repli ; sinon le choix du menu doit
    /// suivre jusqu'au dernier écran, pas seulement jusqu'à l'API.
    private var langueAffichage: String { langueEffective ?? langue }

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
                            Text(cas.libelle).tag(cas)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 20)

                    menuLangue
                        .padding(.horizontal, 20)

                    contenu
                        .padding(.horizontal, 20)
                }
                .padding(.bottom, 24)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
            .scrollDismissesKeyboard(.immediately)
            .sheet(isPresented: $scannerVisible) {
                ScannerSheet { requete in
                    // Le scanner a rendu la main sur un code que personne ne
                    // connait : la recherche prend le relais, deja remplie.
                    texte = requete
                    portee = .tout
                }
            }
            .sheet(isPresented: $ajoutManuelVisible) {
                AjoutManuelSheet(
                    isbnInitial: ISBNUtil.canonique(texte) ?? "",
                    titreInitial: ISBNUtil.canonique(texte) == nil ? texte : "",
                    typeInitial: portee == .mangas ? .manga : .livre,
                    langueInitiale: langueEffective ?? langue
                ) { resultat in
                    ajoutes.insert(resultat.id)
                    // Une recherche ISBN ne peut plus retrouver localement le
                    // livre par son titre. Après saisie, on montre donc la
                    // fiche réellement créée plutôt qu'un ancien état vide.
                    if ISBNUtil.canonique(texte) != nil {
                        texte = resultat.titre
                    }
                }
            }
            .ecranHonyaPlus(
                $plusVisible,
                verrou: verrouPlus ?? .bibliotheque()
            )
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
                ForEach(languesConfigurees, id: \.self) { code in
                    Button(Langues.nom(code)) {
                        langueChoisie = code
                        toutesLangues = false
                    }
                }
                if portee != .mangas {
                    Divider()
                    Button("Toutes les langues") { toutesLangues = true }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(
                        toutesLangues && portee != .mangas
                            ? String(localized: "Toutes les langues")
                            : Langues.nom(langueEffective ?? langue)
                    )
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
            VStack(spacing: 14) {
                ContentUnavailableView.search(text: texte)
                Button {
                    ajoutManuelVisible = true
                } label: {
                    Label("Ajouter un livre", systemImage: "square.and.pencil")
                }
                .buttonStyle(.borderedProminent)
                .tint(Couleurs.accent)
            }
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
                if !resultatsSeries.isEmpty {
                    EtiquetteSection(texte: "Séries")
                    rangees(resultatsSeries)
                }
                if !resultatsTomes.isEmpty {
                    EtiquetteSection(texte: "Tomes")
                        .padding(.top, resultatsSeries.isEmpty ? 0 : 8)
                    rangees(resultatsTomes)
                }
                if !resultatsLivres.isEmpty {
                    EtiquetteSection(texte: "Livres")
                        .padding(.top, (resultatsSeries.isEmpty && resultatsTomes.isEmpty) ? 0 : 8)
                    rangees(resultatsLivres)
                }
            }
        }
    }

    private var resultatsSeries: [ResultatRecherche] {
        resultats.filter(\.estSerie)
    }

    private var resultatsTomes: [ResultatRecherche] {
        resultats.filter { !$0.estSerie && $0.estUnTome }
    }

    private var resultatsLivres: [ResultatRecherche] {
        resultats.filter { !$0.estSerie && !$0.estUnTome }
    }

    private func rangees(_ elements: [ResultatRecherche]) -> some View {
        ForEach(elements) { resultat in
            RangeeResultat(
                resultat: resultat,
                langue: langueAffichage,
                dejaAjoute: ajoutes.contains(resultat.id)
                    || ImportService.existeDeja(resultat, dans: contexte)
            ) { statut in
                switch ImportService.ajouter(
                    resultat, statut: statut, dans: contexte
                ) {
                case .limiteAtteinte:
                    verrouPlus = nil
                    plusVisible = true
                case .rayonVerrouille(let serie):
                    verrouPlus = .serie(serie, langue: langueAffichage)
                    plusVisible = true
                case .oeuvre, .serie, .dejaPresent:
                    ajoutes.insert(resultat.id)
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
                    TitreSection(titre: "Nouveautés et tendances")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 14) {
                            ForEach(tendances.prefix(12)) { resultat in
                                NavigationLink {
                                    ApercuResultatView(
                                        resultat: resultat,
                                        langue: langueSelectionnee
                                    )
                                } label: {
                                    CouvertureView(
                                        urlString: resultat.couvertureURL,
                                        titre: resultat.titreAffiche(langueSelectionnee),
                                        coins: 6,
                                        manga: resultat.type != .livre
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
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }
        }
        .task(id: langueSelectionnee) {
            tendances = []
            tendances = await Decouverte.classement(
                gratuits: false,
                langue: langueSelectionnee
            )
        }
    }

    /// Les titres du top du pays, transformés en termes de recherche propres
    /// (nom de série sans numéro de tome, dédoublonnés).
    private var termesTendance: [String] {
        var vus = Set<String>()
        let bases = tendances.compactMap { resultat -> String? in
            let base = Tomaison.decomposer(
                resultat.titreAffiche(langueSelectionnee)
            ).base
            let cle = TexteUtil.normaliser(base)
            guard !cle.isEmpty, vus.insert(cle).inserted else { return nil }
            return base
        }
        let trouves = Array(bases.prefix(8))
        return trouves.isEmpty
            ? Array(Decouverte.termesSuggestions(pour: langueSelectionnee).prefix(6))
            : trouves
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
                    Text("La recherche privilégie les éditions dans vos langues, et les titres s'affichent tels qu'ils sont officiellement publiés.")
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
        guard texte.count >= 2 else { return [] }
        return oeuvres.filter { oeuvre in
            guard oeuvre.correspond(texte) else { return false }
            switch portee {
            case .tout: return true
            case .livres: return oeuvre.type == .livre
            case .mangas: return oeuvre.type != .livre
            }
        }
    }

    private var seriesLocales: [Serie] {
        guard texte.count >= 2 else { return [] }
        return series.filter { serie in
            guard serie.correspond(texte) else { return false }
            switch portee {
            case .tout: return true
            case .livres: return serie.type == .livre
            case .mangas: return serie.type != .livre
            }
        }
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
                        titre: oeuvre.titre(langueAffichage),
                        sousTitre: oeuvre.auteurPrincipal,
                        couverture: oeuvre.couvertureAffichee,
                        manga: oeuvre.type != .livre
                    )
                }
                .buttonStyle(.plain)
            }
            ForEach(seriesTrouvees) { serie in
                NavigationLink {
                    FicheSerieView(serie: serie)
                } label: {
                    ligneLocale(
                        titre: serie.nomAffiche(langueAffichage),
                        sousTitre: "\(serie.nbPossedes) possédés · \(serie.nbLus) lus",
                        couverture: serie.couvertureAffichee,
                        manga: serie.type != .livre
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func ligneLocale(
        titre: String,
        sousTitre: String,
        couverture: String?,
        manga: Bool
    ) -> some View {
        HStack(spacing: 12) {
            CouvertureView(urlString: couverture, titre: titre, coins: 4, manga: manga)
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
            enChargement = false
            return
        }
        // Anti-rebond : on attend que la frappe se calme.
        try? await Task.sleep(for: .milliseconds(220))
        guard !Task.isCancelled else { return }

        enChargement = true

        // Un ISBN saisi au clavier mérite les mêmes garanties que la caméra :
        // clé de contrôle valide, correspondance canonique exacte et aucune
        // couverture empruntée à un autre tirage.
        let nouveaux: [ResultatRecherche]
        if let isbn = ISBNUtil.canonique(texte) {
            guard let rapide = await AgregateurMetadonnees.partage.parISBN(isbn) else {
                guard !Task.isCancelled, ISBNUtil.canonique(texte) == isbn else { return }
                resultats = []
                enChargement = false
                return
            }
            guard !Task.isCancelled, ISBNUtil.canonique(texte) == isbn else { return }

            // Même comportement que la caméra : la fiche identifiable paraît
            // immédiatement, puis les catalogues nationaux complètent CET ISBN
            // en arrière-plan (type, résumé, couverture exacte si disponible).
            resultats = [rapide]
            enChargement = false
            let enrichi = await AgregateurMetadonnees.partage.enrichirFicheExacte(rapide)
            guard !Task.isCancelled, ISBNUtil.canonique(texte) == isbn else { return }
            ImportService.appliquerEnrichissementExact(enrichi, dans: contexte)
            if enrichi != rapide { resultats = [enrichi] }
            return
        } else {
            switch portee {
            case .tout:
                nouveaux = await AgregateurMetadonnees.partage
                    .rechercherTout(texte, langue: langueEffective)
            case .livres:
                nouveaux = await AgregateurMetadonnees.partage
                    .rechercherLivres(texte, langue: langueEffective)
                    .filter { $0.type == .livre && !$0.estUnTome }
            case .mangas:
                nouveaux = await AgregateurMetadonnees.partage
                    .rechercherMangas(texte, langue: langueSelectionnee)
            }
        }

        // `.task(id:)` annule l'ancienne frappe, mais les fournisseurs qui
        // avaient déjà reçu leur requête peuvent encore répondre. Seule la
        // recherche toujours courante a le droit de toucher l'écran.
        guard !Task.isCancelled else { return }
        resultats = nouveaux
        enChargement = false
    }
}

// MARK: - Rangée de résultat en ligne

private struct RangeeResultat: View {
    let resultat: ResultatRecherche
    let langue: String
    let dejaAjoute: Bool
    var surAjout: (StatutLecture) -> Void

    var body: some View {
        HStack(spacing: 0) {
            NavigationLink {
                ApercuResultatView(resultat: resultat, langue: langue)
            } label: {
                contenu
            }
            .buttonStyle(.plain)

            if !dejaAjoute {
                controleAjout
            }
        }
        .padding(10)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .sensoryFeedback(.success, trigger: dejaAjoute)
    }

    private var contenu: some View {
        HStack(spacing: 12) {
            CouvertureView(
                urlString: resultat.couvertureURL,
                titre: resultat.titreAffiche(langue),
                coins: 4,
                manga: resultat.type != .livre
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
                    if resultat.estUnTome,
                       let numero = Tomaison.decomposer(resultat.titre).numero {
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
                    .frame(width: 44, height: 44)
                    .accessibilityLabel("Déjà dans la bibliothèque")
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var controleAjout: some View {
        if resultat.estSerie {
                // Ajouter la série crée son rayon complet, sans prétendre que
                // le lecteur possède soudain tous les volumes. Le statut global
                // reste modifiable ensuite depuis la fiche de la série.
                Button { surAjout(.wishlist) } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Couleurs.accent)
                        .frame(width: 44, height: 44)
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
                    Button { surAjout(.abandonne) } label: {
                        Label("Je l'ai abandonné", systemImage: "xmark.circle")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Couleurs.accent)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Ajouter")
        }
    }
}

#Preview {
    RechercheView()
        .modelContainer(Apercu.conteneur)
}

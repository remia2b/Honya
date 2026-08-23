import SwiftUI
import SwiftData

/// La librairie de Honya : un étal vivant calqué sur l'onglet Librairie
/// d'Apple Books — tendances du pays, rayons par genre, coups adaptés aux
/// goûts du lecteur, précommandes et classements. Tout vient du catalogue
/// Apple Books local ; chaque couverture ouvre la fiche d'aperçu.
struct DecouverteView: View {
    @Query private var objectifs: [Objectif]
    @Query private var series: [Serie]
    @Query private var exemplaires: [Exemplaire]

    @State private var tendances: [ResultatRecherche] = []
    @State private var gratuits: [ResultatRecherche] = []
    @State private var rayons: [String: [ResultatRecherche]] = [:]
    @State private var aVenir: [ResultatRecherche] = []
    @State private var pourVous: [(ancre: String, resultats: [ResultatRecherche])] = []
    @State private var chargementLance = false

    private var langue: String { objectifs.first?.languePrincipale ?? Langues.codeAppareil }

    /// Les rayons du fond de boutique, servis par le catalogue du pays.
    private static let rayonsCatalogue: [(cle: String, titre: String, terme: String)] = [
        ("manga", "Mangas populaires", "manga"),
        ("polar", "Polars & thrillers", "thriller"),
        ("romance", "Romance", "romance"),
        ("sf", "SF et fantasy", "fantasy"),
    ]

    /// Les grandes portes d'entrée, comme « Parcourir par genre » chez Apple.
    private static let genres: [(nom: String, terme: String, symbole: String, teinte: Color)] = [
        ("Romance", "romance", "heart.fill", Color(red: 0.85, green: 0.44, blue: 0.58)),
        ("Polar", "thriller", "magnifyingglass", Color(red: 0.34, green: 0.42, blue: 0.58)),
        ("SF & Fantasy", "fantasy", "moon.stars.fill", Color(red: 0.48, green: 0.38, blue: 0.72)),
        ("Mangas", "manga", "book.pages.fill", Color(red: 0.88, green: 0.50, blue: 0.30)),
        ("Jeunesse", "jeunesse", "sparkles", Color(red: 0.32, green: 0.60, blue: 0.44)),
        ("BD & Comics", "bande dessinée", "text.bubble.fill", Color(red: 0.80, green: 0.58, blue: 0.24)),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    EnteteEcran(titre: "Découverte")

                    if toutEstVide {
                        etalEnInstallation
                    } else {
                        if !tendances.isEmpty { sectionTendances }
                        rayonSection("manga")
                        bandeGouts
                        sectionAVenir
                        bandeGratuits
                        sectionClassements
                        rayonSection("polar")
                        rayonSection("romance")
                        rayonSection("sf")
                        sectionGenres
                    }
                }
                .padding(.bottom, 28)
            }
            .background(Color(uiColor: .systemBackground))
            .toolbar(.hidden, for: .navigationBar)
            .task { await charger() }
        }
    }

    private var toutEstVide: Bool {
        tendances.isEmpty && gratuits.isEmpty && rayons.values.allSatisfy(\.isEmpty)
    }

    private var etalEnInstallation: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Le libraire installe l'étal…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 130)
    }

    // MARK: - Chargement

    private func charger() async {
        guard !chargementLance else { return }
        chargementLance = true

        // Les classements d'abord : le flux RSS répond tout de suite.
        async let payants = Decouverte.classement(gratuits: false, langue: langue)
        async let libres = Decouverte.classement(gratuits: true, langue: langue)
        let (p, l) = await (payants, libres)
        withAnimation(.easeOut) {
            tendances = p
            gratuits = l
        }

        // Puis les rayons, un à un : la file d'attente du catalogue les espace,
        // les sections apparaissent au fil de l'eau (et restent en cache).
        for rayon in Self.rayonsCatalogue {
            let bruts = await Decouverte.rayonBrut(rayon.terme, langue: langue)
            withAnimation(.easeOut) {
                rayons[rayon.cle] = Decouverte.parSerie(bruts)
                integrerAVenir(bruts)
            }
        }

        await chargerPourVous()
    }

    private func integrerAVenir(_ bruts: [ResultatRecherche]) {
        var vus = Set(aVenir.map(\.id))
        let nouveaux = Decouverte.aParaitre(bruts).filter { vus.insert($0.id).inserted }
        aVenir = (aVenir + nouveaux)
            .sorted { ($0.dateSortie ?? .distantFuture) < ($1.dateSortie ?? .distantFuture) }
    }

    /// « Dans vos goûts » : des ancres tirées de la bibliothèque (l'auteur de
    /// la série du moment, le genre le plus présent), sans jamais reproposer
    /// ce que le lecteur possède déjà.
    private func chargerPourVous() async {
        let connues = basesBibliotheque
        var sections: [(ancre: String, resultats: [ResultatRecherche])] = []
        for (libelle, terme) in ancresGouts.prefix(2) {
            let resultats = Decouverte.parSerie(await Decouverte.rayonBrut(terme, langue: langue))
                .filter { !connues.contains(TexteUtil.normaliser(Tomaison.decomposer($0.titre).base)) }
            if resultats.count >= 4 {
                sections.append((ancre: libelle, resultats: resultats))
            }
        }
        withAnimation(.easeOut) { pourVous = sections }
    }

    private var ancresGouts: [(String, String)] {
        var ancres: [(String, String)] = []
        let recentes = series.sorted {
            ($0.derniereLecture ?? $0.dateAjout) > ($1.derniereLecture ?? $1.dateAjout)
        }
        if let serie = recentes.first, let auteur = serie.auteur, !auteur.isEmpty {
            ancres.append(("Parce que vous lisez \(serie.nomAffiche(langue))", auteur))
        }
        let genres = series.flatMap(\.genres)
            + exemplaires.compactMap(\.oeuvre).flatMap(\.genres)
        if let favori = Dictionary(grouping: genres, by: { $0 })
            .max(by: { $0.value.count < $1.value.count })?.key {
            ancres.append(("Vous aimez \(favori)", favori))
        }
        return ancres
    }

    private var basesBibliotheque: Set<String> {
        var bases = Set<String>()
        for serie in series {
            bases.insert(TexteUtil.normaliser(Tomaison.decomposer(serie.nom).base))
            for nom in serie.noms.values {
                bases.insert(TexteUtil.normaliser(Tomaison.decomposer(nom).base))
            }
        }
        for exemplaire in exemplaires {
            if let oeuvre = exemplaire.oeuvre {
                bases.insert(TexteUtil.normaliser(Tomaison.decomposer(oeuvre.titreOriginal).base))
            }
        }
        bases.remove("")
        return bases
    }

    // MARK: - Tendances (deux rangées, comme la Librairie)

    private var sectionTendances: some View {
        VStack(alignment: .leading, spacing: 10) {
            enTete("Nouveautés et tendances", sousTitre: "Les incontournables du moment")
                .padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(
                    rows: [
                        GridItem(.fixed(178), alignment: .top),
                        GridItem(.fixed(178), alignment: .top),
                    ],
                    spacing: 14
                ) {
                    ForEach(Array(tendances.prefix(16))) { resultat in
                        lienCouverture(resultat, largeur: 106)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }
        }
        .padding(.top, 6)
    }

    // MARK: - Rayons

    @ViewBuilder
    private func rayonSection(_ cle: String) -> some View {
        if let rayon = Self.rayonsCatalogue.first(where: { $0.cle == cle }),
           let resultats = rayons[cle], !resultats.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                separateur
                NavigationLink {
                    RayonCompletView(titre: rayon.titre, terme: rayon.terme, langue: langue)
                } label: {
                    enTete(rayon.titre, chevron: true)
                        .padding(.horizontal, 20)
                }
                .buttonStyle(.plain)
                etagere(resultats)
            }
        }
    }

    private func etagere(_ resultats: [ResultatRecherche], largeur: CGFloat = 106) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(Array(resultats.prefix(15))) { resultat in
                    lienCouverture(resultat, largeur: largeur)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Dans vos goûts (bande framboise)

    @ViewBuilder
    private var bandeGouts: some View {
        if !pourVous.isEmpty {
            bandeCouleur(Color(red: 0.42, green: 0.15, blue: 0.28)) {
                enTete("Dans vos goûts", sousTitre: "Choisi d'après votre bibliothèque")
                    .padding(.horizontal, 20)
                ForEach(pourVous, id: \.ancre) { section in
                    Text(section.ancre)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                    etagere(section.resultats, largeur: 96)
                }
            }
            .padding(.top, 22)
        }
    }

    // MARK: - Bientôt disponibles (précommandes)

    @ViewBuilder
    private var sectionAVenir: some View {
        if !aVenir.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                separateur
                enTete("Bientôt disponibles !", sousTitre: "Les précommandes du catalogue")
                    .padding(.horizontal, 20)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 18) {
                        ForEach(Array(aVenir.prefix(10))) { resultat in
                            lienCouverture(resultat, largeur: 148, avecDate: true)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
                .background(
                    RadialGradient(
                        colors: [Couleurs.accent.opacity(0.14), .clear],
                        center: .center, startRadius: 20, endRadius: 280
                    )
                )
            }
        }
    }

    // MARK: - Gratuits (bande verte, mosaïque)

    @ViewBuilder
    private var bandeGratuits: some View {
        if gratuits.count >= 5 {
            bandeCouleur(Color(red: 0.14, green: 0.32, blue: 0.22)) {
                enTete("Gratuits en ce moment", sousTitre: "Excellentes lectures à zéro euro")
                    .padding(.horizontal, 20)
                HStack(alignment: .top, spacing: 16) {
                    lienCouverture(gratuits[0], largeur: 150)
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12),
                        ],
                        spacing: 12
                    ) {
                        ForEach(Array(gratuits.dropFirst().prefix(4))) { resultat in
                            lienCouverture(resultat, largeur: 74)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.top, 22)
        }
    }

    // MARK: - Classements

    @ViewBuilder
    private var sectionClassements: some View {
        if !tendances.isEmpty || !gratuits.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                separateur
                enTete("Classements")
                    .padding(.horizontal, 20)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 30) {
                        if !tendances.isEmpty {
                            colonneClassement("Payant", resultats: tendances)
                        }
                        if !gratuits.isEmpty {
                            colonneClassement("Gratuit", resultats: gratuits)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private func colonneClassement(_ titre: String, resultats: [ResultatRecherche]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(titre)
                .font(.headline)
            ForEach(Array(resultats.prefix(5).enumerated()), id: \.element.id) { rang, resultat in
                NavigationLink {
                    ApercuResultatView(resultat: resultat, langue: langue)
                } label: {
                    HStack(spacing: 12) {
                        CouvertureView(
                            urlString: resultat.couvertureURL,
                            titre: resultat.titre,
                            coins: 4,
                            manga: resultat.type != .livre
                        )
                        .frame(width: 50)
                        Text("\(rang + 1)")
                            .font(.system(size: 24, weight: .semibold, design: .serif))
                            .monospacedDigit()
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(resultat.titre)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            if let auteur = resultat.auteurs.first {
                                Text(auteur)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(width: 300, alignment: .leading)
                }
                .buttonStyle(.plain)
                Divider().frame(width: 300)
            }
        }
    }

    // MARK: - Parcourir par genre

    private var sectionGenres: some View {
        VStack(alignment: .leading, spacing: 12) {
            separateur
            enTete("Parcourir par genre")
                .padding(.horizontal, 20)
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                ],
                spacing: 12
            ) {
                ForEach(Self.genres, id: \.nom) { genre in
                    NavigationLink {
                        RayonCompletView(titre: genre.nom, terme: genre.terme, langue: langue)
                    } label: {
                        ZStack(alignment: .bottomLeading) {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(genre.teinte.gradient)
                            Image(systemName: genre.symbole)
                                .font(.system(size: 42, weight: .bold))
                                .foregroundStyle(.white.opacity(0.32))
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                                .padding(12)
                            Text(genre.nom)
                                .font(.system(size: 19, weight: .semibold, design: .serif))
                                .foregroundStyle(.white)
                                .padding(14)
                        }
                        .frame(height: 102)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Briques communes

    private func lienCouverture(
        _ resultat: ResultatRecherche,
        largeur: CGFloat,
        avecDate: Bool = false
    ) -> some View {
        NavigationLink {
            ApercuResultatView(resultat: resultat, langue: langue)
        } label: {
            VStack(spacing: 5) {
                CouvertureView(
                    urlString: resultat.couvertureURL,
                    titre: resultat.titre,
                    coins: 6,
                    manga: resultat.type != .livre
                )
                .frame(width: largeur)
                .shadow(color: .black.opacity(0.4), radius: 10, y: 6)
                if avecDate, let sortie = resultat.dateSortie {
                    Text(sortie, format: .dateTime.day().month())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Couleurs.accent)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func enTete(
        _ titre: String,
        sousTitre: String? = nil,
        chevron: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Text(titre)
                    .font(.system(size: 25, weight: .semibold, design: .serif))
                    .foregroundStyle(.primary)
                if chevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            if let sousTitre {
                Text(sousTitre)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Une bande pleine largeur en couleur franche, comme « Nos coups de
    /// cœur » chez Apple Books. Le contenu passe en rendu sombre pour rester
    /// lisible sur la couleur, quel que soit le thème.
    private func bandeCouleur(
        _ couleur: Color,
        @ViewBuilder contenu: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            contenu()
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(couleur)
        .environment(\.colorScheme, .dark)
    }

    private var separateur: some View {
        Rectangle()
            .fill(Color(uiColor: .separator).opacity(0.5))
            .frame(height: 0.7)
            .padding(.horizontal, 20)
            .padding(.top, 22)
    }
}

// MARK: - Un rayon en entier (grille 3 colonnes)

struct RayonCompletView: View {
    let titre: String
    let terme: String
    let langue: String

    @State private var resultats: [ResultatRecherche] = []

    var body: some View {
        ScrollView {
            if resultats.isEmpty {
                ProgressView()
                    .padding(.top, 90)
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3),
                    spacing: 22
                ) {
                    ForEach(resultats) { resultat in
                        NavigationLink {
                            ApercuResultatView(resultat: resultat, langue: langue)
                        } label: {
                            VStack(spacing: 6) {
                                CouvertureView(
                                    urlString: resultat.couvertureURL,
                                    titre: resultat.titre,
                                    coins: 5,
                                    manga: resultat.type != .livre
                                )
                                .shadow(color: .black.opacity(0.3), radius: 7, y: 4)
                                Text(resultat.titre)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle(titre)
        .navigationBarTitleDisplayMode(.large)
        .task {
            guard resultats.isEmpty else { return }
            resultats = Decouverte.parSerie(
                await Decouverte.rayonBrut(terme, langue: langue)
            )
        }
    }
}

#Preview {
    DecouverteView()
        .modelContainer(Apercu.conteneur)
}

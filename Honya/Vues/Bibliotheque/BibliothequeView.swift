import SwiftUI
import SwiftData

// MARK: - Filtres, tris et éléments affichables

enum FiltreBibli: String, CaseIterable, Identifiable {
    case tous = "Tous"
    case enCours = "En cours"
    case aLire = "À lire"
    case lus = "Lus"
    case wishlist = "À acheter"
    case series = "Séries"

    var id: String { rawValue }

    /// Le libellé affiché passe par le catalogue ; `rawValue` reste la clé
    /// de stockage, qui ne doit jamais changer avec la langue.
    var libelle: String {
        switch self {
        case .tous: return String(localized: "Tous")
        case .enCours: return String(localized: "En cours")
        case .aLire: return String(localized: "À lire")
        case .lus: return String(localized: "Lus")
        case .wishlist: return String(localized: "À acheter")
        case .series: return String(localized: "Séries")
        }
    }
}

enum TriBibli: String, CaseIterable, Identifiable {
    case recents = "Ajouts récents"
    case titre = "Titre"
    case note = "Note"

    var id: String { rawValue }

    var libelle: String {
        switch self {
        case .recents: return String(localized: "Ajouts récents")
        case .titre: return String(localized: "Titre")
        case .note: return String(localized: "Note")
        }
    }
}

enum ElementBibli: Identifiable {
    case livre(Exemplaire)
    case serie(Serie)

    var id: PersistentIdentifier {
        switch self {
        case .livre(let exemplaire): return exemplaire.persistentModelID
        case .serie(let serie): return serie.persistentModelID
        }
    }
}

// MARK: - Bibliothèque

struct BibliothequeView: View {
    var allerRecherche: () -> Void

    @Environment(\.modelContext) private var contexte
    @Query private var exemplaires: [Exemplaire]
    @Query private var series: [Serie]
    @Query private var objectifs: [Objectif]

    @State private var filtre: FiltreBibli = .tous
    @State private var tri: TriBibli = .recents
    @State private var enListe = false
    @State private var filtreTexte = ""

    private var langue: String { objectifs.first?.languePrincipale ?? Langues.codeAppareil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    EnteteEcran(titre: "Bibliothèque") {
                        HStack(spacing: 12) {
                            NavigationLink {
                                CollectionsView()
                            } label: {
                                boutonRond("square.stack.fill")
                            }
                            .accessibilityLabel("Collections")
                            Menu {
                                Picker("Trier par", selection: $tri) {
                                    ForEach(TriBibli.allCases) { Text($0.libelle).tag($0) }
                                }
                                Divider()
                                Button {
                                    enListe.toggle()
                                } label: {
                                    Label(
                                        enListe ? "Afficher en grille" : "Afficher en liste",
                                        systemImage: enListe ? "square.grid.2x2" : "list.bullet"
                                    )
                                }
                            } label: {
                                boutonRond("line.3.horizontal.decrease")
                            }
                            Button(action: allerRecherche) {
                                boutonRond("plus", accent: true)
                            }
                            .accessibilityLabel("Ajouter")
                        }
                    }

                    chipsFiltres

                    if elements.isEmpty {
                        ContentUnavailableView {
                            Label("Rien ici pour l'instant", systemImage: "books.vertical")
                        } description: {
                            Text(filtre == .wishlist
                                 ? "Ajoutez des envies depuis la recherche."
                                 : "Ajoutez des livres ou des séries depuis la recherche.")
                        } actions: {
                            Button("Ajouter", action: allerRecherche)
                                .buttonStyle(.borderedProminent)
                                .tint(Couleurs.accent)
                        }
                        .padding(.top, 50)
                    } else if enListe {
                        listeElements
                            .padding(.horizontal, 20)
                    } else {
                        grilleElements
                            .padding(.horizontal, 20)
                    }

                    if !elements.isEmpty {
                        Text(legende)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)
                            .monospacedDigit()
                    }
                }
                .padding(.bottom, 24)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    /// Boutons ronds de l'en-tête, à la Apple Books : plus gros, plus francs.
    private func boutonRond(_ symbole: String, accent: Bool = false) -> some View {
        Image(systemName: symbole)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(accent ? Color.white : .primary)
            .frame(width: 36, height: 36)
            .background(
                accent
                    ? AnyShapeStyle(Couleurs.accent)
                    : AnyShapeStyle(Color(uiColor: .secondarySystemFill)),
                in: Circle()
            )
    }

    // MARK: - Chips

    private var chipsFiltres: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FiltreBibli.allCases) { cas in
                    ChipFiltre(
                        libelle: cas.libelle,
                        nombre: compte(pour: cas),
                        actif: filtre == cas
                    ) {
                        withAnimation(.snappy) { filtre = cas }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func compte(pour cas: FiltreBibli) -> Int? {
        switch cas {
        case .tous: return exemplaires.count + series.count
        case .enCours: return exemplaires.filter { $0.statut == .enCours }.count
            + series.filter { $0.statut == .enCours }.count
        case .aLire: return exemplaires.filter { $0.statut == .aLire }.count
            + series.filter { $0.statut == .aLire }.count
        case .lus: return exemplaires.filter { $0.statut == .lu }.count
            + series.filter { $0.statut == .lu }.count
        case .wishlist: return exemplaires.filter { $0.statut == .wishlist }.count
            + series.filter { $0.statut == .wishlist }.count
        case .series: return series.count
        }
    }

    // MARK: - Données filtrées et triées

    private var elements: [ElementBibli] {
        var resultat: [ElementBibli]
        switch filtre {
        case .tous:
            resultat = exemplaires.map(ElementBibli.livre) + series.map(ElementBibli.serie)
        case .enCours:
            resultat = exemplaires.filter { $0.statut == .enCours }.map(ElementBibli.livre)
                + series.filter { $0.statut == .enCours }.map(ElementBibli.serie)
        case .aLire:
            resultat = exemplaires.filter { $0.statut == .aLire }.map(ElementBibli.livre)
                + series.filter { $0.statut == .aLire }.map(ElementBibli.serie)
        case .lus:
            resultat = exemplaires.filter { $0.statut == .lu }.map(ElementBibli.livre)
                + series.filter { $0.statut == .lu }.map(ElementBibli.serie)
        case .wishlist:
            resultat = exemplaires.filter { $0.statut == .wishlist }.map(ElementBibli.livre)
                + series.filter { $0.statut == .wishlist }.map(ElementBibli.serie)
        case .series:
            resultat = series.map(ElementBibli.serie)
        }
        return trier(resultat)
    }

    private func trier(_ liste: [ElementBibli]) -> [ElementBibli] {
        switch tri {
        case .recents:
            return liste.sorted { dateAjout($0) > dateAjout($1) }
        case .titre:
            return liste.sorted {
                titre($0).localizedCaseInsensitiveCompare(titre($1)) == .orderedAscending
            }
        case .note:
            return liste.sorted { note($0) > note($1) }
        }
    }

    private func dateAjout(_ element: ElementBibli) -> Date {
        switch element {
        case .livre(let exemplaire): return exemplaire.oeuvre?.dateAjout ?? .distantPast
        case .serie(let serie): return serie.dateAjout
        }
    }

    private func titre(_ element: ElementBibli) -> String {
        switch element {
        case .livre(let exemplaire): return exemplaire.oeuvre?.titre(langue) ?? ""
        case .serie(let serie): return serie.nomAffiche(langue)
        }
    }

    private func note(_ element: ElementBibli) -> Int {
        switch element {
        case .livre(let exemplaire): return exemplaire.note ?? -1
        case .serie: return -1
        }
    }

    private var legende: String {
        let pretes = exemplaires.filter { $0.preteA != nil }.count
        var morceaux = [
            String(localized: "\(exemplaires.count) livres"),
            String(localized: "\(series.count) séries"),
        ]
        if pretes > 0 { morceaux.append(String(localized: "\(pretes) prêtés")) }
        return morceaux.joined(separator: " · ")
    }

    // MARK: - Grille

    private var grilleElements: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 100, maximum: 150), spacing: 14)],
            spacing: 20
        ) {
            ForEach(elements) { element in
                switch element {
                case .livre(let exemplaire):
                    if let oeuvre = exemplaire.oeuvre {
                        CelluleLivre(exemplaire: exemplaire, oeuvre: oeuvre, langue: langue)
                    }
                case .serie(let serie):
                    CelluleSerie(serie: serie, langue: langue)
                }
            }
        }
    }

    // MARK: - Liste

    private var listeElements: some View {
        LazyVStack(spacing: 8) {
            ForEach(elements) { element in
                switch element {
                case .livre(let exemplaire):
                    if let oeuvre = exemplaire.oeuvre {
                        RangeeLivre(exemplaire: exemplaire, oeuvre: oeuvre, langue: langue)
                    }
                case .serie(let serie):
                    RangeeSerie(serie: serie, langue: langue)
                }
            }
        }
    }
}

// MARK: - Cellule livre (grille)

private struct CelluleLivre: View {
    @Bindable var exemplaire: Exemplaire
    let oeuvre: Oeuvre
    let langue: String

    @Environment(\.modelContext) private var contexte
    @State private var confirmerSuppression = false
    @State private var etagereVisible = false

    var body: some View {
        NavigationLink {
            FicheOeuvreView(oeuvre: oeuvre)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                CouvertureView(
                    urlString: oeuvre.couvertureAffichee,
                    titre: oeuvre.titre(langue),
                    auteur: oeuvre.auteurPrincipal,
                    manga: oeuvre.type != .livre
                )
                // Le badge vit SOUS la couverture, comme chez Apple Books :
                // l'image reste propre.
                HStack {
                    BadgeStatutView(statut: exemplaire.statut)
                    Spacer(minLength: 0)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu { menuContextuel }
        .alerteNouvelleEtagere(.oeuvre(oeuvre), visible: $etagereVisible)
        .confirmationDialog(
            "Retirer « \(oeuvre.titre(langue)) » de la bibliothèque ?",
            isPresented: $confirmerSuppression,
            titleVisibility: .visible
        ) {
            Button("Retirer", role: .destructive) {
                contexte.delete(oeuvre)
            }
        }
    }

    @ViewBuilder
    private var menuContextuel: some View {
        Menu("Statut") {
            ForEach(StatutLecture.allCases) { statut in
                Button {
                    exemplaire.changerStatut(statut)
                    BadgesEngine.evaluer(dans: contexte)
                } label: {
                    Label(statut.libelle, systemImage: statut.symbole)
                }
            }
        }
        Button {
            exemplaire.aSuivre.toggle()
        } label: {
            Label(
                exemplaire.aSuivre ? "Retirer d'À suivre" : "Ajouter à À suivre",
                systemImage: exemplaire.aSuivre ? "text.badge.minus" : "text.badge.plus"
            )
        }
        MenuEtageres(cible: .oeuvre(oeuvre), creationVisible: $etagereVisible)
        Divider()
        Button(role: .destructive) {
            confirmerSuppression = true
        } label: {
            Label("Retirer de la bibliothèque", systemImage: "trash")
        }
    }
}

// MARK: - Cellule série (pile de couvertures + badge n/total)

private struct CelluleSerie: View {
    let serie: Serie
    let langue: String

    var body: some View {
        NavigationLink {
            FicheSerieView(serie: serie)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    // Effet de pile : deux « cartes » derrière la couverture.
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color(uiColor: .systemFill))
                        .aspectRatio(2.0 / 3.0, contentMode: .fit)
                        .scaleEffect(0.9)
                        .offset(y: -10)
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemFill))
                        .aspectRatio(2.0 / 3.0, contentMode: .fit)
                        .scaleEffect(0.95)
                        .offset(y: -5)
                    CouvertureView(
                        urlString: serie.couvertureAffichee,
                        titre: serie.nomAffiche(langue),
                        auteur: serie.auteur,
                        manga: serie.type != .livre
                    )
                }
                // Badge et progression SOUS la couverture, comme chez Apple
                // Books : la couverture reste propre.
                HStack {
                    BadgeStatutView(statut: serie.statut)
                    Spacer(minLength: 0)
                    Text("\(serie.nbPossedes)/\(serie.tomesTotal ?? serie.tomes.count)")
                        .font(.caption2.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .menuSerie(serie, langue: langue)
    }
}

// MARK: - Rangée livre (liste)

private struct RangeeLivre: View {
    @Bindable var exemplaire: Exemplaire
    let oeuvre: Oeuvre
    let langue: String

    var body: some View {
        NavigationLink {
            FicheOeuvreView(oeuvre: oeuvre)
        } label: {
            HStack(spacing: 12) {
                CouvertureView(
                    urlString: oeuvre.couvertureAffichee,
                    titre: oeuvre.titre(langue),
                    coins: 4,
                    manga: oeuvre.type != .livre
                )
                .frame(width: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text(oeuvre.titre(langue))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(oeuvre.auteurPrincipal)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if exemplaire.statut == .enCours {
                        BarreProgression(valeur: exemplaire.progression, hauteur: 4)
                    }
                }
                Spacer()
                if let preteA = exemplaire.preteA {
                    Label(preteA, systemImage: "person.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                }
                BadgeStatutView(statut: exemplaire.statut)
            }
            .padding(10)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Rangée série (liste)

private struct RangeeSerie: View {
    let serie: Serie
    let langue: String

    var body: some View {
        NavigationLink {
            FicheSerieView(serie: serie)
        } label: {
            HStack(spacing: 12) {
                CouvertureView(
                    urlString: serie.couvertureAffichee,
                    titre: serie.nomAffiche(langue),
                    coins: 4,
                    manga: serie.type != .livre
                )
                .frame(width: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text(serie.nomAffiche(langue))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text("\(serie.nbPossedes) possédés · \(serie.nbLus) lus")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
                Image(systemName: "square.stack.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .menuSerie(serie, langue: langue)
    }
}

// MARK: - Appui long sur une série : changer l'état sans ouvrir la fiche

private struct MenuSerie: ViewModifier {
    let serie: Serie
    let langue: String

    @Environment(\.modelContext) private var contexte
    @State private var confirmerSuppression = false
    @State private var etagereVisible = false

    func body(content: Content) -> some View {
        content
            .contextMenu {
                MenuEtageres(cible: .serie(serie), creationVisible: $etagereVisible)
                if let prochain = serie.prochainALire {
                    Button {
                        prochain.lu = true
                        prochain.dateLu = Date()
                        BadgesEngine.evaluer(dans: contexte)
                        if serie.estTerminee {
                            Celebrations.partage.feter("Série terminée !")
                        }
                    } label: {
                        Label("Tome \(prochain.numero) lu", systemImage: "checkmark.circle")
                    }
                }
                if !serie.estTerminee && !serie.tomesParus.isEmpty {
                    Button {
                        for tome in serie.tomesParus {
                            tome.possede = true
                            if !tome.lu {
                                tome.lu = true
                                tome.dateLu = Date()
                            }
                        }
                        BadgesEngine.evaluer(dans: contexte)
                        Celebrations.partage.feter("Série terminée !")
                    } label: {
                        Label("Toute la série lue", systemImage: "checkmark.seal")
                    }
                }
                Divider()
                Button(role: .destructive) {
                    confirmerSuppression = true
                } label: {
                    Label("Retirer de ma bibliothèque", systemImage: "trash")
                }
            }
            .alerteNouvelleEtagere(.serie(serie), visible: $etagereVisible)
            .confirmationDialog(
                "Retirer « \(serie.nomAffiche(langue)) » et tous ses tomes ?",
                isPresented: $confirmerSuppression,
                titleVisibility: .visible
            ) {
                Button("Retirer", role: .destructive) {
                    contexte.delete(serie)
                }
            }
    }
}

private extension View {
    func menuSerie(_ serie: Serie, langue: String) -> some View {
        modifier(MenuSerie(serie: serie, langue: langue))
    }
}

#Preview {
    BibliothequeView(allerRecherche: {})
        .modelContainer(Apercu.conteneur)
}

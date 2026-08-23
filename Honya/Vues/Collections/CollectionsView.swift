import SwiftUI
import SwiftData

/// Les étagères que l'on compose soi-même, à la manière des collections
/// d'Apple Books — plus celles que Honya devine à votre place.
struct CollectionsView: View {
    @Environment(\.modelContext) private var contexte
    @Query(sort: \Collection.dateCreation, order: .reverse) private var collections: [Collection]
    @Query private var exemplaires: [Exemplaire]
    @Query private var series: [Serie]
    @Query private var objectifs: [Objectif]

    @State private var creationVisible = false
    @State private var nouveauNom = ""

    private var langue: String { objectifs.first?.languePrincipale ?? Langues.codeAppareil }

    var body: some View {
        List {
            Section {
                ForEach(StatutLecture.allCases) { statut in
                    // Une série a elle aussi un statut, déduit de ses tomes :
                    // sans elle, ces étagères restaient à zéro pour qui ne
                    // collectionne que des mangas.
                    let livres = exemplaires.filter { $0.statut == statut }
                    let seriesStatut = series.filter { $0.statut == statut }
                    NavigationLink {
                        GrilleOeuvres(
                            oeuvres: livres.compactMap(\.oeuvre),
                            series: seriesStatut,
                            langue: langue,
                            messageVide: "Rien avec ce statut pour l'instant."
                        )
                        .navigationTitle(statut.libelle)
                        .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        Label {
                            HStack {
                                Text(statut.libelle)
                                Spacer()
                                Text("\(livres.count + seriesStatut.count)")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        } icon: {
                            Image(systemName: statut.symbole)
                                .foregroundStyle(statut.couleur)
                        }
                    }
                }
                NavigationLink {
                    GrilleOeuvres(
                        oeuvres: [],
                        series: series,
                        langue: langue,
                        messageVide: "Aucune série suivie."
                    )
                    .navigationTitle("Séries")
                    .navigationBarTitleDisplayMode(.inline)
                } label: {
                    Label {
                        HStack {
                            Text("Séries")
                            Spacer()
                            Text("\(series.count)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    } icon: {
                        Image(systemName: "square.stack.fill")
                            .foregroundStyle(Couleurs.accent)
                    }
                }
            } header: {
                Text("Par statut")
            }

            Section {
                if collections.isEmpty {
                    Text("Créez une étagère ici avec « + », puis rangez-y un livre ou une série depuis sa fiche (menu « … ») ou par un appui long dans la bibliothèque.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(collections) { collection in
                    NavigationLink {
                        DetailCollectionView(collection: collection, langue: langue)
                    } label: {
                        Label {
                            HStack {
                                Text(collection.nom)
                                Spacer()
                                Text("\(collection.nombre)")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        } icon: {
                            Image(systemName: collection.symbole)
                                .foregroundStyle(Couleurs.accent)
                        }
                    }
                }
                .onDelete { index in
                    index.map { collections[$0] }.forEach(contexte.delete)
                }
            } header: {
                Text("Mes étagères")
            }

            Section {
                ForEach(CollectionAuto.allCases) { auto in
                    let livres = auto.exemplaires(exemplaires)
                    let sfx = auto.series(series)
                    if !livres.isEmpty || !sfx.isEmpty {
                        NavigationLink {
                            DetailCollectionAutoView(auto: auto, langue: langue)
                        } label: {
                            Label {
                                HStack {
                                    Text(auto.nom)
                                    Spacer()
                                    Text("\(livres.count + sfx.count)")
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                            } icon: {
                                Image(systemName: auto.symbole)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("Automatiques")
            } footer: {
                Text("Ces étagères se remplissent toutes seules d'après vos statuts, vos notes et vos dates d'achat.")
            }
        }
        .navigationTitle("Collections")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { creationVisible = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Nouvelle collection")
            }
        }
        .alert("Nouvelle étagère", isPresented: $creationVisible) {
            TextField("Son nom", text: $nouveauNom)
            Button("Créer") {
                let propre = nouveauNom.trimmingCharacters(in: .whitespaces)
                guard !propre.isEmpty else { return }
                contexte.insert(Collection(nom: propre))
                nouveauNom = ""
            }
            Button("Annuler", role: .cancel) { nouveauNom = "" }
        }
    }
}

// MARK: - Contenu d'une étagère personnelle

struct DetailCollectionView: View {
    @Bindable var collection: Collection
    let langue: String

    var body: some View {
        GrilleOeuvres(
            oeuvres: collection.oeuvres,
            series: collection.series,
            langue: langue,
            messageVide: "Ajoutez-y des livres depuis leur fiche, ou d'un appui long dans la bibliothèque."
        )
        .navigationTitle(collection.nom)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Contenu d'une étagère automatique

struct DetailCollectionAutoView: View {
    let auto: CollectionAuto
    let langue: String

    @Query private var exemplaires: [Exemplaire]
    @Query private var series: [Serie]

    var body: some View {
        GrilleOeuvres(
            oeuvres: auto.exemplaires(exemplaires).compactMap(\.oeuvre),
            series: auto.series(series),
            langue: langue,
            messageVide: "Rien ici pour l'instant."
        )
        .navigationTitle(auto.nom)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Grille réutilisable

struct GrilleOeuvres: View {
    let oeuvres: [Oeuvre]
    let series: [Serie]
    let langue: String
    var messageVide: String

    var body: some View {
        ScrollView {
            if oeuvres.isEmpty && series.isEmpty {
                ContentUnavailableView(
                    "Étagère vide",
                    systemImage: "books.vertical",
                    description: Text(messageVide)
                )
                .padding(.top, 60)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 100, maximum: 150), spacing: 14)],
                    spacing: 20
                ) {
                    ForEach(oeuvres) { oeuvre in
                        NavigationLink {
                            FicheOeuvreView(oeuvre: oeuvre)
                        } label: {
                            CouvertureView(
                                urlString: oeuvre.couvertureAffichee,
                                titre: oeuvre.titre(langue),
                                auteur: oeuvre.auteurPrincipal
                            )
                            .overlay(alignment: .bottomLeading) {
                                if let statut = oeuvre.exemplaire?.statut {
                                    BadgeStatutView(statut: statut).padding(6)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(series) { serie in
                        NavigationLink {
                            FicheSerieView(serie: serie)
                        } label: {
                            CouvertureView(
                                urlString: serie.couvertureAffichee,
                                titre: serie.nomAffiche(langue),
                                auteur: serie.auteur
                            )
                            .overlay(alignment: .topTrailing) {
                                Text("\(serie.nbPossedes)/\(serie.tomes.count)")
                                    .font(.system(size: 9, weight: .heavy))
                                    .monospacedDigit()
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(.black.opacity(0.72), in: Capsule())
                                    .padding(6)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }
}

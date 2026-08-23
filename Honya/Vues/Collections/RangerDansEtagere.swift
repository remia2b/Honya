import SwiftUI
import SwiftData

/// Ce qu'on peut ranger sur une étagère : un livre ou une série.
enum CibleEtagere {
    case oeuvre(Oeuvre)
    case serie(Serie)

    var nom: String {
        switch self {
        case .oeuvre(let oeuvre): return oeuvre.titreOriginal
        case .serie(let serie): return serie.nom
        }
    }

    func estDans(_ collection: Collection) -> Bool {
        switch self {
        case .oeuvre(let oeuvre):
            return collection.oeuvres.contains { $0.persistentModelID == oeuvre.persistentModelID }
        case .serie(let serie):
            return collection.series.contains { $0.persistentModelID == serie.persistentModelID }
        }
    }

    func basculer(dans collection: Collection) {
        switch self {
        case .oeuvre(let oeuvre):
            if let index = collection.oeuvres.firstIndex(where: {
                $0.persistentModelID == oeuvre.persistentModelID
            }) {
                collection.oeuvres.remove(at: index)
            } else {
                collection.oeuvres.append(oeuvre)
            }
        case .serie(let serie):
            if let index = collection.series.firstIndex(where: {
                $0.persistentModelID == serie.persistentModelID
            }) {
                collection.series.remove(at: index)
            } else {
                collection.series.append(serie)
            }
        }
    }
}

// MARK: - Le menu « Ranger dans une étagère »
//
// À placer dans un menu existant (fiche ou appui long). Il propose toujours
// de créer une étagère : sans ça, tant qu'on n'en avait pas, rien ne
// laissait deviner que la fonction existait.

struct MenuEtageres: View {
    let cible: CibleEtagere
    @Binding var creationVisible: Bool

    @Query(sort: \Collection.dateCreation, order: .reverse) private var collections: [Collection]

    var body: some View {
        Menu("Ranger dans une étagère") {
            ForEach(collections) { collection in
                Button {
                    cible.basculer(dans: collection)
                } label: {
                    Label(
                        collection.nom,
                        systemImage: cible.estDans(collection) ? "checkmark" : collection.symbole
                    )
                }
            }
            if !collections.isEmpty { Divider() }
            Button {
                creationVisible = true
            } label: {
                Label("Nouvelle étagère…", systemImage: "plus")
            }
        }
    }
}

// MARK: - Créer une étagère et y ranger dans la foulée

struct AlerteNouvelleEtagere: ViewModifier {
    let cible: CibleEtagere
    @Binding var visible: Bool

    @Environment(\.modelContext) private var contexte
    @State private var nom = ""

    func body(content: Content) -> some View {
        content.alert("Nouvelle étagère", isPresented: $visible) {
            TextField("Son nom", text: $nom)
            Button("Créer") {
                let propre = nom.trimmingCharacters(in: .whitespaces)
                guard !propre.isEmpty else { return }
                let collection = Collection(nom: propre)
                contexte.insert(collection)
                cible.basculer(dans: collection)
                nom = ""
            }
            Button("Annuler", role: .cancel) { nom = "" }
        } message: {
            Text("« \(cible.nom) » y sera rangé aussitôt.")
        }
    }
}

extension View {
    func alerteNouvelleEtagere(_ cible: CibleEtagere, visible: Binding<Bool>) -> some View {
        modifier(AlerteNouvelleEtagere(cible: cible, visible: visible))
    }
}

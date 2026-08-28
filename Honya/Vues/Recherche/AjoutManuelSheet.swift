import Foundation
import SwiftUI
import SwiftData

/// Porte de sortie quand les catalogues ne connaissent pas encore une édition.
///
/// La saisie produit le même `ResultatRecherche` que les fournisseurs : toute la
/// déduplication, la tomaison et les limites Honya+ restent ainsi centralisées
/// dans `ImportService`.
struct AjoutManuelSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var contexte

    @State private var titre: String
    @State private var auteur: String
    @State private var isbn: String
    @State private var type: TypeOeuvre
    @State private var tome: String
    @State private var pages: String
    @State private var couvertureURL: String
    @State private var langue: String
    @State private var statut: StatutLecture
    @State private var tentativeEnregistrement = false
    @State private var champsVisites: Set<Champ> = []
    @State private var plusVisible = false
    @FocusState private var champActif: Champ?

    private let surAjout: (ResultatRecherche) -> Void

    private enum Champ: Hashable {
        case titre, auteur, isbn, tome, pages, couverture
    }

    init(
        isbnInitial: String = "",
        titreInitial: String = "",
        typeInitial: TypeOeuvre = .livre,
        langueInitiale: String = Langues.codeAppareil,
        statutInitial: StatutLecture = .aLire,
        surAjout: @escaping (ResultatRecherche) -> Void = { _ in }
    ) {
        let isbnCanonique = ISBNUtil.canonique(isbnInitial)
        let isbnAffiche = isbnCanonique ?? ISBNUtil.normaliser(isbnInitial)
        // La langue reste un choix explicite : le groupe d'enregistrement de
        // l'ISBN décrit l'éditeur, pas nécessairement la langue du livre.
        let langueCandidate = langueInitiale
        let langueDeBase = Locale(identifier: langueCandidate)
            .language.languageCode?.identifier ?? langueCandidate
        let langueResolue = Langues.codes.contains(langueDeBase)
            ? langueDeBase
            : Langues.codeAppareil
        let titreNet = titreInitial.trimmingCharacters(in: .whitespacesAndNewlines)
        let tomaisonInitiale: (base: String, numero: Int?) = typeInitial == .livre
            ? (base: titreNet, numero: nil)
            : Tomaison.decomposer(titreNet)

        _titre = State(initialValue: tomaisonInitiale.base)
        _auteur = State(initialValue: "")
        _isbn = State(initialValue: isbnAffiche)
        _type = State(initialValue: typeInitial)
        _tome = State(initialValue: tomaisonInitiale.numero.map { String($0) } ?? "")
        _pages = State(initialValue: "")
        _couvertureURL = State(initialValue: "")
        _langue = State(initialValue: langueResolue)
        _statut = State(initialValue: statutInitial)
        self.surAjout = surAjout
    }

    var body: some View {
        NavigationStack {
            Form {
                apercu

                Section("Informations") {
                    LabeledContent {
                        TextField("Titre", text: $titre, axis: .vertical)
                            .multilineTextAlignment(.trailing)
                            .focused($champActif, equals: .titre)
                            .submitLabel(.next)
                    } label: {
                        HStack(spacing: 0) {
                            Text("Titre")
                            Text(verbatim: " *")
                                .foregroundStyle(.red)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Titre requis")
                    }
                    if afficheErreur(.titre, invalide: !titreValide) {
                        messageErreur(Text("Titre requis"))
                    }

                    LabeledContent {
                        TextField("Auteur", text: $auteur)
                            .multilineTextAlignment(.trailing)
                            .focused($champActif, equals: .auteur)
                            .submitLabel(.next)
                    } label: {
                        Text("Auteur")
                    }

                    Picker("Type", selection: $type) {
                        ForEach(TypeOeuvre.allCases) { type in
                            Text(type.libelle).tag(type)
                        }
                    }

                    LabeledContent {
                        TextField("Tome", text: $tome)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                            .focused($champActif, equals: .tome)
                    } label: {
                        Text("Tome")
                    }
                    if afficheErreur(.tome, invalide: !tomeValide) {
                        messageErreur(Text("Valeur invalide"))
                    }

                    LabeledContent("Pages") {
                        TextField("Pages", text: $pages)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                            .focused($champActif, equals: .pages)
                    }
                    if afficheErreur(.pages, invalide: !pagesValides) {
                        messageErreur(Text("Valeur invalide"))
                    }
                }

                Section("Langue de l'édition") {
                    LabeledContent("ISBN") {
                        TextField("ISBN", text: $isbn)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.asciiCapable)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .focused($champActif, equals: .isbn)
                    }
                    if afficheErreur(.isbn, invalide: !isbnValide) {
                        messageErreur(Text("ISBN invalide"))
                    }

                    Picker("Langue", selection: $langue) {
                        ForEach(Langues.toutes) { langue in
                            Text(langue.nomNatif).tag(langue.code)
                        }
                    }

                    LabeledContent {
                        TextField("URL de couverture", text: $couvertureURL)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($champActif, equals: .couverture)
                    } label: {
                        Text("URL de couverture")
                    }
                    if afficheErreur(.couverture, invalide: !couvertureValide) {
                        messageErreur(Text("URL invalide"))
                    }
                }

                Section {
                    Picker("Statut", selection: $statut) {
                        ForEach(StatutLecture.allCases) { statut in
                            Label(statut.libelle, systemImage: statut.symbole)
                                .tag(statut)
                        }
                    }
                }
            }
            .navigationTitle("Ajouter un livre")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer", action: enregistrer)
                        .fontWeight(.semibold)
                }
            }
            .onChange(of: champActif) { ancien, _ in
                if let ancien { champsVisites.insert(ancien) }
            }
            .ecranHonyaPlus(
                $plusVisible,
                verrou: .bibliotheque(couvertures: [couvertureApercu].compactMap { $0 })
            )
        }
    }

    private var apercu: some View {
        Section {
            HStack {
                Spacer()
                CouvertureView(
                    urlString: couvertureApercu,
                    titre: titreComplet.isEmpty ? String(localized: "Livre") : titreComplet,
                    auteur: auteurPropre,
                    coins: 7,
                    manga: type == .manga
                )
                .frame(width: 86)
                Spacer()
            }
            .listRowBackground(Color.clear)
            .accessibilityHidden(true)
        }
    }

    private func messageErreur(_ texte: Text) -> some View {
        Label {
            texte
        } icon: {
            Image(systemName: "exclamationmark.circle.fill")
        }
        .font(.caption)
        .foregroundStyle(.red)
    }

    private func afficheErreur(_ champ: Champ, invalide: Bool) -> Bool {
        invalide && (tentativeEnregistrement || champsVisites.contains(champ))
    }

    private func enregistrer() {
        tentativeEnregistrement = true
        guard formulaireValide else {
            ciblerPremiereErreur()
            return
        }

        let resultat = resultatManuel()
        switch ImportService.ajouter(resultat, statut: statut, dans: contexte) {
        case .limiteAtteinte:
            plusVisible = true
        case .oeuvre, .serie, .dejaPresent:
            surAjout(resultat)
            dismiss()
        }
    }

    private func ciblerPremiereErreur() {
        if !titreValide { champActif = .titre }
        else if !tomeValide { champActif = .tome }
        else if !pagesValides { champActif = .pages }
        else if !isbnValide { champActif = .isbn }
        else if !couvertureValide { champActif = .couverture }
    }

    private func resultatManuel() -> ResultatRecherche {
        let isbnCanonique = ISBNUtil.canonique(isbnPropre)
        let identifiant = isbnCanonique.map { "manuel:isbn:\($0)" }
            ?? "manuel:\(UUID().uuidString.lowercased())"
        var resultat = ResultatRecherche(
            id: identifiant,
            titre: titreComplet,
            source: String(localized: "Ajout manuel")
        )
        resultat.auteurs = auteurPropre.isEmpty ? [] : [auteurPropre]
        resultat.type = type
        resultat.pages = pagesSaisies
        resultat.couvertureURL = couvertureApercu
        resultat.isbn = isbnCanonique
        resultat.langue = langue
        resultat.titresParLangue[langue] = titreComplet
        resultat.saisieManuelle = true
        return resultat
    }

    private var formulaireValide: Bool {
        titreValide && tomeValide && pagesValides && isbnValide && couvertureValide
    }

    private var titreValide: Bool { !titrePropre.isEmpty }
    private var titrePropre: String { propre(titre) }
    private var auteurPropre: String { propre(auteur) }
    private var isbnPropre: String { propre(isbn) }

    private var titreComplet: String {
        guard !titrePropre.isEmpty else { return "" }
        guard let numero = tomeSaisi else { return titrePropre }
        let decomposition = Tomaison.decomposer(titrePropre)
        let base = decomposition.numero == nil ? titrePropre : decomposition.base
        // Le champ « Tome » est un choix explicite, y compris pour une saga
        // cataloguée comme livre. Le marqueur universel « # » conserve cette
        // intention sans injecter un mot français dans les autres langues.
        return "\(base) #\(numero)"
    }

    private var tomeSaisi: Int? {
        guard let numero = entierPositif(tome), numero <= 4_000 else { return nil }
        return numero
    }
    private var pagesSaisies: Int? { entierPositif(pages) }
    private var tomeValide: Bool { propre(tome).isEmpty || tomeSaisi != nil }
    private var pagesValides: Bool { propre(pages).isEmpty || pagesSaisies != nil }
    private var isbnValide: Bool {
        isbnPropre.isEmpty || ISBNUtil.canonique(isbnPropre) != nil
    }

    private var couvertureApercu: String? {
        let valeur = propre(couvertureURL)
        return valeur.isEmpty || !couvertureValide ? nil : valeur
    }

    private var couvertureValide: Bool {
        let valeur = propre(couvertureURL)
        guard !valeur.isEmpty else { return true }
        guard let composants = URLComponents(string: valeur),
              let schema = composants.scheme?.lowercased(),
              ["http", "https"].contains(schema),
              let hote = composants.host, !hote.isEmpty
        else { return false }
        return true
    }

    private func entierPositif(_ valeur: String) -> Int? {
        guard let entier = Int(propre(valeur)), entier > 0 else { return nil }
        return entier
    }

    private func propre(_ valeur: String) -> String {
        valeur.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#Preview {
    AjoutManuelSheet(
        isbnInitial: "9782749958194",
        titreInitial: "Instinct 2",
        typeInitial: .bd,
        langueInitiale: "fr"
    )
    .modelContainer(Apercu.conteneur)
}

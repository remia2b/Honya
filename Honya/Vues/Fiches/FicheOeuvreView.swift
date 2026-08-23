import SwiftUI
import SwiftData

/// Fiche livre, calquée sur la page produit d'Apple Books : grande couverture
/// au rendu de vrai livre, titre serif, auteur cliquable, carte d'informations
/// avec les actions, « De l'éditeur », et les autres livres du même auteur.
/// L'écran entier reste teinté par la couleur dominante de la couverture.
struct FicheOeuvreView: View {
    var oeuvre: Oeuvre

    @Environment(\.modelContext) private var contexte

    var body: some View {
        Group {
            if let exemplaire = oeuvre.exemplaire {
                ContenuFicheOeuvre(oeuvre: oeuvre, exemplaire: exemplaire)
            } else {
                // Sécurité : un exemplaire manquant est recréé.
                Color.clear.onAppear {
                    oeuvre.exemplaire = Exemplaire()
                }
            }
        }
    }
}

private struct ContenuFicheOeuvre: View {
    var oeuvre: Oeuvre
    @Bindable var exemplaire: Exemplaire

    @Environment(\.modelContext) private var contexte
    @Environment(\.dismiss) private var dismiss
    @Query private var objectifs: [Objectif]
    @Query private var oeuvres: [Oeuvre]

    @State private var teinte = Color(red: 0.30, green: 0.21, blue: 0.14)
    @State private var cibleSession: CibleSession?
    @State private var majPageVisible = false
    @State private var pretVisible = false
    @State private var nomPret = ""
    @State private var confirmerSuppression = false
    @State private var celebration = false
    @State private var etagereVisible = false
    @State private var resumeDeplie = false

    private var langue: String { objectifs.first?.languePrincipale ?? Langues.codeAppareil }

    /// Les autres œuvres du même auteur, pour l'étagère du bas.
    private var duMemeAuteur: [Oeuvre] {
        let auteur = oeuvre.auteurPrincipal
        guard !auteur.isEmpty else { return [] }
        return oeuvres.filter {
            $0.persistentModelID != oeuvre.persistentModelID
                && $0.auteurs.contains { $0.localizedCaseInsensitiveContains(auteur) }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                GrandeCouverture(
                    urlString: oeuvre.couvertureAffichee,
                    titre: oeuvre.titre(langue),
                    auteur: oeuvre.auteurPrincipal,
                    largeur: 208,
                    manga: oeuvre.type != .livre
                )
                .padding(.top, 6)

                blocTitre

                carteInfosActions

                chipsMoods

                if exemplaire.statut == .enCours {
                    carteProgression
                }

                if let resume = oeuvre.resumeAffiche, !resume.isEmpty {
                    sectionEditeur(resume)
                }

                if !oeuvre.sessions.isEmpty {
                    carteSessions
                }

                carteCitations

                carteDetails

                if !duMemeAuteur.isEmpty {
                    sectionMemeAuteur
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
            .foregroundStyle(.white)
        }
        .background(fond.ignoresSafeArea())
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar { barreActions }
        .sensoryFeedback(.success, trigger: celebration)
        .alerteNouvelleEtagere(.oeuvre(oeuvre), visible: $etagereVisible)
        .fullScreenCover(item: $cibleSession) { SessionLectureView(cible: $0) }
        .sheet(isPresented: $majPageVisible) {
            MiseAJourPageSheet(exemplaire: exemplaire, oeuvre: oeuvre, surTermine: marquerLu)
        }
        .alert("Prêter ce livre", isPresented: $pretVisible) {
            TextField("À qui ?", text: $nomPret)
            Button("Prêter") {
                exemplaire.preteA = nomPret.isEmpty ? nil : nomPret
                nomPret = ""
            }
            Button("Annuler", role: .cancel) {}
        }
        .confirmationDialog(
            "Retirer « \(oeuvre.titre(langue)) » de la bibliothèque ?",
            isPresented: $confirmerSuppression,
            titleVisibility: .visible
        ) {
            Button("Retirer", role: .destructive) {
                contexte.delete(oeuvre)
                dismiss()
            }
        }
        .task {
            if oeuvre.couvertureLocaleURL == nil {
                await EditionsLocales.rafraichirOeuvre(oeuvre, langue: langue)
            }
        }
        .task(id: oeuvre.couvertureAffichee) {
            guard let image = await ImageCharge.partage.uiImage(depuis: oeuvre.couvertureAffichee),
                  let couleur = CouleurCouverture.teinteDeFond(image)
            else { return }
            withAnimation(.easeOut(duration: 0.5)) { teinte = couleur }
        }
    }

    private var fond: some View {
        LinearGradient(
            colors: [teinte, teinte.opacity(0.85)],
            startPoint: .top,
            endPoint: .bottom
        )
        .background(teinte)
    }

    // MARK: - Titre, auteur, note — la tête de page d'Apple Books

    private var blocTitre: some View {
        VStack(spacing: 6) {
            Text(oeuvre.titre(langue))
                .font(.system(size: 27, weight: .semibold, design: .serif))
                .multilineTextAlignment(.center)

            if let auteur = oeuvre.auteurs.first, !auteur.isEmpty {
                NavigationLink {
                    FicheAuteurView(auteur: auteur, langue: langue)
                } label: {
                    HStack(spacing: 4) {
                        Text(oeuvre.auteurs.joined(separator: " · "))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .opacity(0.7)
                    }
                    .font(.system(size: 17))
                    .opacity(0.9)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                EtoilesNotation(note: $exemplaire.note, taille: 14)
                if let genre = oeuvre.genres.first {
                    Text("· \(genre)")
                        .font(.footnote)
                        .opacity(0.75)
                }
            }
        }
    }

    // MARK: - La carte « Livre ⓘ » : informations + les deux actions

    private var carteInfosActions: some View {
        VStack(spacing: 12) {
            HStack {
                Label(oeuvre.type.libelle, systemImage: "book.closed.fill")
                    .font(.footnote.weight(.semibold))
                Spacer()
                Text(sousInfos)
                    .font(.footnote)
                    .opacity(0.75)
                    .monospacedDigit()
            }

            HStack(spacing: 10) {
                Button {
                    if exemplaire.statut == .aLire || exemplaire.statut == .wishlist {
                        exemplaire.changerStatut(.enCours)
                    }
                    cibleSession = .oeuvre(oeuvre)
                } label: {
                    Text(libelleSession)
                        .font(.subheadline.weight(.heavy))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .foregroundStyle(teinte)
                .background(.white, in: Capsule())

                Menu {
                    ForEach(StatutLecture.allCases) { statut in
                        Button {
                            if statut == .lu { marquerLu() }
                            else {
                                exemplaire.changerStatut(statut)
                                BadgesEngine.evaluer(dans: contexte)
                            }
                        } label: {
                            Label(statut.libelle, systemImage: statut.symbole)
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: exemplaire.statut.symbole)
                        Text(exemplaire.statut.libelle)
                            .fontWeight(.bold)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .opacity(0.7)
                    }
                    .font(.footnote)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(.white.opacity(0.18), in: Capsule())
                }
            }
        }
        .padding(14)
        .background(.white.opacity(0.13), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var sousInfos: String {
        var morceaux: [String] = []
        if let annee = oeuvre.anneePublication { morceaux.append(String(annee)) }
        if let pages = oeuvre.pages { morceaux.append("\(pages) pages") }
        if let format = exemplaire.format { morceaux.append(format.libelle) }
        return morceaux.joined(separator: " · ")
    }

    private var libelleSession: String {
        switch exemplaire.statut {
        case .enCours: return String(localized: "Reprendre · p. \(exemplaire.pageCourante)")
        case .lu: return String(localized: "Relire")
        default: return String(localized: "Session de lecture")
        }
    }

    // MARK: - Moods

    private var chipsMoods: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 6)], spacing: 6) {
            ForEach(Moods.tous, id: \.self) { mood in
                let actif = exemplaire.moods.contains(mood)
                Button {
                    if actif {
                        exemplaire.moods.removeAll { $0 == mood }
                    } else {
                        exemplaire.moods.append(mood)
                    }
                } label: {
                    Text(mood)
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(actif ? .white.opacity(0.9) : .white.opacity(0.12), in: Capsule())
                        .foregroundStyle(actif ? teinte : .white)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Sections, avec les titres serif d'Apple Books

    private func titreSerif(_ texte: String) -> some View {
        Text(texte)
            .font(.system(size: 21, weight: .semibold, design: .serif))
    }

    private func sectionEditeur(_ resume: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            titreSerif("De l'éditeur")
            Text(resume)
                .font(.callout)
                .opacity(0.92)
                .lineLimit(resumeDeplie ? nil : 7)
            Button(resumeDeplie ? "Réduire" : "Plus") {
                withAnimation(.snappy) { resumeDeplie.toggle() }
            }
            .font(.subheadline.weight(.bold))
            .tint(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    private var carteProgression: some View {
        carte {
            titreSerif("Progression")
            BarreProgression(valeur: exemplaire.progression, teinte: .white)
            HStack {
                if let pages = oeuvre.pages {
                    Text("p. \(exemplaire.pageCourante) sur \(pages) · \(Int(exemplaire.progression * 100)) %")
                        .monospacedDigit()
                }
                Spacer()
                Button("Mettre à jour") { majPageVisible = true }
                    .font(.caption.weight(.bold))
                    .buttonStyle(.bordered)
                    .tint(.white)
            }
            .font(.caption)
        }
    }

    private var carteSessions: some View {
        let recentes = oeuvre.sessions.sorted { $0.debut > $1.debut }.prefix(3)
        let totalMinutes = oeuvre.sessions.reduce(0) { $0 + $1.dureeSecondes } / 60
        return carte {
            HStack(alignment: .lastTextBaseline) {
                titreSerif("Sessions")
                Spacer()
                Text("\(totalMinutes) min au total")
                    .font(.caption)
                    .opacity(0.7)
                    .monospacedDigit()
            }
            ForEach(Array(recentes)) { session in
                HStack {
                    Text(session.debut, format: .dateTime.weekday(.wide).day().month())
                    Spacer()
                    Text("\(session.minutes) min · \(session.pagesLues) p.")
                        .monospacedDigit()
                }
                .font(.caption)
                .opacity(0.9)
            }
        }
    }

    private var carteCitations: some View {
        NavigationLink {
            ListeCitationsView(oeuvre: oeuvre)
        } label: {
            carte {
                HStack {
                    titreSerif("Citations")
                    Spacer()
                    Text("\(oeuvre.citations.count)")
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .opacity(0.6)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var carteDetails: some View {
        carte {
            titreSerif("Détails")
            if let isbn = exemplaire.isbn {
                rangee("ISBN", valeur: isbn, mono: true)
            }
            if let langueEdition = exemplaire.langueEdition {
                rangee("Langue de l'édition", valeur: Langues.nom(langueEdition))
            }
            if let debut = exemplaire.dateDebut {
                rangee("Commencé le", valeur: debut.formatted(date: .abbreviated, time: .omitted))
            }
            if let fin = exemplaire.dateFin {
                rangee("Terminé le", valeur: fin.formatted(date: .abbreviated, time: .omitted))
            }
            HStack {
                Text("Prêté à").opacity(0.7)
                Spacer()
                if let preteA = exemplaire.preteA {
                    Text(preteA).fontWeight(.semibold)
                    Button("Rendu") { exemplaire.preteA = nil }
                        .font(.caption2.weight(.bold))
                        .buttonStyle(.bordered)
                        .tint(.white)
                } else {
                    Button("Prêter…") { pretVisible = true }
                        .font(.caption.weight(.bold))
                        .buttonStyle(.bordered)
                        .tint(.white)
                }
            }
            .font(.caption)
        }
    }

    // MARK: - Plus de livres de cet auteur, comme chez eux

    private var sectionMemeAuteur: some View {
        VStack(alignment: .leading, spacing: 10) {
            titreSerif("Plus de livres de : \(oeuvre.auteurPrincipal)")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(duMemeAuteur) { autre in
                        NavigationLink {
                            FicheOeuvreView(oeuvre: autre)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                GrandeCouverture(
                                    urlString: autre.couvertureAffichee,
                                    titre: autre.titre(langue),
                                    largeur: 118,
                                    manga: autre.type != .livre
                                )
                                Text(autre.titre(langue))
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                    .frame(width: 118, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    // MARK: - Barre d'outils : ✓ rapide + menu ⋯

    private var barreActions: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                if exemplaire.statut == .lu {
                    exemplaire.changerStatut(.aLire)
                } else {
                    marquerLu()
                }
            } label: {
                Image(systemName: exemplaire.statut == .lu ? "checkmark.circle.fill" : "checkmark")
            }
            .accessibilityLabel("Marquer comme lu")

            Menu {
                Button {
                    exemplaire.aSuivre.toggle()
                } label: {
                    Label(
                        exemplaire.aSuivre ? "Retirer d'À suivre" : "Ajouter à À suivre",
                        systemImage: "text.badge.plus"
                    )
                }
                Button { pretVisible = true } label: {
                    Label("Prêter…", systemImage: "person.badge.plus")
                }
                MenuEtageres(cible: .oeuvre(oeuvre), creationVisible: $etagereVisible)
                Divider()
                Button(role: .destructive) { confirmerSuppression = true } label: {
                    Label("Retirer de la bibliothèque", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle.fill")
            }
        }
    }

    // MARK: - Fin de livre (confettis plein écran)

    private func marquerLu() {
        exemplaire.changerStatut(.lu)
        BadgesEngine.evaluer(dans: contexte)
        celebration.toggle()
        Celebrations.partage.feter("Terminé !")
    }

    // MARK: - Aides

    private func rangee(_ libelle: String, valeur: String, mono: Bool = false) -> some View {
        HStack {
            Text(libelle).opacity(0.7)
            Spacer()
            Text(valeur)
                .fontWeight(.semibold)
                .font(mono ? .system(.caption, design: .monospaced) : .caption)
        }
        .font(.caption)
    }

    private func carte(@ViewBuilder _ contenu: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            contenu()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.white.opacity(0.13), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Feuille de mise à jour de page

private struct MiseAJourPageSheet: View {
    @Bindable var exemplaire: Exemplaire
    var oeuvre: Oeuvre
    var surTermine: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var page: Double = 0

    private var maxPages: Double { Double(oeuvre.pages ?? 2000) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Où en es-tu ?")
                    .font(.titreOeuvre(22))
                Text("p. \(Int(page)) sur \(Int(maxPages))")
                    .font(.chiffreSerif(30))
                    .monospacedDigit()
                Slider(value: $page, in: 0...maxPages, step: 1)
                    .tint(Couleurs.accent)
                HStack(spacing: 12) {
                    Stepper("Ajuster", value: $page, in: 0...maxPages)
                        .labelsHidden()
                    Spacer()
                    Button("J'ai terminé ce livre") {
                        dismiss()
                        surTermine()
                    }
                    .font(.caption.weight(.bold))
                    .buttonStyle(.bordered)
                    .tint(Couleurs.lu)
                }
            }
            .padding(24)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        exemplaire.pageCourante = Int(page)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
        }
        .presentationDetents([.height(300)])
        .onAppear { page = Double(exemplaire.pageCourante) }
    }
}

// MARK: - Citations

struct ListeCitationsView: View {
    var oeuvre: Oeuvre

    @Environment(\.modelContext) private var contexte
    @State private var ajoutVisible = false
    @State private var texte = ""
    @State private var page = ""

    var body: some View {
        List {
            if oeuvre.citations.isEmpty {
                ContentUnavailableView(
                    "Aucune citation",
                    systemImage: "quote.opening",
                    description: Text("Gardez ici les phrases qui vous ont arrêté.")
                )
            }
            ForEach(oeuvre.citations.sorted { $0.dateAjout > $1.dateAjout }) { citation in
                VStack(alignment: .leading, spacing: 6) {
                    Text("« \(citation.texte) »")
                        .font(.system(.subheadline, design: .serif))
                    if let page = citation.page {
                        Text("p. \(page)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .swipeActions {
                    Button(role: .destructive) {
                        contexte.delete(citation)
                    } label: {
                        Label("Supprimer", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Citations")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { ajoutVisible = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $ajoutVisible) {
            NavigationStack {
                Form {
                    Section("La phrase") {
                        TextField("Recopiez la citation…", text: $texte, axis: .vertical)
                            .lineLimit(3...8)
                    }
                    Section("Page (optionnel)") {
                        TextField("Numéro de page", text: $page)
                            .keyboardType(.numberPad)
                    }
                }
                .navigationTitle("Nouvelle citation")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Ajouter") {
                            let citation = Citation(texte: texte, page: Int(page))
                            oeuvre.citations.append(citation)
                            texte = ""
                            page = ""
                            ajoutVisible = false
                        }
                        .disabled(texte.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annuler") { ajoutVisible = false }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }
}

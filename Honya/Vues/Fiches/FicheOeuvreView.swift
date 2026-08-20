import SwiftUI
import SwiftData

/// Fiche livre : l'écran entier prend la couleur dominante de la couverture,
/// comme les fiches d'Apple Books. Texte blanc, contrôles translucides.
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

    @State private var teinte = Color(red: 0.30, green: 0.21, blue: 0.14)
    @State private var cibleSession: CibleSession?
    @State private var majPageVisible = false
    @State private var pretVisible = false
    @State private var nomPret = ""
    @State private var confirmerSuppression = false
    @State private var celebration = false

    private var langue: String { objectifs.first?.languePrincipale ?? Langues.codeAppareil }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                CouvertureView(
                    urlString: oeuvre.couvertureCanoniqueURL,
                    titre: oeuvre.titre(langue),
                    auteur: oeuvre.auteurPrincipal,
                    coins: 8
                )
                .frame(width: 132)
                .shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 10)
                .padding(.top, 8)

                VStack(spacing: 4) {
                    Text(oeuvre.titre(langue))
                        .font(.titreOeuvre(26))
                        .multilineTextAlignment(.center)
                    Text(oeuvre.auteurs.joined(separator: " · "))
                        .font(.subheadline)
                        .opacity(0.8)
                }

                EtoilesNotation(note: $exemplaire.note)

                chipsMetadonnees

                boutonPrincipal

                chipsMoods

                if exemplaire.statut == .enCours {
                    carteProgression
                }

                if !oeuvre.sessions.isEmpty {
                    carteSessions
                }

                carteCitations

                if let resume = oeuvre.resume, !resume.isEmpty {
                    carteResume(resume)
                }

                carteDetails
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
            .foregroundStyle(.white)
        }
        .background(fond.ignoresSafeArea())
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar { menuActions }
        .overlay { if celebration { vueCelebration } }
        .sensoryFeedback(.success, trigger: celebration)
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
        .task(id: oeuvre.couvertureCanoniqueURL) {
            guard let image = await ImageCharge.partage.uiImage(depuis: oeuvre.couvertureCanoniqueURL),
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

    // MARK: - Chips de métadonnées

    private var chipsMetadonnees: some View {
        HStack(spacing: 6) {
            if let pages = oeuvre.pages { chip("\(pages) pages") }
            if let genre = oeuvre.genres.first { chip(genre) }
            if let annee = oeuvre.anneePublication { chip(String(annee)) }
            if let format = exemplaire.format { chip(format.libelle) }
        }
        .font(.caption2.weight(.bold))
    }

    private func chip(_ texte: String) -> some View {
        Text(texte)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(.white.opacity(0.16), in: Capsule())
    }

    // MARK: - Bouton principal (blanc, dépend du statut)

    private var boutonPrincipal: some View {
        Button {
            switch exemplaire.statut {
            case .aLire, .wishlist, .abandonne:
                exemplaire.changerStatut(.enCours)
                cibleSession = .oeuvre(oeuvre)
            case .enCours, .lu:
                cibleSession = .oeuvre(oeuvre)
            }
        } label: {
            VStack(spacing: 1) {
                Text(libelleBouton)
                    .font(.subheadline.weight(.heavy))
                Text(sousLibelleBouton)
                    .font(.caption2.weight(.medium))
                    .opacity(0.6)
            }
            .frame(maxWidth: 300)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .foregroundStyle(teinte)
        .background(.white, in: Capsule())
    }

    private var libelleBouton: String {
        switch exemplaire.statut {
        case .aLire: return "Commencer la lecture"
        case .wishlist: return "Commencer la lecture"
        case .enCours: return "Reprendre · p. \(exemplaire.pageCourante)"
        case .lu: return "Relire"
        case .abandonne: return "Reprendre quand même"
        }
    }

    private var sousLibelleBouton: String {
        switch exemplaire.statut {
        case .enCours:
            return "\(Int(exemplaire.progression * 100)) % · lancer une session"
        case .lu:
            if let fin = exemplaire.dateFin {
                return "terminé le \(fin.formatted(.dateTime.day().month().year()))"
            }
            return "terminé"
        default:
            return "lance le chronomètre de session"
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
        .padding(.top, 2)
    }

    // MARK: - Cartes

    private var carteProgression: some View {
        carte {
            EtiquetteCarte("Progression")
            BarreProgression(valeur: exemplaire.progression, teinte: .white)
            HStack {
                if let pages = oeuvre.pages {
                    Text("p. \(exemplaire.pageCourante) sur \(pages)")
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
            EtiquetteCarte("Sessions · \(totalMinutes) min au total")
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
                    EtiquetteCarte("Citations")
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

    private func carteResume(_ resume: String) -> some View {
        carte {
            EtiquetteCarte("Résumé")
            Text(resume)
                .font(.caption)
                .lineLimit(6)
                .opacity(0.9)
        }
    }

    private var carteDetails: some View {
        carte {
            EtiquetteCarte("Détails")
            if let isbn = exemplaire.isbn {
                rangee("ISBN", valeur: isbn, mono: true)
            }
            if let langueEdition = exemplaire.langueEdition {
                rangee("Langue de l'édition", valeur: langueEdition.uppercased())
            }
            if let debut = exemplaire.dateDebut {
                rangee("Commencé le", valeur: debut.formatted(date: .abbreviated, time: .omitted))
            }
            if let fin = exemplaire.dateFin {
                rangee("Terminé le", valeur: fin.formatted(date: .abbreviated, time: .omitted))
            }
            HStack {
                Text("Prêté à")
                    .opacity(0.7)
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

    // MARK: - Barre d'outils

    private var menuActions: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Menu("Statut") {
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
                }
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
                Divider()
                Button(role: .destructive) { confirmerSuppression = true } label: {
                    Label("Retirer de la bibliothèque", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle.fill")
            }
        }
    }

    // MARK: - Fin de livre (petit moment de fête, sobre)

    private func marquerLu() {
        exemplaire.changerStatut(.lu)
        BadgesEngine.evaluer(dans: contexte)
        withAnimation(.spring(duration: 0.4)) { celebration = true }
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            withAnimation(.easeOut(duration: 0.4)) { celebration = false }
        }
    }

    private var vueCelebration: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .symbolEffect(.bounce, value: celebration)
            Text("Terminé !")
                .font(.titreOeuvre(24))
            Text("Un de plus sur l'étagère des lus.")
                .font(.caption)
                .opacity(0.8)
        }
        .foregroundStyle(.white)
        .padding(30)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .transition(.scale(scale: 0.8).combined(with: .opacity))
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

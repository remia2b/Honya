import SwiftUI
import SwiftData

/// Fiche série : le tableau de chasse du lecteur de manga.
/// Grille de tomes cochables (pattern « épisodes TV »), double progression
/// possédés/lus, suivi de chapitres, prochaine sortie avec rappel.
struct FicheSerieView: View {
    /// Toutes les séries : le plafond d'alertes porte sur le compte entier.
    @Query private var series: [Serie]
    @State private var plusVisible = false
    @State private var plusAlerteVisible = false
    @State private var plusEtagereVisible = false
    @State private var droits = Droits.partage
    @Bindable var serie: Serie

    @Environment(\.modelContext) private var contexte
    @Environment(\.dismiss) private var dismiss
    @Query private var objectifs: [Objectif]

    @State private var cibleSession: CibleSession?
    @State private var sortieVisible = false
    @State private var confirmerSuppression = false
    @State private var etagereVisible = false

    private var langue: String { objectifs.first?.languePrincipale ?? Langues.codeAppareil }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                banniere
                carteProgression
                PiluleCTA(
                    titre: "Session de lecture",
                    sousTitre: serie.nomAffiche(langue)
                ) {
                    cibleSession = .serie(serie)
                }
                .frame(maxWidth: 280)
                menuStatut
                carteTomes
                if serie.rayonRefuse && !droits.plus
                    && ImportService.contientTomeVerrouille(serie.tomes, de: serie) {
                    invitationRayon
                }
                carteSortie
                if let resume = serie.resumeAffiche, !resume.isEmpty {
                    carte {
                        EtiquetteCarte("De l’éditeur")
                        Text(resume)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(6)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    MenuEtageres(
                        cible: .serie(serie),
                        creationVisible: $etagereVisible,
                        plusVisible: $plusEtagereVisible
                    )
                    Button {
                        Task { await actualiser() }
                    } label: {
                        Label("Actualiser les informations", systemImage: "arrow.clockwise")
                    }
                    Divider()
                    Button(role: .destructive) { confirmerSuppression = true } label: {
                        Label("Retirer la série", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog(
            "Retirer « \(serie.nomAffiche(langue)) » et tous ses tomes ?",
            isPresented: $confirmerSuppression,
            titleVisibility: .visible
        ) {
            Button("Retirer", role: .destructive) {
                let photos = serie.tomes.compactMap(\.couverturePersonnelleURL)
                let rappel = NotificationsService.cibleAnnulation(pour: serie)
                contexte.delete(serie)
                do {
                    try contexte.save()
                    NotificationsService.annulerRappel(rappel)
                    for photo in photos { CouverturesPersonnelles.supprimer(photo) }
                    dismiss()
                } catch {
                    contexte.rollback()
                }
            }
        }
        .alerteNouvelleEtagere(.serie(serie), visible: $etagereVisible)
        .fullScreenCover(item: $cibleSession) { SessionLectureView(cible: $0) }
        .ecranHonyaPlus($plusVisible, verrou: .serie(
            nom: serie.nomAffiche(langue),
            tomes: serie.tomesTotal ?? serie.tomes.count,
            couvertures: couverturesDeLaSerie
        ))
        .ecranHonyaPlus($plusAlerteVisible, verrou: .alerte(
            nom: serie.nomAffiche(langue),
            couvertures: couverturesDeLaSerie
        ))
        .ecranHonyaPlus($plusEtagereVisible, verrou: .etagere(
            couvertures: couverturesDeLaSerie
        ))
        .sheet(isPresented: $sortieVisible) {
            SortieSheet(serie: serie, langue: langue)
        }
        .onAppear(perform: synchroniserTomes)
        .task(id: droits.plus) {
            let jamaisEnrichie = !serie.rayonEnrichi && !serie.rayonRefuse
            let essaiPerime = serie.dernierEssaiEditionLocale
                .map { $0 < Date().addingTimeInterval(-24 * 60 * 60) }
                ?? true
            if serie.couvertureLocaleURL == nil
                || jamaisEnrichie
                || essaiPerime
                || (droits.plus && serie.rayonRefuse) {
                ResolveurTomes.reinitialiser(serie)
                await EditionsLocales.rafraichirSerieComplete(
                    serie, langue: langue, profonde: true
                )
            }
        }
    }

    /// Re-résout la série depuis AniList (auteur, tomes, résumé) et relance
    /// la recherche des éditions locales — répare les données mal héritées.
    private func actualiser() async {
        // Conserver ici l'identifiant historique exact : l'actualisation peut
        // modifier le nom ou ajouter l'identifiant AniList de la série.
        if serie.rappelActive {
            NotificationsService.annulerRappel(pour: serie)
        }
        let reference = serie.nomRomaji ?? serie.noms["en"] ?? serie.nom
        await AgregateurMetadonnees.partage.viderCache()
        let resultats = await AgregateurMetadonnees.partage.rechercherMangas(reference)
        if let bon = resultatCompatiblePourActualisation(dans: resultats) {
            let nom = Tomaison.decomposer(bon.titre).base
            if !nom.isEmpty { serie.nom = nom }
            if let romaji = bon.romaji, !romaji.isEmpty {
                serie.nomRomaji = romaji
            }
            for alias in bon.titresAlternatifs
                where !serie.nomsAlternatifs.contains(alias) {
                serie.nomsAlternatifs.append(alias)
            }
            for (code, nom) in bon.titresParLangue {
                let base = Tomaison.decomposer(nom).base
                if !base.isEmpty { serie.noms[code] = base }
            }
            if let auteur = bon.auteurs.first, !auteur.isEmpty {
                serie.auteur = auteur
            }
            for genre in bon.genres where !serie.genres.contains(genre) {
                serie.genres.append(genre)
            }
            if let resume = bon.resume, !resume.isEmpty { serie.resume = resume }
            if let couverture = bon.couvertureURL {
                serie.couvertureURL = couverture
                serie.attributionCouverture = bon.attributionCouverture
            }
            if let total = bon.tomesTotal { serie.tomesTotal = total }
            if bon.statutParution != .inconnue {
                serie.statutParution = bon.statutParution
            }
            if serie.idAniList == nil { serie.idAniList = bon.idAniList }
        }
        // Les nouvelles notices écrasent les champs qu'elles savent confirmer.
        // On ne vide rien avant le réseau : une panne pendant « Actualiser » ne
        // doit jamais faire disparaître les titres et couvertures déjà acquis.
        ResolveurTomes.reinitialiser(serie)
        await EditionsLocales.rafraichirSerieComplete(
            serie, langue: langue, profonde: true
        )
        synchroniserTomes()
        if serie.rappelActive {
            serie.rappelActive = await NotificationsService.planifierRappelSortie(
                pour: serie, langue: langue
            )
        }
    }

    /// Une réponse proche dans les résultats n'est pas une identité. Si la
    /// série porte déjà un identifiant AniList, lui seul est accepté. Pour une
    /// ancienne série sans identifiant, le nom ET l'auteur doivent concorder ;
    /// en l'absence d'auteur des deux côtés, seul le nom exact suffit.
    private func resultatCompatiblePourActualisation(
        dans resultats: [ResultatRecherche]
    ) -> ResultatRecherche? {
        if let identifiant = serie.idAniList {
            return resultats.first {
                $0.estSerie && $0.idAniList == identifiant
            }
        }

        let nomsSerie = ([serie.nom, serie.nomRomaji].compactMap { $0 })
            + Array(serie.noms.values) + serie.nomsAlternatifs
        let auteursSerie = [serie.auteur].compactMap { $0 }
        return resultats.first { candidat in
            guard candidat.estSerie else { return false }
            let nomsCandidat = ([candidat.titre, candidat.titreOriginal, candidat.romaji]
                .compactMap { $0 })
                + Array(candidat.titresParLangue.values)
                + candidat.titresAlternatifs
            let titreCompatible = nomsSerie.contains { nomSerie in
                nomsCandidat.contains { Tomaison.memeSerie($0, nomSerie) }
            }
            guard titreCompatible else { return false }
            if auteursSerie.isEmpty || candidat.auteurs.isEmpty {
                let clesSerie = Set(nomsSerie.map {
                    TexteUtil.normaliser(Tomaison.decomposer($0).base)
                })
                return nomsCandidat.contains {
                    clesSerie.contains(
                        TexteUtil.normaliser(Tomaison.decomposer($0).base)
                    )
                }
            }
            return AuteursUtil.correspondent(candidat.auteurs, auteursSerie)
        }
    }

    /// Retire les anciennes cases 1...N créées depuis le seul total AniList.
    /// Les vrais volumes locaux portent au moins un titre, un ISBN, une date
    /// ou une couverture ; les possessions du lecteur ne sont jamais touchées.
    private func synchroniserTomes() {
        if let sortie = serie.prochaineSortieDate,
           !DateCivile.estAujourdhuiOuApres(sortie) {
            if serie.rappelActive {
                NotificationsService.annulerRappel(pour: serie)
            }
            serie.rappelActive = false
            serie.prochaineSortieNumero = nil
            serie.prochaineSortieDate = nil
        }
        let fantomes = serie.tomes.filter {
            !$0.possede && !$0.lu && $0.titre == nil && $0.isbn == nil
                && $0.couvertureURL == nil && $0.pages == nil
                && $0.dateSortie == nil
        }
        for tome in fantomes {
            contexte.delete(tome)
        }
        if !fantomes.isEmpty { serie.rayonComplet = false }
    }

    // MARK: - Bannière

    private var banniere: some View {
        HStack(spacing: 14) {
            CouvertureView(
                urlString: serie.couvertureAffichee,
                titre: serie.nomAffiche(langue),
                auteur: serie.auteur,
                manga: serie.type != .livre
            )
            .frame(width: 66)
            .shadow(color: .black.opacity(0.3), radius: 7, y: 4)
            VStack(alignment: .leading, spacing: 3) {
                Text(serie.nomAffiche(langue))
                    .font(.titreOeuvre(21))
                    .lineLimit(2)
                if let auteur = serie.auteur, !auteur.isEmpty {
                    NavigationLink {
                        FicheAuteurView(auteur: auteur, langue: langue)
                    } label: {
                        HStack(spacing: 3) {
                            Text(auteur)
                            Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                        }
                        .font(.caption)
                        .foregroundStyle(Couleurs.accent)
                    }
                    .buttonStyle(.plain)
                }
                Text("\(serie.tomesTotal ?? serie.tomes.count) tomes · \(serie.statutParution.libelle)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if let genre = serie.genres.first {
                    Text(genre)
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                }
                if let attribution = serie.attributionCouvertureAffichee {
                    Text(verbatim: attribution)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }

    // MARK: - Double progression (possédés / lus)

    private var carteProgression: some View {
        let total = max(serie.tomes.count, 1)
        return carte {
            rangeeProgression(
                "Possédés",
                valeur: Double(serie.nbPossedes) / Double(total),
                teinte: Couleurs.aLire,
                detail: "\(serie.nbPossedes)/\(serie.tomes.count)"
            )
            rangeeProgression(
                "Lus",
                valeur: Double(serie.nbLus) / Double(total),
                teinte: Couleurs.lu,
                detail: "\(serie.nbLus)/\(serie.tomes.count)"
            )
            if let prochain = serie.prochainAAcheter {
                Text("Prochain à acheter : tome \(prochain)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Couleurs.accent)
                    .monospacedDigit()
            }
        }
    }

    private func rangeeProgression(
        _ libelle: LocalizedStringKey,
        valeur: Double,
        teinte: Color,
        detail: String
    ) -> some View {
        HStack(spacing: 10) {
            Text(libelle)
                .font(.caption.weight(.bold))
                .frame(width: 66, alignment: .leading)
            BarreProgression(valeur: valeur, teinte: teinte)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 46, alignment: .trailing)
        }
    }

    // MARK: - Grille de tomes

    private var carteTomes: some View {
        carte {
            GrilleTomesView(serie: serie, langue: langue)
        }
    }

    // MARK: - Prochaine sortie

    private var carteSortie: some View {
        carte {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Prochaine sortie")
                        .font(.subheadline.weight(.semibold))
                    if let date = serie.prochaineSortieDate {
                        HStack(spacing: 4) {
                            if let numero = serie.prochaineSortieNumero {
                                Text("Tome \(numero) —")
                            }
                            Text(date, format: .dateTime.day().month(.wide).year())
                        }
                        .font(.caption)
                        .foregroundStyle(Couleurs.accent)
                        .monospacedDigit()
                    } else {
                        Text("Non renseignée")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if serie.prochaineSortieDate != nil {
                    Button(action: basculerRappel) {
                        Image(systemName: serie.rappelActive ? "bell.fill" : "bell")
                            .foregroundStyle(serie.rappelActive ? Couleurs.accent : .secondary)
                    }
                    .buttonStyle(.bordered)
                    .clipShape(Circle())
                    .accessibilityLabel("Rappel de sortie")
                    .badgeCadenas(alerteVerrouillee)
                }
                Button("Modifier") { sortieVisible = true }
                    .font(.caption.weight(.bold))
                    .buttonStyle(.bordered)
            }
        }
    }

    private func basculerRappel() {
        if serie.rappelActive {
            serie.rappelActive = false
            NotificationsService.annulerRappel(pour: serie)
        } else {
            guard droits.plus
                    || series.lazy.filter(\.rappelActive).count < Limites.alertesSortie
            else {
                plusAlerteVisible = true
                return
            }
            Task { @MainActor in
                guard await NotificationsService.demanderAutorisation() else { return }
                serie.rappelActive = await NotificationsService.planifierRappelSortie(
                    pour: serie, langue: langue
                )
            }
        }
    }

    /// Une alerte existante reste libre à couper. Le cadenas n'apparaît que
    /// sur le geste qui dépasserait la première série offerte.
    private var alerteVerrouillee: Bool {
        guard !droits.plus, !serie.rappelActive else { return false }
        return series.lazy.filter(\.rappelActive).count >= Limites.alertesSortie
    }

    /// Le statut de la série se CHOISIT — il était seulement calculé, si bien
    /// qu'« abandonné » n'existait nulle part pour une série.
    private var menuStatut: some View {
        Menu {
            ForEach(StatutLecture.allCases) { statut in
                Button {
                    serie.statutChoisi = statut
                } label: {
                    Label(statut.libelle, systemImage: statut.symbole)
                }
            }
            if serie.statutChoisi != nil {
                Divider()
                Button("Laisser Honya décider", systemImage: "wand.and.stars") {
                    serie.statutChoisi = nil
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: serie.statut.symbole)
                    .foregroundStyle(serie.statut.couleur)
                VStack(alignment: .leading, spacing: 1) {
                    Text(serie.statut.libelle)
                        .font(.subheadline.weight(.semibold))
                    Text(serie.statutChoisi == nil
                         ? "Calculé d'après vos tomes"
                         : "Choisi par vous")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
        }
        .buttonStyle(.plain)
    }

    /// Quand le rayon automatique a été refusé, la fiche le dit clairement et
    /// propose de l'ouvrir — plutôt que de laisser croire à un catalogue vide.
    private var invitationRayon: some View {
        Button { plusVisible = true } label: {
            HStack(spacing: 13) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Couleurs.accent)
                    .frame(width: 34, height: 34)
                    .background(Couleurs.accent.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Poser le rayon entier")
                        .font(.subheadline.weight(.semibold))
                    Text("Tous les tomes parus et à venir, dates comprises.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Couleurs.accent.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Couleurs.accent.opacity(0.28), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    /// Les trois premières couvertures de tomes, pour l'écran Honya+.
    private var couverturesDeLaSerie: [String] {
        let tomes = serie.tomesTries.compactMap(\.couvertureAffichee)
        return tomes.isEmpty
            ? [serie.couvertureAffichee].compactMap { $0 }
            : Array(tomes.prefix(3))
    }

    // MARK: - Aide carte

    private func carte(@ViewBuilder _ contenu: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            contenu()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }
}

// MARK: - Feuille « prochaine sortie »

private struct SortieSheet: View {
    @Bindable var serie: Serie
    var langue: String

    @Environment(\.dismiss) private var dismiss
    @State private var numero: Int = 1
    @State private var date: Date = .now

    private var aujourdHui: Date { Calendar.current.startOfDay(for: .now) }

    var body: some View {
        NavigationStack {
            Form {
                Stepper("Tome \(numero)", value: $numero, in: 1...500)
                    .monospacedDigit()
                DatePicker(
                    "Date de sortie",
                    selection: $date,
                    in: aujourdHui...,
                    displayedComponents: .date
                )
            }
            .navigationTitle("Prochaine sortie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        // L'identifiant historique contenait le numéro : il
                        // faut l'annuler tant que l'ancien numéro est connu.
                        if serie.rappelActive {
                            NotificationsService.annulerRappel(pour: serie)
                        }
                        serie.prochaineSortieNumero = numero
                        serie.prochaineSortieDate = date
                        if serie.rappelActive {
                            Task { @MainActor in
                                serie.rappelActive = await NotificationsService
                                    .planifierRappelSortie(pour: serie, langue: langue)
                            }
                        }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
        }
        .presentationDetents([.height(260)])
        .onAppear {
            numero = serie.prochaineSortieNumero
                ?? ((serie.tomes.map(\.numero).max() ?? 0) + 1)
            date = max(serie.prochaineSortieDate ?? aujourdHui, aujourdHui)
        }
    }
}

import SwiftUI
import SwiftData

/// Fiche série : le tableau de chasse du lecteur de manga.
/// Grille de tomes cochables (pattern « épisodes TV »), double progression
/// possédés/lus, suivi de chapitres, prochaine sortie avec rappel.
struct FicheSerieView: View {
    @Bindable var serie: Serie

    @Environment(\.modelContext) private var contexte
    @Environment(\.dismiss) private var dismiss
    @Query private var objectifs: [Objectif]

    @State private var cibleSession: CibleSession?
    @State private var sortieVisible = false
    @State private var confirmerSuppression = false

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
                carteTomes
                carteChapitres
                carteSortie
                if let resume = serie.resume, !resume.isEmpty {
                    carte {
                        EtiquetteCarte("Résumé")
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
                contexte.delete(serie)
                dismiss()
            }
        }
        .fullScreenCover(item: $cibleSession) { SessionLectureView(cible: $0) }
        .sheet(isPresented: $sortieVisible) {
            SortieSheet(serie: serie, langue: langue)
        }
        .onAppear(perform: synchroniserTomes)
    }

    /// Crée les cases manquantes si AniList annonce plus de tomes que la grille.
    private func synchroniserTomes() {
        guard let total = serie.tomesTotal, total > serie.tomes.count else { return }
        let existants = Set(serie.tomes.map(\.numero))
        for numero in 1...total where !existants.contains(numero) {
            serie.tomes.append(Tome(numero: numero))
        }
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

    private func rangeeProgression(_ libelle: String, valeur: Double, teinte: Color, detail: String) -> some View {
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

    // MARK: - Chapitres (prépublication)

    private var carteChapitres: some View {
        carte {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Chapitres (prépublication)")
                        .font(.subheadline.weight(.semibold))
                    Text("Lu jusqu'au chapitre \(serie.chapitresLus)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
                Stepper("Chapitres lus", value: $serie.chapitresLus, in: 0...(serie.chapitresTotal ?? 9999))
                    .labelsHidden()
            }
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
            Task { @MainActor in
                guard await NotificationsService.demanderAutorisation() else { return }
                serie.rappelActive = true
                await NotificationsService.planifierRappelSortie(pour: serie, langue: langue)
            }
        }
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

    var body: some View {
        NavigationStack {
            Form {
                Stepper("Tome \(numero)", value: $numero, in: 1...500)
                    .monospacedDigit()
                DatePicker("Date de sortie", selection: $date, displayedComponents: .date)
            }
            .navigationTitle("Prochaine sortie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        serie.prochaineSortieNumero = numero
                        serie.prochaineSortieDate = date
                        if serie.rappelActive {
                            Task { @MainActor in
                                NotificationsService.annulerRappel(pour: serie)
                                await NotificationsService.planifierRappelSortie(pour: serie, langue: langue)
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
            date = serie.prochaineSortieDate ?? .now
        }
    }
}

import SwiftUI
import SwiftData

/// La fiche d'un titre qu'on n'a pas encore : on la consulte avant de décider,
/// exactement comme la page produit d'Apple Books quand on vient de la recherche.
struct ApercuResultatView: View {
    @Query private var exemplaires: [Exemplaire]
    @Query private var tousLesTomes: [Tome]
    @State private var plusVisible = false
    @State private var cibleExistante: CibleSession?
    @State private var verifie = false

    let resultat: ResultatRecherche
    let langue: String

    @Environment(\.modelContext) private var contexte
    @Environment(\.dismiss) private var dismiss

    @State private var teinte = Color(red: 0.28, green: 0.20, blue: 0.14)
    @State private var ajoute = false
    @State private var resumeDeplie = false

    private var dejaPresent: Bool {
        ajoute || ImportService.existeDeja(resultat, dans: contexte)
    }

    var body: some View {
        // Un titre déjà rangé n'a pas à repasser par la page d'ajout : on
        // emmène directement à sa fiche, d'où qu'on vienne — découverte,
        // recherche ou classements.
        //
        // La vérification est figée à l'arrivée : la refaire à chaque image
        // ferait basculer l'écran juste après un ajout, en écrasant la
        // confirmation que le lecteur vient de déclencher.
        Group {
            if let deja = cibleExistante {
                switch deja {
                case .oeuvre(let oeuvre): FicheOeuvreView(oeuvre: oeuvre)
                case .serie(let serie): FicheSerieView(serie: serie)
                }
            } else {
                apercu
            }
        }
        .onAppear {
            if !verifie {
                verifie = true
                cibleExistante = ImportService.trouver(resultat, dans: contexte)
            }
        }
    }

    private var apercu: some View {
        ScrollView {
            VStack(spacing: 16) {
                CouvertureView(
                    urlString: resultat.couvertureURL,
                    titre: resultat.titreAffiche(langue),
                    auteur: resultat.auteurs.first,
                    coins: 8,
                    manga: resultat.type != .livre
                )
                .frame(width: 148)
                .shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 10)
                .padding(.top, 12)

                VStack(spacing: 5) {
                    Text(resultat.titreAffiche(langue))
                        .font(.titreOeuvre(25))
                        .multilineTextAlignment(.center)
                    if !resultat.auteurs.isEmpty {
                        Text(resultat.auteurs.joined(separator: " · "))
                            .font(.subheadline)
                            .opacity(0.85)
                    }
                    // Le titre d'origine reste consultable, en second plan.
                    if let original = resultat.titreOriginal,
                       original != resultat.titreAffiche(langue) {
                        Text(original)
                            .font(.caption)
                            .opacity(0.55)
                            .multilineTextAlignment(.center)
                    }
                }

                chips

                actions

                if let resume = resultat.resume, !resume.isEmpty {
                    carte {
                        EtiquetteCarte("Résumé")
                        Text(resume)
                            .font(.callout)
                            .lineLimit(resumeDeplie ? nil : 8)
                        Button(resumeDeplie ? "Réduire" : "Lire la suite") {
                            withAnimation(.snappy) { resumeDeplie.toggle() }
                        }
                        .font(.caption.weight(.bold))
                        .tint(.white)
                    }
                }

                carte {
                    EtiquetteCarte("Informations")
                    if resultat.estSerie {
                        ligne("Type", "Série")
                        if let tomes = resultat.tomesTotal { ligne("Tomes parus", "\(tomes)") }
                        if let chapitres = resultat.chapitresTotal { ligne("Chapitres", "\(chapitres)") }
                        ligne("Parution", resultat.statutParution.libelle)
                    } else {
                        if let pages = resultat.pages { ligne("Pages", "\(pages)") }
                        if let isbn = resultat.isbn { ligne("ISBN", isbn) }
                        if let langueEdition = resultat.langue {
                            ligne("Langue", Langues.nom(langueEdition))
                        }
                    }
                    if let annee = resultat.annee { ligne("Publication", String(annee)) }
                    if !resultat.genres.isEmpty {
                        ligne("Genres", resultat.genres.prefix(3).joined(separator: ", "))
                    }
                    ligne("Source", resultat.source)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 36)
            .foregroundStyle(.white)
        }
        .background(fond.ignoresSafeArea())
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .ecranHonyaPlus($plusVisible, verrou: .bibliotheque(
            couvertures: [resultat.couvertureURL].compactMap { $0 }
        ))
        .task(id: resultat.couvertureURL) {
            guard let image = await ImageCharge.partage.uiImage(depuis: resultat.couvertureURL),
                  let couleur = CouleurCouverture.teinteDeFond(image)
            else { return }
            withAnimation(.easeOut(duration: 0.5)) { teinte = couleur }
        }
    }

    private var fond: some View {
        LinearGradient(colors: [teinte, teinte.opacity(0.85)], startPoint: .top, endPoint: .bottom)
            .background(teinte)
    }

    // MARK: - Chips

    private var chips: some View {
        HStack(spacing: 6) {
            if resultat.estSerie {
                chip(String(localized: "Série"))
                if let tomes = resultat.tomesTotal {
                    chip(String(localized: "\(tomes) tomes"))
                }
            } else if let pages = resultat.pages {
                chip(String(localized: "\(pages) pages"))
            }
            if let annee = resultat.annee { chip(String(annee)) }
            if let genre = resultat.genres.first { chip(genre) }
        }
        .font(.caption2.weight(.bold))
    }

    private func chip(_ texte: String) -> some View {
        Text(texte)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(.white.opacity(0.16), in: Capsule())
    }

    // MARK: - Ajouter

    @ViewBuilder
    private var actions: some View {
        if dejaPresent {
            Label("Déjà dans votre bibliothèque", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.bold))
                .padding(.horizontal, 20)
                .padding(.vertical, 11)
                .background(.white.opacity(0.18), in: Capsule())
        } else if resultat.estSerie {
            Menu {
                Button { ajouter(.aLire) } label: {
                    Label("Je la possède · à lire", systemImage: "books.vertical.fill")
                }
                Button { ajouter(.enCours) } label: {
                    Label("Je suis en train de la lire", systemImage: "book.fill")
                }
                Button { ajouter(.lu) } label: {
                    Label("Je l'ai lue", systemImage: "checkmark.circle.fill")
                }
                Button { ajouter(.wishlist) } label: {
                    Label("À acheter", systemImage: "cart.fill")
                }
                Button { ajouter(.abandonne) } label: {
                    Label("Je l'ai abandonnée", systemImage: "xmark.circle")
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.subheadline.weight(.heavy))
                    Text("Ajouter cette série")
                        .font(.subheadline.weight(.heavy))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .opacity(0.55)
                }
                .frame(maxWidth: 300)
                .padding(.vertical, 12)
                .foregroundStyle(teinte)
                .background(.white, in: Capsule())
                .badgeCadenas(!Droits.partage.plus && tomesRanges >= Limites.tomes)
            }
        } else {
            // Un seul bouton, et l'état se choisit au moment d'ajouter :
            // fini le livre rangé « à lire » qu'on a en fait déjà fini.
            Menu {
                Button {
                    ajouter(.aLire)
                } label: {
                    Label("Je le possède · à lire", systemImage: "books.vertical.fill")
                }
                Button {
                    ajouter(.enCours)
                } label: {
                    Label("Je suis en train de le lire", systemImage: "book.fill")
                }
                Button {
                    ajouter(.lu)
                } label: {
                    Label("Je l'ai lu", systemImage: "checkmark.circle.fill")
                }
                Button {
                    ajouter(.wishlist)
                } label: {
                    Label("À acheter", systemImage: "cart.fill")
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.subheadline.weight(.heavy))
                    Text("Ajouter à ma bibliothèque")
                        .font(.subheadline.weight(.heavy))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .opacity(0.55)
                }
                .frame(maxWidth: 300)
                .padding(.vertical, 12)
                .foregroundStyle(teinte)
                .background(.white, in: Capsule())
                .badgeCadenas(!Droits.partage.plus && tomesRanges >= Limites.tomes)
            }
        }
    }

    private func ajouter(_ statut: StatutLecture) {
        // Le plafond porte sur la collection, jamais sur la consultation :
        // tout ce qui est déjà rangé reste accessible et lisible.
        guard Droits.partage.plus || tomesRanges < Limites.tomes else {
            plusVisible = true
            return
        }
        ImportService.ajouter(resultat, statut: statut, dans: contexte)
        withAnimation(.snappy) { ajoute = true }
    }

    /// Ce que compte le plafond : les livres seuls et les tomes des séries.
    private var tomesRanges: Int {
        exemplaires.count + tousLesTomes.count
    }

    // MARK: - Aides

    private func ligne(_ libelle: LocalizedStringKey, _ valeur: String) -> some View {
        HStack(alignment: .top) {
            Text(libelle).opacity(0.7)
            Spacer()
            Text(valeur)
                .fontWeight(.semibold)
                .multilineTextAlignment(.trailing)
        }
        .font(.caption)
        .padding(.vertical, 1)
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

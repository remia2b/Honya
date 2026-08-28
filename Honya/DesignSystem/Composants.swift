import SwiftUI

// MARK: - Couverture de livre (ratio 2:3, tranche à gauche, ombre portée)

struct CouvertureView: View {
    var urlString: String?
    var titre: String
    var auteur: String? = nil
    var coins: CGFloat = 6
    /// Un manga se relie à droite (sens de lecture japonais), un roman à gauche :
    /// la gorge du dos change de côté, comme sur les rendus d'Apple Books.
    var manga: Bool = false
    /// Côté de la vignette demandée au serveur, en pixels. La valeur par défaut
    /// convient à une fiche ; une grille de vignettes doit demander moins.
    var cote: Int = 1200

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Color.clear
                    .overlay(
                        Image(uiImage: image)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFill()
                    )
            } else {
                // Couverture générée : dégradé stable + titre serif, comme les maquettes.
                LinearGradient(
                    colors: [
                        Color(hue: teinte, saturation: 0.42, brightness: 0.62),
                        Color(hue: teinte, saturation: 0.55, brightness: 0.38),
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                VStack(alignment: .leading, spacing: 4) {
                    Text(titre)
                        .font(.system(size: 13, weight: .semibold, design: .serif))
                        .lineLimit(4)
                        .minimumScaleFactor(0.6)
                    Spacer(minLength: 0)
                    if let auteur, !auteur.isEmpty {
                        Text(auteur)
                            .font(.system(size: 8, weight: .semibold))
                            .opacity(0.85)
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(8)
                .padding(.leading, 4)
            }

            // Reflet léger en haut + voile mat : la matérialité d'un vrai livre.
            LinearGradient(
                colors: [.white.opacity(0.13), .clear],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.28)
            )
            LinearGradient(
                colors: [.clear, .black.opacity(0.07)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .aspectRatio(2.0 / 3.0, contentMode: .fit)
        .overlay(alignment: manga ? .trailing : .leading) {
            // La gorge de reliure : ombre de pli, filet de lumière, bord du dos.
            HStack(spacing: 0) {
                if manga {
                    Rectangle()
                        .fill(LinearGradient(
                            colors: [.clear, .black.opacity(0.30)],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(width: 9)
                    Rectangle().fill(.white.opacity(0.25)).frame(width: 1)
                    Rectangle().fill(.black.opacity(0.28)).frame(width: 2.5)
                } else {
                    Rectangle().fill(.black.opacity(0.28)).frame(width: 2.5)
                    Rectangle().fill(.white.opacity(0.25)).frame(width: 1)
                    Rectangle()
                        .fill(LinearGradient(
                            colors: [.black.opacity(0.30), .clear],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(width: 9)
                }
            }
        }
        .clipShape(UnevenRoundedRectangle(
            topLeadingRadius: manga ? coins : 2.5,
            bottomLeadingRadius: manga ? coins : 2.5,
            bottomTrailingRadius: manga ? 2.5 : coins,
            topTrailingRadius: manga ? 2.5 : coins
        ))
        .shadow(color: .black.opacity(0.18), radius: 7, x: 0, y: 2)
        .task(id: urlString) {
            image = await ImageCharge.partage.uiImage(depuis: urlString, cote: cote)
        }
        .accessibilityLabel(Text(titre))
    }

    /// Teinte stable dérivée du titre (indépendante du lancement).
    private var teinte: Double {
        let somme = titre.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return Double(somme % 360) / 360.0
    }
}

// MARK: - Badge de statut posé sur une couverture

struct BadgeStatutView: View {
    let statut: StatutLecture

    var body: some View {
        Text(statut.libelle)
            .font(.system(size: 9, weight: .heavy))
            .textCase(.uppercase)
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(statut.couleur.opacity(0.92), in: Capsule())
    }
}

// MARK: - Pilule CTA (encre pleine, sous-texte), à la « Keep Reading »

struct PiluleCTA: View {
    let titre: LocalizedStringKey
    var sousTitre: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(titre)
                    .font(.subheadline.weight(.bold))
                if let sousTitre {
                    Text(sousTitre)
                        .font(.caption2.weight(.medium))
                        .opacity(0.65)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color(uiColor: .systemBackground))
        .background(Color.primary, in: Capsule())
    }
}

// MARK: - Chip de filtre

struct ChipFiltre: View {
    let libelle: String
    var nombre: Int? = nil
    var actif: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(libelle)
                if let nombre {
                    Text("\(nombre)")
                        .opacity(0.6)
                        .monospacedDigit()
                }
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 15)
            .padding(.vertical, 9)
            .background(
                actif ? AnyShapeStyle(Color.primary) : AnyShapeStyle(Color(uiColor: .secondarySystemBackground)),
                in: Capsule()
            )
            .foregroundStyle(actif ? Color(uiColor: .systemBackground) : .primary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Notation en étoiles (note sur 10 → 5 étoiles avec demi-pas)

struct EtoilesNotation: View {
    @Binding var note: Int?
    var taille: CGFloat = 18

    var body: some View {
        HStack(spacing: 5) {
            ForEach(1...5, id: \.self) { etoile in
                Image(systemName: symbole(pour: etoile))
                    .font(.system(size: taille))
                    .foregroundStyle(Couleurs.accent)
                    .onTapGesture {
                        let nouvelle = etoile * 2
                        // Re-taper la même étoile : demi-étoile, puis effacer.
                        if note == nouvelle { note = nouvelle - 1 }
                        else if note == nouvelle - 1 { note = nil }
                        else { note = nouvelle }
                    }
            }
            if note == nil {
                Text("Noter")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("Note")
    }

    private func symbole(pour etoile: Int) -> String {
        guard let note else { return "star" }
        if note >= etoile * 2 { return "star.fill" }
        if note == etoile * 2 - 1 { return "star.leadinghalf.filled" }
        return "star"
    }
}

// MARK: - Barre de progression fine

struct BarreProgression: View {
    var valeur: Double // 0...1
    var teinte: Color = Couleurs.accent
    var hauteur: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(uiColor: .secondarySystemFill))
                Capsule()
                    .fill(teinte)
                    .frame(width: max(hauteur, geo.size.width * min(max(valeur, 0), 1)))
            }
        }
        .frame(height: hauteur)
        .animation(.spring(duration: 0.5), value: valeur)
    }
}

// MARK: - Étiquette de carte (petit titre en capitales, hérite de la couleur du contexte)

struct EtiquetteCarte: View {
    let texte: LocalizedStringKey

    init(_ texte: LocalizedStringKey) { self.texte = texte }

    var body: some View {
        Text(texte)
            .font(.caption2.weight(.heavy))
            .textCase(.uppercase)
            .kerning(0.5)
            .opacity(0.7)
    }
}

// MARK: - Étiquette de section (petites capitales)

struct EtiquetteSection: View {
    let texte: LocalizedStringKey
    var action: (() -> Void)? = nil
    var libelleAction: LocalizedStringKey = "Tout voir"

    var body: some View {
        HStack {
            Text(texte)
                .font(.footnote.weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .kerning(0.6)
            Spacer()
            if let action {
                Button(libelleAction, action: action)
                    .font(.footnote.weight(.semibold))
                    .tint(Couleurs.accent)
            }
        }
    }
}

// MARK: - En-tête de section, façon Apple Books
//
// Un grand titre serif suivi d'un chevron, éventuellement un sous-titre :
// c'est ce qui donne à leur accueil son allure de magazine, là où de petites
// capitales grises font « application utilitaire ».

struct TitreSection: View {
    let titre: LocalizedStringKey
    var sousTitre: LocalizedStringKey? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Button {
                action?()
            } label: {
                HStack(spacing: 5) {
                    Text(titre)
                        .font(.system(size: 25, weight: .semibold, design: .serif))
                        .foregroundStyle(.primary)
                    if action != nil {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(action == nil)

            if let sousTitre {
                Text(sousTitre)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Grande couverture d'accueil
//
// Chez Apple Books, deux couvertures occupent la largeur de l'écran et portent
// une ombre diffuse : c'est ce qui fait exister les livres à l'écran.

struct GrandeCouverture: View {
    var urlString: String?
    var titre: String
    var auteur: String?
    var largeur: CGFloat = 158
    var manga: Bool = false

    var body: some View {
        CouvertureView(urlString: urlString, titre: titre, auteur: auteur, coins: 8, manga: manga)
            .frame(width: largeur)
            .shadow(color: .black.opacity(0.45), radius: 14, x: 0, y: 8)
    }
}

// MARK: - Bande de section
//
// Les sections alternent avec le fond au lieu d'être enfermées dans des cartes
// arrondies : le contenu respire, comme dans leur accueil.

struct BandeSection<Contenu: View>: View {
    var teintee: Bool = false
    @ViewBuilder var contenu: Contenu

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            contenu
        }
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(teintee ? Color(uiColor: .secondarySystemBackground) : Color.clear)
    }
}

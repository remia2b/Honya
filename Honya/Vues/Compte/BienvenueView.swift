import AuthenticationServices
import SwiftData
import SwiftUI

/// La toute première page : un mur de couvertures qui dérive lentement, le nom
/// en serif, et deux chemins pour entrer — l'identifiant Apple, ou une adresse
/// e-mail.
///
/// Cette page ne se voit qu'une fois, avant d'entrer : le mur est un tirage
/// aléatoire des livres en tendance dans le pays du lecteur, rien de plus.
/// Sans réseau, l'écran reste net — titre et boutons, pas de mur.
struct BienvenueView: View {
    @Environment(\.colorScheme) private var apparence
    @Environment(\.accessibilityReduceMotion) private var mouvementReduit

    @Query private var objectifs: [Objectif]

    @State private var compte = Compte.partage
    @State private var vignettes: [Vignette] = []
    @State private var apparu = false

    @State private var parEmail = false
    @State private var mode: Mode = .inscription
    @State private var email = ""
    @State private var motDePasse = ""
    @State private var enCours = false
    @State private var erreur: String?
    @State private var information: String?
    @FocusState private var champActif: Champ?

    private enum Champ { case email, motDePasse }

    enum Mode: String, CaseIterable, Identifiable {
        case inscription = "Créer un compte"
        case connexion = "Se connecter"

        var id: String { rawValue }

        var libelle: String {
            switch self {
            case .inscription: return String(localized: "Créer un compte")
            case .connexion: return String(localized: "Se connecter")
            }
        }
    }

    /// Une case du mur. Le titre ne sert que si l'image manque — `CouvertureView`
    /// dessine alors une couverture, plutôt qu'un rectangle vide.
    private struct Vignette: Identifiable, Hashable, Codable {
        let id: String
        let url: String?
        let titre: String
        let manga: Bool
    }

    // Trois colonnes qui se recouvrent : le nombre de couvertures par colonne
    // se déduit de la hauteur de l'écran, il n'est pas figé.
    private static let colonnes = 3
    private static let ecart: CGFloat = 9
    private static let marge: CGFloat = 5
    /// Les colonnes ne démarrent pas au même endroit, sinon les couvertures
    /// forment des rangées bien alignées et le mur perd sa vie. Exprimé en
    /// fraction d'une couverture, jamais plus d'une : au-delà, la boucle
    /// laisserait le bas de l'écran à découvert.
    private static let departs: [CGFloat] = [-0.10, -0.55, -0.28]
    private static let durees: [Double] = [66, 78, 58]

    private var langue: String {
        objectifs.first?.languePrincipale ?? Langues.codeAppareil
    }

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()

            if !parEmail && !vignettes.isEmpty {
                // Un mur de cases vides est pire que pas de mur : tant qu'on
                // n'a rien à montrer, l'écran reste net.
                mur.ignoresSafeArea()
                    .transition(.opacity)
                voile.ignoresSafeArea()
                    .transition(.opacity)
            }

            if parEmail {
                ecranEmail
            } else {
                ecranAccueil
            }
        }
        .animation(.snappy(duration: 0.3), value: parEmail)
        .task { await chargerLeMur() }
        .onAppear {
            withAnimation(.easeOut(duration: 0.7)) { apparu = true }
        }
    }

    // MARK: - Le mur

    /// Chaque colonne dérive à sa vitesse, en sens alterné.
    ///
    /// Le mouvement vient d'une horloge (TimelineView), PAS d'une animation
    /// SwiftUI : une animation `repeatForever` posée sur les colonnes capture
    /// les changements de ses enfants, et l'apparition des images de
    /// couverture se retrouvait fondue sur 66 secondes — l'écran semblait
    /// n'afficher que des boîtes noires. Avec l'horloge, la position est un
    /// simple calcul à chaque image : rien à capturer.
    ///
    /// Le jeu de couvertures est posé DEUX fois et la dérive parcourt
    /// exactement la hauteur d'un jeu : quand le premier exemplaire est
    /// sorti, le second est précisément à sa place, la boucle ne se voit pas.
    private var mur: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: mouvementReduit)) { contexte in
            GeometryReader { geo in
                let largeur = (geo.size.width - Self.marge * 2
                               - Self.ecart * CGFloat(Self.colonnes - 1)) / CGFloat(Self.colonnes)
                let pas = largeur * 1.5 + Self.ecart
                let parColonne = Int(ceil(geo.size.height / pas)) + 1
                let course = pas * CGFloat(parColonne)
                let instant = contexte.date.timeIntervalSinceReferenceDate

                HStack(alignment: .top, spacing: Self.ecart) {
                    ForEach(0..<Self.colonnes, id: \.self) { index in
                        colonne(index, largeur: largeur, pas: pas,
                                parColonne: parColonne, course: course, instant: instant)
                    }
                }
                .padding(.horizontal, Self.marge)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                .clipped()
            }
        }
    }

    private func colonne(
        _ index: Int, largeur: CGFloat, pas: CGFloat,
        parColonne: Int, course: CGFloat, instant: TimeInterval
    ) -> some View {
        let depart = Self.departs[index % Self.departs.count] * pas
        let duree = Self.durees[index % Self.durees.count]
        // Fraction du tour accomplie, qui boucle d'elle-même.
        let cycle = CGFloat((instant / duree).truncatingRemainder(dividingBy: 1))
        // Les colonnes extérieures montent, celle du milieu descend. Une
        // colonne qui descend part une hauteur de jeu plus haut : c'est le
        // second exemplaire qui occupe l'écran, et il en sort par le bas.
        let position = index == 1
            ? depart - course + course * cycle
            : depart - course * cycle
        let jeu = vignettesDeLaColonne(index, combien: parColonne)

        return VStack(spacing: Self.ecart) {
            ForEach(Array((jeu + jeu).enumerated()), id: \.offset) { _, vignette in
                CouvertureView(
                    urlString: vignette.url,
                    titre: vignette.titre,
                    coins: 5,
                    manga: vignette.manga,
                    cote: 400          // affichée sur ~120 points : inutile d'aller plus haut
                )
                // Hauteur imposée avec la largeur : CouvertureView porte un
                // aspectRatio(.fit), et sans hauteur fixe la pile la ferait
                // rétrécir en largeur pour tenir le ratio.
                .frame(width: largeur, height: largeur * 1.5)
            }
        }
        .offset(y: position)
    }

    private func vignettesDeLaColonne(_ index: Int, combien: Int) -> [Vignette] {
        guard !vignettes.isEmpty else { return [] }
        return (0..<combien).map { rang in
            vignettes[(index * combien + rang) % vignettes.count]
        }
    }

    /// Le voile : les couvertures habillent TOUT l'écran, jamais coupées par
    /// un mur de noir — seulement assombries, de plus en plus vers le bas,
    /// assez pour que le titre et les boutons se détachent. C'est l'écran de
    /// bienvenue d'une salle pleine de livres, pas un dégradé qui les efface.
    private var voile: some View {
        let fond = Color(uiColor: .systemBackground)
        return LinearGradient(
            stops: [
                .init(color: fond.opacity(0.38), location: 0),
                .init(color: fond.opacity(0.30), location: 0.28),
                .init(color: fond.opacity(0.58), location: 0.55),
                .init(color: fond.opacity(0.80), location: 0.74),
                .init(color: fond.opacity(0.90), location: 1),
            ],
            startPoint: .top, endPoint: .bottom
        )
    }

    // MARK: - L'accueil

    private var ecranAccueil: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 10) {
                Text("Honya")
                    .font(.system(size: 46, weight: .semibold, design: .serif))
                Text("Rangez vos livres, suivez vos lectures.")
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 26)
            .padding(.bottom, 28)

            entrees
        }
        .opacity(apparu ? 1 : 0)
        .offset(y: apparu ? 0 : 14)
        .animation(.easeOut(duration: 0.6).delay(0.15), value: apparu)
    }

    private var entrees: some View {
        VStack(spacing: 12) {
            SignInWithAppleButton(
                .signIn,
                onRequest: { compte.preparerDemandeApple($0) },
                onCompletion: { traiterApple($0) }
            )
            .signInWithAppleButtonStyle(apparence == .dark ? .white : .black)
            .frame(height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))

            Button {
                erreur = nil
                information = nil
                parEmail = true
            } label: {
                Text("Continuer avec un e-mail")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        Color.primary.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                    )
            }
            .buttonStyle(.plain)

            Button("Continuer sans compte") {
                compte.continuerSansCompte()
            }
            .font(.system(size: 15))
            .tint(.secondary)
            .padding(.top, 4)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 34)
    }

    // MARK: - L'entrée par e-mail

    private var ecranEmail: some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack {
                    Button {
                        champActif = nil
                        erreur = nil
                        information = nil
                        parEmail = false
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 36, height: 36)
                            .background(Color.primary.opacity(0.06), in: Circle())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 18)

                VStack(spacing: 8) {
                    Text("Honya")
                        .font(.system(size: 34, weight: .semibold, design: .serif))
                    Text(sousTitreEmail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)

                Picker("", selection: $mode) {
                    ForEach(Mode.allCases) { cas in
                        Text(cas.libelle).tag(cas)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .onChange(of: mode) { _, _ in
                    erreur = nil
                    information = nil
                }

                formulaire
                    .padding(.horizontal, 28)
                    .padding(.top, 18)

                if let information {
                    message(information, couleur: Couleurs.lu)
                        .padding(.horizontal, 28)
                        .padding(.top, 14)
                }
                if let erreur {
                    message(erreur, couleur: .red)
                        .padding(.horizontal, 28)
                        .padding(.top, 14)
                }

                Text("Vos lectures restent sur votre appareil. Vous pouvez supprimer votre compte à tout moment depuis les réglages.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
                    .padding(.top, 26)
                    .padding(.bottom, 30)
            }
            .padding(.top, 14)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
    }

    private var sousTitreEmail: String {
        mode == .inscription
            ? String(localized: "Créez votre compte avec une adresse e-mail.")
            : String(localized: "Content de vous revoir.")
    }

    private var formulaire: some View {
        VStack(spacing: 12) {
            champ("Adresse e-mail", systemImage: "envelope", texte: $email, champ: .email)
            champ(
                mode == .inscription ? "Mot de passe (6 caractères min.)" : "Mot de passe",
                systemImage: "lock",
                texte: $motDePasse,
                champ: .motDePasse,
                secret: true
            )

            if mode == .connexion {
                Button("Mot de passe oublié ?") {
                    Task { await envoyerReinitialisation() }
                }
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            Button {
                Task { await valider() }
            } label: {
                HStack(spacing: 8) {
                    if enCours { ProgressView().tint(.white) }
                    Text(mode == .inscription ? "Créer mon compte" : "Se connecter")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .foregroundStyle(.white)
                .background(Couleurs.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(enCours || email.isEmpty || motDePasse.count < 6)
            .opacity(enCours || email.isEmpty || motDePasse.count < 6 ? 0.55 : 1)
        }
    }

    private func champ(
        _ invite: LocalizedStringKey,
        systemImage: String,
        texte: Binding<String>,
        champ cible: Champ,
        secret: Bool = false
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Group {
                if secret {
                    SecureField(invite, text: texte)
                } else {
                    TextField(invite, text: texte)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .autocapitalization(.none)
                }
            }
            .autocorrectionDisabled()
            .focused($champActif, equals: cible)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            Color(uiColor: .secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }

    private func message(_ texte: String, couleur: Color) -> some View {
        Text(texte)
            .font(.caption)
            .foregroundStyle(couleur)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Les couvertures du mur

    private func chargerLeMur() async {
        let besoin = 24

        // JAMAIS d'écran nu, pas même à la toute première ouverture : le mur
        // de la dernière fois s'affiche tel quel, et faute de souvenir, un jeu
        // de départ embarqué dans l'app prend la place. Le réseau ne sert qu'à
        // préparer l'ouverture suivante — il ne redistribue jamais sous les
        // yeux.
        if !poserDepuisCache() {
            poser(Self.jeuDeDepart)
        }

        for essai in 0..<4 {
            if Task.isCancelled { return }
            if essai > 0 {
                try? await Task.sleep(for: .seconds(Double(essai) * 2))
            }

            // Les deux classements du pays, mêlés puis battus comme un jeu de
            // cartes : les têtes d'affiche du moment, dans un ordre différent
            // à chaque ouverture.
            async let payants = Decouverte.classement(gratuits: false, langue: langue)
            async let libres = Decouverte.classement(gratuits: true, langue: langue)
            var tirage = await payants + libres
            if tirage.isEmpty && essai == 3 {
                tirage = await Decouverte.rayonBrut("roman", langue: langue)
            }
            guard !tirage.isEmpty else { continue }

            var vues = Set<String>()
            let jeu = tirage.shuffled().compactMap { resultat -> Vignette? in
                // Uniquement de vraies couvertures : une case de remplacement
                // au milieu des tendances se verrait tout de suite.
                guard let url = resultat.couvertureURL,
                      vues.insert(url).inserted else { return nil }
                return Vignette(id: resultat.id, url: url, titre: resultat.titre,
                                manga: resultat.type != .livre)
            }
            if !jeu.isEmpty {
                garder(Array(jeu.prefix(besoin)))
                return
            }
        }
    }

    /// Les couvertures de la toute première ouverture, avant tout réseau :
    /// des valeurs sûres du catalogue français, romans et mangas mêlés. Dès la
    /// deuxième ouverture, le tirage des tendances du pays prend la place.
    private static let jeuDeDepart: [Vignette] = [
        Vignette(id: "depart-0", url: "https://is1-ssl.mzstatic.com/image/thumb/Publication112/v4/df/c6/61/dfc661fb-7824-9cd8-7601-26b94a6439fb/9782824637167-001-x.jpeg/600x600bb.jpg", titre: "La femme de ménage", manga: false),
        Vignette(id: "depart-1", url: "https://is1-ssl.mzstatic.com/image/thumb/Publication124/v4/ec/92/42/ec9242c6-e6af-fbe7-1cc4-b4bb34f7758b/9782709641920-001-x.jpeg/600x600bb.jpg", titre: "Cinquante nuances de Grey", manga: false),
        Vignette(id: "depart-2", url: "https://is1-ssl.mzstatic.com/image/thumb/Publication116/v4/0c/a9/46/0ca94621-e8a9-f304-80f2-f180f2f3aab7/9782755630756-001-x.jpeg/600x600bb.jpg", titre: "Jamais plus", manga: false),
        Vignette(id: "depart-3", url: "https://is1-ssl.mzstatic.com/image/thumb/Publication221/v4/e1/bf/68/e1bf6862-6bbb-3b99-5a9d-866b4442b18a/9782755648720-001-x.jpeg/600x600bb.jpg", titre: "Verity", manga: false),
        Vignette(id: "depart-4", url: "https://is1-ssl.mzstatic.com/image/thumb/Publication116/v4/aa/d1/29/aad129f2-b1dd-fa8f-5239-8e720646ef30/9782811235949-001-x.jpeg/600x600bb.jpg", titre: "Les Sept Maris d'Evelyn Hugo", manga: false),
        Vignette(id: "depart-5", url: "https://is1-ssl.mzstatic.com/image/thumb/Publication211/v4/28/7a/85/287a858d-2b91-e220-79fd-3b5b935d6d86/9782709645126-001-x.jpeg/600x600bb.jpg", titre: "Da Vinci Code - version française", manga: false),
        Vignette(id: "depart-6", url: "https://is1-ssl.mzstatic.com/image/thumb/Publication221/v4/2e/f9/30/2ef9305d-ed76-78c8-7619-415667064083/9781781105986.jpg/600x600bb.jpg", titre: "Harry Potter à L'école des Sorciers (Enhanced Edition)", manga: false),
        Vignette(id: "depart-7", url: "https://is1-ssl.mzstatic.com/image/thumb/Publication124/v4/0e/b4/1a/0eb41ac2-ddfa-004e-2f36-1486d87d2009/9782072431258.jpg/600x600bb.jpg", titre: "Le Petit Prince", manga: false),
        Vignette(id: "depart-8", url: "https://is1-ssl.mzstatic.com/image/thumb/Publication126/v4/d5/85/1a/d5851a16-5cd9-ced5-bb77-6e75c8c3b9ef/d1c368f5-a3e5-4d0e-85a6-8ffdf8952dc9_cover_image.png/600x600bb.jpg", titre: "1984", manga: false),
        Vignette(id: "depart-9", url: "https://is1-ssl.mzstatic.com/image/thumb/Publication221/v4/57/7e/f0/577ef0d8-38fa-cf1a-ceba-2c0ead263f76/9782072376429.jpg/600x600bb.jpg", titre: "L'étranger", manga: false),
        Vignette(id: "depart-10", url: "https://is1-ssl.mzstatic.com/image/thumb/Publication221/v4/eb/25/74/eb2574fd-be3b-1bff-cc40-7c9bab9bc6bc/9782221127483.jpg/600x600bb.jpg", titre: "Dune - Tome 1", manga: false),
        Vignette(id: "depart-11", url: "https://is1-ssl.mzstatic.com/image/thumb/Publication221/v4/30/2b/a1/302ba156-ad04-ea54-8c30-397093599ef7/9782330071035.jpg/600x600bb.jpg", titre: "Le problème à trois corps", manga: false),
        Vignette(id: "depart-12", url: "https://is1-ssl.mzstatic.com/image/thumb/Publication114/v4/5f/31/34/5f3134d6-b6d6-fd37-8f6e-52562aa35615/9782823874778.jpg/600x600bb.jpg", titre: "Il était deux fois", manga: false),
        Vignette(id: "depart-13", url: "https://is1-ssl.mzstatic.com/image/thumb/Publication4/v4/dd/56/03/dd56030e-ff13-7028-0e6c-70d9af43fbd0/9782081345980.jpg/600x600bb.jpg", titre: "L'Alchimiste", manga: false),
        Vignette(id: "depart-14", url: "https://is1-ssl.mzstatic.com/image/thumb/Publication211/v4/97/73/21/97732192-1702-3256-f28e-6c0ef0980bde/cover.jpg/600x600bb.jpg", titre: "Le Comte de Monte-Cristo - Alexandre Dumas", manga: false),
        Vignette(id: "depart-15", url: "https://is1-ssl.mzstatic.com/image/thumb/Publication211/v4/cb/a4/22/cba4222a-e625-1802-e3e2-0d860ac012e9/9782331089893-001-x.jpeg/600x600bb.jpg", titre: "One Piece - Édition originale - Tome 113", manga: true),
        Vignette(id: "depart-16", url: "https://is1-ssl.mzstatic.com/image/thumb/Publication123/v4/fa/ad/7a/faad7a51-1b9b-f5ba-bef2-040b8e4527c2/9782809484069-001-x.jpeg/600x600bb.jpg", titre: "Demon Slayer T01", manga: true),
        Vignette(id: "depart-17", url: "https://is1-ssl.mzstatic.com/image/thumb/Publication124/v4/7a/7d/65/7a7d65b5-dd10-dda6-ad66-f1d63d4a28e7/9782820339744-001-x.jpeg/600x600bb.jpg", titre: "Chainsaw Man - Chapitre 1", manga: true),
        Vignette(id: "depart-18", url: "https://is1-ssl.mzstatic.com/image/thumb/Publication3/v4/36/16/d1/3616d14d-1dc4-2743-f255-a62236557967/9782811617462-X.jpg/600x600bb.jpg", titre: "L'Attaque des Titans T10", manga: true),
        Vignette(id: "depart-19", url: "https://is1-ssl.mzstatic.com/image/thumb/Publication116/v4/0e/6f/82/0e6f8246-88ce-c868-8ae5-7fb070522b63/9782505032182.jpg/600x600bb.jpg", titre: "Death Note - Tome 1", manga: true),
    ]

    /// Le dernier tirage, gardé sur l'appareil pour l'ouverture suivante.
    private static let cleCache = "murAccueil"

    private func poserDepuisCache() -> Bool {
        guard let donnees = UserDefaults.standard.data(forKey: Self.cleCache),
              let jeu = try? JSONDecoder().decode([Vignette].self, from: donnees),
              !jeu.isEmpty
        else { return false }
        poser(jeu)
        return true
    }

    private func garder(_ jeu: [Vignette]) {
        if let donnees = try? JSONEncoder().encode(jeu) {
            UserDefaults.standard.set(donnees, forKey: Self.cleCache)
        }
    }

    /// Pose le mur d'un coup, sans fondu : l'apparition progressive créait un
    /// état intermédiaire où les couvertures traversaient le voile à moitié
    /// posé — l'écran semblait s'assombrir petit à petit.
    private func poser(_ jeu: [Vignette]) {
        vignettes = jeu
    }

    // MARK: - Actions

    private func traiterApple(_ resultat: Result<ASAuthorization, Error>) {
        switch resultat {
        case .success(let autorisation):
            guard let identite = autorisation.credential as? ASAuthorizationAppleIDCredential
            else { return }
            Task { await compte.connecterAvecApple(identite) }
        case .failure(let souci):
            // Une annulation n'est pas une erreur : on ne dit rien.
            let code = (souci as? ASAuthorizationError)?.code
            if code != .canceled && code != .unknown {
                erreur = String(localized: "La connexion n'a pas abouti. Réessayez dans un instant.")
            }
        }
    }

    private func valider() async {
        champActif = nil
        erreur = nil
        information = nil
        enCours = true
        defer { enCours = false }

        let adresse = email.trimmingCharacters(in: .whitespaces)
        do {
            if mode == .inscription {
                if let attente = try await compte.inscrire(email: adresse, motDePasse: motDePasse) {
                    information = attente
                    mode = .connexion
                }
            } else {
                try await compte.connecter(email: adresse, motDePasse: motDePasse)
            }
        } catch {
            erreur = error.localizedDescription
        }
    }

    private func envoyerReinitialisation() async {
        let adresse = email.trimmingCharacters(in: .whitespaces)
        guard !adresse.isEmpty else {
            erreur = String(localized: "Saisissez d'abord votre adresse e-mail.")
            return
        }
        erreur = nil
        do {
            try await compte.envoyerReinitialisation(email: adresse)
            information = String(localized: "Un courrier vient de partir vers \(adresse).")
        } catch {
            erreur = error.localizedDescription
        }
    }
}

#Preview {
    BienvenueView()
        .modelContainer(Apercu.conteneur)
}

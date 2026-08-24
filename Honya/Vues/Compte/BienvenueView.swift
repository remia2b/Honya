import AuthenticationServices
import SwiftData
import SwiftUI

/// La toute première page : un mur de couvertures qui dérive lentement, le nom
/// en serif, et deux chemins pour entrer — l'identifiant Apple, ou une adresse
/// e-mail.
///
/// Le mur montre les livres du lecteur dès qu'il en a : l'écran d'accueil
/// devient le sien. Sinon, les meilleures ventes de son pays. Sans réseau,
/// `CouvertureView` dessine ses couvertures de secours, et la mise en page
/// tient quand même.
struct BienvenueView: View {
    @Environment(\.colorScheme) private var apparence
    @Environment(\.accessibilityReduceMotion) private var mouvementReduit

    @Query private var oeuvres: [Oeuvre]
    @Query private var series: [Serie]
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
    private struct Vignette: Identifiable, Hashable {
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
                voile.ignoresSafeArea()
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
        .opacity(apparu ? 1 : 0)
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

    /// Le voile qui ramène le mur au fond : transparent en haut pour laisser
    /// voir les livres, opaque en bas pour que le texte se lise sans effort.
    private var voile: some View {
        let fond = Color(uiColor: .systemBackground)
        return LinearGradient(
            stops: [
                .init(color: fond.opacity(0.42), location: 0),
                .init(color: fond.opacity(0), location: 0.16),
                .init(color: fond.opacity(0), location: 0.33),
                .init(color: fond.opacity(0.90), location: 0.53),
                .init(color: fond, location: 0.63),
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

        // Ce que le lecteur possède déjà s'affiche TOUT DE SUITE : attendre le
        // réseau avant de rien montrer laisserait l'écran nu alors qu'on a
        // déjà de quoi le remplir.
        let siennes = couverturesDeLaBibliotheque()
        if !siennes.isEmpty {
            vignettes = Array(siennes.prefix(besoin))
        }
        if siennes.count >= besoin { return }

        // Le réseau du premier lancement est capricieux, et cet appel ne se
        // refait pas de lui-même : un échec unique laisserait le mur vide pour
        // toujours. On retente donc calmement, et on change de source si le
        // classement payant ne répond pas.
        for essai in 0..<4 {
            if Task.isCancelled { return }
            if essai > 0 {
                try? await Task.sleep(for: .seconds(Double(essai) * 2))
            }

            var top = await Decouverte.classement(gratuits: false, langue: langue)
            if top.isEmpty {
                top = await Decouverte.classement(gratuits: true, langue: langue)
            }
            if top.isEmpty && essai == 3 {
                // Dernier recours : le catalogue de recherche, une seule
                // requête, qui passe par la même file d'attente que le reste.
                top = await Decouverte.rayonBrut("roman", langue: langue)
            }
            guard !top.isEmpty else { continue }

            let venues = top.map {
                Vignette(id: $0.id, url: $0.couvertureURL, titre: $0.titre,
                         manga: $0.type != .livre)
            }
            let assemblees = siennes + venues.filter { venue in
                !siennes.contains { $0.url == venue.url }
            }
            if !assemblees.isEmpty {
                vignettes = Array(assemblees.prefix(besoin))
                return
            }
        }
    }

    private func couverturesDeLaBibliotheque() -> [Vignette] {
        var vues = Set<String>()
        var resultat: [Vignette] = []

        for serie in series {
            guard let url = serie.couvertureAffichee, vues.insert(url).inserted else { continue }
            resultat.append(Vignette(id: "serie-\(url)", url: url,
                                     titre: serie.nomAffiche(langue), manga: serie.type != .livre))
        }
        for oeuvre in oeuvres {
            guard let url = oeuvre.couvertureAffichee, vues.insert(url).inserted else { continue }
            resultat.append(Vignette(id: "oeuvre-\(url)", url: url,
                                     titre: oeuvre.titre(langue), manga: oeuvre.type != .livre))
        }
        return resultat.shuffled()
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

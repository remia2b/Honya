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
    /// Ouvre directement le formulaire, pour les aperçus et les captures.
    var surLEmail = false

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

    /// Le mot de passe oublié occupe la même plaque que la connexion : c'est
    /// la même page, on ne change pas d'écran pour trois champs.
    @State private var oubli = false
    @State private var codeEnvoye = false
    @State private var code = ""
    @State private var nouveauMotDePasse = ""

    private enum Champ { case email, motDePasse, code, nouveau }

    /// Le clavier est-il ouvert — sans dire sur quel champ.
    ///
    /// C'est la distinction qui compte. Animer sur `champActif` déclenchait une
    /// transition à CHAQUE passage d'un champ à l'autre, alors que rien ne
    /// change à l'écran à ce moment-là : la seule chose qui bougeait était le
    /// décalage imposé par le clavier, qui se retrouvait animé deux fois — par
    /// iOS avec sa courbe, et par nous avec la nôtre. D'où le saut.
    private var enSaisie: Bool { champActif != nil }

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

            if !vignettes.isEmpty {
                // Le mur reste derrière l'écran e-mail : c'est la même page,
                // pas un formulaire posé sur du vide.
                //
                // `.keyboard` explicitement : à l'ouverture du clavier, iOS
                // rétrécit la zone sûre et le décor se serait redimensionné
                // avec le formulaire. Le fond doit rester immobile.
                mur
                    .ignoresSafeArea()
                    .ignoresSafeArea(.keyboard)
                voile
                    .ignoresSafeArea()
                    .ignoresSafeArea(.keyboard)
                    .animation(.snappy(duration: 0.28), value: enSaisie)
            }

            ecranAccueil
        }
        .task { await chargerLeMur() }
        .onAppear {
            withAnimation(.easeOut(duration: 0.7)) { apparu = true }
            if surLEmail { parEmail = true }
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

    /// Le voile : RIEN sur les livres — ils se montrent tels quels — puis une
    /// pénombre qui s'installe sous le titre et les boutons SANS jamais
    /// devenir opaque : les couvertures restent en fantôme derrière.
    private var voile: some View {
        let fond = Color(uiColor: .systemBackground)
        // Pendant la saisie, le clavier remonte le formulaire jusqu'au milieu
        // de l'écran : la pénombre doit remonter avec lui, sinon les
        // couvertures percent derrière les champs.
        return LinearGradient(
            stops: !enSaisie
                ? [
                    .init(color: fond.opacity(0), location: 0),
                    .init(color: fond.opacity(0), location: 0.40),
                    .init(color: fond.opacity(0.78), location: 0.56),
                    .init(color: fond.opacity(0.90), location: 0.74),
                    .init(color: fond.opacity(0.93), location: 1),
                  ]
                : [
                    .init(color: fond.opacity(0.30), location: 0),
                    .init(color: fond.opacity(0.62), location: 0.14),
                    .init(color: fond.opacity(0.88), location: 0.28),
                    .init(color: fond.opacity(0.95), location: 1),
                  ],
            startPoint: .top, endPoint: .bottom
        )
    }

    // MARK: - L'accueil

    private var ecranAccueil: some View {
        // Une pile ordinaire, décalée par l'évitement automatique du clavier
        // (SwiftUI, iOS 14+). Rien à écrire pour cela : il suffit de ne pas
        // l'empêcher de travailler. `.ignoresSafeArea(.keyboard)` ne se pose
        // donc QUE sur le décor, jamais ici ni sur la racine — posé trop haut,
        // il désactive l'évitement pour tout ce qu'il couvre.
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            if !enSaisie {
                    // Le titre s'efface pendant la saisie : sur un écran
                    // réduit par le clavier, il finissait par chevaucher les
                    // couvertures et le formulaire.
                VStack(spacing: 10) {
                    Text("Honya")
                        .font(.system(size: 46, weight: .semibold, design: .serif))
                    Text("Rangez vos livres, suivez vos lectures.")
                        .font(.system(size: 17))
                        .foregroundStyle(.primary.opacity(0.85))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 26)
                .padding(.bottom, parEmail ? 20 : 28)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if parEmail {
                formulaireEnBas
            } else {
                entrees
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.snappy(duration: 0.28), value: enSaisie)
        .animation(.snappy(duration: 0.3), value: parEmail)
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
                    // Un matériau, pas une teinte : sur un mur de couvertures,
                    // un fond à 6 % disparaissait et le bouton semblait n'être
                    // que du texte posé là.
                    .background(
                        .regularMaterial,
                        in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                    )
            }
            .buttonStyle(.plain)

        }
        .padding(.horizontal, 24)
        .padding(.bottom, 34)
    }

    // MARK: - L'entrée par e-mail

    /// Le formulaire prend la place des deux boutons, en bas, sans rien
    /// changer d'autre : même mur, même voile, même titre. Changer d'écran
    /// pour trois champs cassait la continuité de la page d'accueil.
    private var formulaireEnBas: some View {
        VStack(spacing: 12) {
            if oubli {
                contenuOubli
            } else {
                contenuConnexion
            }

            if let information {
                message(information, couleur: Couleurs.lu)
            }
            if let erreur {
                message(erreur, couleur: .red)
            }

            liens
        }
        .padding(20)
        // Une plaque sous tout le bloc : sans elle, sélecteur, champs et
        // mentions flottaient chacun sur des couvertures différentes.
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color(uiColor: .systemBackground).opacity(0.55))
                )
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 26)
        .animation(.snappy(duration: 0.25), value: oubli)
        .animation(.snappy(duration: 0.25), value: codeEnvoye)
    }

    private var contenuConnexion: some View {
        Group {
            Picker("", selection: $mode) {
                ForEach(Mode.allCases) { cas in
                    Text(cas.libelle).tag(cas)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: mode) { _, _ in
                erreur = nil
                information = nil
            }

            champ("Adresse e-mail", systemImage: "envelope", texte: $email, champ: .email)
            champ(
                mode == .inscription ? "Mot de passe (6 caractères min.)" : "Mot de passe",
                systemImage: "lock",
                texte: $motDePasse,
                champ: .motDePasse,
                secret: true
            )

            bouton(
                titre: mode == .inscription ? "Créer mon compte" : "Se connecter",
                actif: !email.isEmpty && motDePasse.count >= 6
            ) {
                await valider()
            }
        }
    }

    /// Le mot de passe oublié se termine ici, par un code à recopier.
    ///
    /// Pas de lien à suivre : un lien suppose que Honya sache se faire rouvrir
    /// depuis Safari, et sort le lecteur de l'écran où il était. Le code se
    /// recopie sans quitter l'application.
    private var contenuOubli: some View {
        Group {
            VStack(spacing: 4) {
                Text("Réinitialiser le mot de passe")
                    .font(.system(size: 16, weight: .semibold))
                Text(codeEnvoye
                     ? "Recopiez le code reçu, puis choisissez votre nouveau mot de passe."
                     : "Un code part vers votre adresse, à recopier ici même.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 2)

            champ("Adresse e-mail", systemImage: "envelope", texte: $email, champ: .email)

            if codeEnvoye {
                champ("Code reçu par courrier", systemImage: "number",
                      texte: $code, champ: .code, clavier: .numberPad)
                champ("Nouveau mot de passe (6 caractères min.)", systemImage: "lock.rotation",
                      texte: $nouveauMotDePasse, champ: .nouveau, secret: true)

                bouton(
                    titre: "Valider et me connecter",
                    actif: code.count >= 4 && nouveauMotDePasse.count >= 6
                ) {
                    await terminerReinitialisation()
                }
            } else {
                bouton(
                    titre: "Envoyer le code",
                    actif: !email.trimmingCharacters(in: .whitespaces).isEmpty
                ) {
                    await envoyerReinitialisation()
                }
            }
        }
    }

    private func bouton(
        titre: LocalizedStringKey, actif: Bool, action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            HStack(spacing: 8) {
                if enCours { ProgressView().tint(.white) }
                Text(titre)
                    .font(.system(size: 17, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .foregroundStyle(.white)
            .background(Couleurs.accent, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(enCours || !actif)
        .opacity(enCours || !actif ? 0.55 : 1)
    }

    private var liens: some View {
        HStack(spacing: 18) {
            Button("Retour") {
                champActif = nil
                erreur = nil
                information = nil
                if oubli {
                    oubli = false
                    codeEnvoye = false
                    code = ""
                    nouveauMotDePasse = ""
                } else {
                    parEmail = false
                }
            }
            Spacer(minLength: 0)
            if oubli {
                if codeEnvoye {
                    Button("Renvoyer le code") {
                        Task { await envoyerReinitialisation() }
                    }
                    .disabled(enCours)
                }
            } else {
                Button("Mot de passe oublié ?") {
                    erreur = nil
                    information = nil
                    oubli = true
                }
            }
        }
        .font(.system(size: 14, weight: .semibold))
        .tint(.primary.opacity(0.75))
        .padding(.top, 2)
    }

    private var sousTitreEmail: String {
        mode == .inscription
            ? String(localized: "Créez votre compte avec une adresse e-mail.")
            : String(localized: "Content de vous revoir.")
    }

    private func champ(
        _ invite: LocalizedStringKey,
        systemImage: String,
        texte: Binding<String>,
        champ cible: Champ,
        secret: Bool = false,
        clavier: UIKeyboardType? = nil
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Group {
                if secret {
                    SecureField(invite, text: texte)
                } else if let clavier {
                    TextField(invite, text: texte)
                        .keyboardType(clavier)
                        .textContentType(.oneTimeCode)
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
        // Sur un mur de couvertures, un matériau seul se noyait : il lui faut
        // un fond opaque dessous et un contour net pour que le champ se lise
        // comme un champ.
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.16), lineWidth: 1)
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
        guard !adresse.isEmpty else { return }
        champActif = nil
        erreur = nil
        enCours = true
        defer { enCours = false }
        do {
            try await compte.envoyerReinitialisation(email: adresse)
            codeEnvoye = true
            information = String(localized: "Un courrier vient de partir vers \(adresse).")
        } catch {
            erreur = error.localizedDescription
        }
    }

    private func terminerReinitialisation() async {
        champActif = nil
        erreur = nil
        information = nil
        enCours = true
        defer { enCours = false }
        do {
            try await compte.reinitialiser(
                email: email.trimmingCharacters(in: .whitespaces),
                code: code.trimmingCharacters(in: .whitespaces),
                nouveau: nouveauMotDePasse
            )
        } catch {
            erreur = error.localizedDescription
        }
    }
}

#Preview {
    BienvenueView()
        .modelContainer(Apercu.conteneur)
}

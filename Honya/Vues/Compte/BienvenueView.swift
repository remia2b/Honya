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
    /// Ouvre le mot de passe oublié : « demande » à l'étape du courrier,
    /// « code » à l'étape de saisie.
    var surLOubli: String?
    /// Reprise d'une suppression interrompue : le même compte uniquement,
    /// sans possibilité d'en créer un autre.
    var connexionSeulement = false

    @Environment(\.colorScheme) private var apparence
    @Environment(\.accessibilityReduceMotion) private var mouvementReduit

    @Query private var objectifs: [Objectif]

    @State private var compte = Compte.partage
    @State private var vignettes: [Vignette] = []
    /// Le mur n'est publié qu'avec des pixels déjà décodés. Conserver les
    /// UIImage ici empêche le premier rendu factice de `CouvertureView`.
    @State private var imagesMur: [String: UIImage] = [:]
    @State private var apparu = false
    /// Origine locale de la derive. Une date absolue faisait commencer le mur
    /// a un endroit arbitraire de sa boucle a chaque apparition.
    @State private var debutMur = Date()

    @State private var parEmail = false
    @State private var mode: Mode = .inscription
    @State private var email = ""
    @State private var motDePasse = ""
    @State private var enCours = false
    @State private var erreur: String?
    @State private var information: String?
    @State private var session = SessionClavier()
    @Environment(\.scenePhase) private var vieApplication

    /// La plaque est un escalier : une marche, UN champ. La bascule de
    /// premier répondant entre deux champs fait re-négocier AutoFill et
    /// reconstruit le clavier — à une marche par champ, on ne bascule plus.
    private enum Marche: Equatable {
        case adresse            // l'e-mail, porte d'entrée de tout
        case motDePasse         // connexion ou inscription
        case oubliEnvoi         // l'e-mail part chercher un code
        case oubliCode          // le code reçu
        case oubliNouveau       // le nouveau mot de passe
    }

    @State private var marche: Marche = .adresse
    /// Le compte existe mais son adresse n'est pas confirmée : on propose
    /// alors de refaire partir le courrier.
    @State private var confirmationAttendue = false
    @State private var code = ""
    @State private var nouveauMotDePasse = ""

    /// L'écran est-il à l'étroit : clavier ouvert, ou formulaire long.
    ///
    /// La réinitialisation avec son code compte trois champs et un en-tête :
    /// la plaque monte, et le titre se retrouvait posé sur des couvertures en
    /// pleine lumière, là où la pénombre ne descend pas encore.
    private var alEtroit: Bool { enSaisie }

    /// La saisie est-elle en cours — au sens de la session, pas du focus.
    ///
    /// C'est la distinction qui compte : le focus SwiftUI s'éteint un
    /// instant pendant le passage d'un champ à l'autre, alors que rien ne
    /// change à l'écran à ce moment-là. La session, elle, s'ouvre au premier
    /// champ et ne se ferme qu'une fois la saisie réellement terminée.
    private var enSaisie: Bool { session.enSaisie }

    private var proposerApple: Bool {
        !connexionSeulement || compte.methodeReconnexionSuppression == .apple
    }

    private var proposerEmail: Bool {
        // En cas d'ancien état incomplet, l'e-mail reste le seul chemin qui ne
        // puisse pas créer silencieusement une nouvelle identité OIDC.
        !connexionSeulement || compte.methodeReconnexionSuppression != .apple
    }

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
        /// Conserve la provenance avec le cache. Le mur ne transforme jamais
        /// une image issue d'une source ouverte en visuel « sans auteur ».
        let attribution: String?

        init(
            id: String,
            url: String?,
            titre: String,
            manga: Bool,
            attribution: String? = nil
        ) {
            self.id = id
            self.url = url
            self.titre = titre
            self.manga = manga
            self.attribution = attribution
        }
    }

    // Trois colonnes qui se recouvrent : le nombre de couvertures par colonne
    // se déduit de la hauteur de l'écran, il n'est pas figé.
    private static let colonnes = 3
    private static let ecart: CGFloat = 4
    private static let marge: CGFloat = 0
    /// Les colonnes ne démarrent pas au même endroit, sinon les couvertures
    /// forment des rangées bien alignées et le mur perd sa vie. Exprimé en
    /// fraction d'une couverture, jamais plus d'une : au-delà, la boucle
    /// laisserait le bas de l'écran à découvert.
    private static let departs: [CGFloat] = [-0.06, -0.34, -0.16]
    private static let durees: [Double] = [66, 78, 58]

    private var langue: String {
        objectifs.first?.languePrincipale ?? Langues.codeAppareil
    }

    /// Une edition anglaise du store US et une edition anglaise du store GB
    /// peuvent avoir des titres et couvertures differents. Le souvenir du mur
    /// est donc cloisonne par langue ET par storefront, comme le catalogue.
    private var cleCacheMur: String {
        let code = langue.lowercased()
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .first.map(String.init) ?? langue.lowercased()
        let storefront = Langues.storefront(pourLangue: langue).lowercased()
        return "murAccueilV3.\(code).\(storefront)"
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
                    .animation(.snappy(duration: 0.28), value: alEtroit)
            }

            // L'écran vit dans le contrôleur qui ancre au guide clavier
            // d'Apple — voir AncrageClavier.swift : l'évitement SwiftUI y est
            // coupé, et la position se fige une fois le clavier posé. Les
            // deux ignoresSafeArea rendent bien TOUT l'écran au contrôleur ;
            // à l'intérieur, c'est UIKit qui place le contenu.
            AncrageClavier(
                phase: session.phase,
                fermetureVoulue: { session.phase != .active },
                clavierRange: { session.clavierRange() }
            ) {
                ecranAccueil
            }
            .ignoresSafeArea()
            .ignoresSafeArea(.keyboard)
        }
        .onChange(of: compte.adresseVientDEtreConfirmee) { _, confirme in
            guard confirme else { return }
            withAnimation(.snappy(duration: 0.3)) {
                parEmail = true
                marche = .adresse
                mode = .connexion
                // L'adresse revient du serveur : il ne reste que le mot de
                // passe à donner.
                if let adresse = compte.email, !adresse.isEmpty { email = adresse }
                erreur = nil
                information = nil
                confirmationAttendue = false
            }
        }
        .onChange(of: compte.soucisDeConfirmation) { _, souci in
            // Le lien n'a pas abouti : on ouvre quand même la plaque et on
            // dit pourquoi. Le courrier peut toujours repartir.
            guard let souci else { return }
            withAnimation(.snappy(duration: 0.3)) {
                parEmail = true
                marche = .adresse
                erreur = souci
                information = nil
                confirmationAttendue = true
            }
        }
        .onChange(of: vieApplication) { _, etat in
            switch etat {
            case .background:
                fermerLeClavier()
            case .active:
                session.reconcilier()
            default:
                break
            }
        }
        .task(id: cleCacheMur) {
            // Un changement de langue/storefront ne doit jamais laisser le
            // mur précédent visible pendant que le nouveau se prépare.
            poser([], images: [:])
            await chargerLeMur()
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.7)) { apparu = true }
            if connexionSeulement { mode = .connexion }
            if surLEmail { parEmail = true }
            if let surLOubli {
                parEmail = true
                switch surLOubli {
                case "code":
                    email = "remi@exemple.fr"
                    marche = .oubliCode
                case "nouveau":
                    email = "remi@exemple.fr"
                    marche = .oubliNouveau
                case "mdp":
                    email = "remi@exemple.fr"
                    marche = .motDePasse
                default:
                    marche = .oubliEnvoi
                }
            }
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
                // La timeline est deja pausee avec Reduce Motion ; la phase
                // zero explicite garantit aussi une composition immobile si
                // SwiftUI recalcule le contexte apres un changement d'etat.
                let instant = mouvementReduit
                    ? 0
                    : max(0, contexte.date.timeIntervalSince(debutMur))

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
                vignetteDuMur(vignette)
                // Hauteur imposée avec la largeur : CouvertureView porte un
                // aspectRatio(.fit), et sans hauteur fixe la pile la ferait
                // rétrécir en largeur pour tenir le ratio.
                .frame(width: largeur, height: largeur * 1.5)
            }
        }
        .offset(y: position)
    }

    @ViewBuilder
    private func vignetteDuMur(_ vignette: Vignette) -> some View {
        if let url = vignette.url, let image = imagesMur[url] {
            CouvertureView(
                urlString: vignette.url,
                titre: vignette.titre,
                coins: 5,
                manga: vignette.manga,
                cote: 700,
                imagePrechargee: image
            )
            // Le mur est un decor : VoiceOver doit atteindre directement le
            // titre et les choix de connexion, pas enumerer le mur.
            .accessibilityHidden(true)
        } else {
            // Une URL morte ou une image non décodable n'a jamais droit à une
            // couverture inventée sur la page qui présente l'application.
            Color.clear
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                .accessibilityHidden(true)
        }
    }

    private func vignettesDeLaColonne(_ index: Int, combien: Int) -> [Vignette] {
        guard !vignettes.isEmpty else { return [] }
        return (0..<combien).map { rang in
            // Distribuer horizontalement d'abord : avec seulement trois
            // couvertures valides, chaque colonne reçoit ainsi la sienne au
            // lieu d'afficher les trois mêmes rangées parfaitement alignées.
            vignettes[(rang * Self.colonnes + index) % vignettes.count]
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
            stops: !alEtroit
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

    /// Ferme la saisie dans le bon ordre — la session d'abord, le focus
    /// ensuite : le contrôleur sait ainsi que le départ du clavier qui suit
    /// est voulu, et rattache le formulaire pour qu'ils descendent ensemble.
    private func fermerLeClavier() {
        session.fermerLaSaisie()
    }

    // MARK: - L'accueil

    private var ecranAccueil: some View {
        // Une pile ordinaire : son placement face au clavier appartient
        // entièrement au contrôleur d'ancrage qui l'héberge.
        VStack(spacing: 0) {
            // La zone au-dessus du formulaire — et elle seule — ferme la
            // saisie au toucher. Un rectangle réel plutôt qu'un Spacer : un
            // Spacer nu ne reçoit pas les gestes de façon fiable.
            ZStack {
                if enSaisie {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { fermerLeClavier() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !alEtroit {
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
        .animation(.snappy(duration: 0.28), value: alEtroit)
        .animation(.snappy(duration: 0.3), value: parEmail)
        .opacity(apparu ? 1 : 0)
        .offset(y: apparu ? 0 : 14)
        .animation(.easeOut(duration: 0.6).delay(0.15), value: apparu)
    }

    private var entrees: some View {
        VStack(spacing: 12) {
            if connexionSeulement {
                Text("Reconnectez-vous avec le compte dont la suppression a été demandée.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if proposerApple {
                SignInWithAppleButton(
                    .signIn,
                    onRequest: { compte.preparerDemandeApple($0) },
                    onCompletion: { traiterApple($0) }
                )
                .signInWithAppleButtonStyle(apparence == .dark ? .white : .black)
                .frame(height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            }

            if proposerEmail {
                Button {
                    erreur = nil
                    information = nil
                    marche = .adresse
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
            liensLegaux
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
            if compte.adresseVientDEtreConfirmee {
                bandeauConfirmee
            }

            enTeteDeMarche

            // De vrais UITextField dans un arbre persistant, UN SEUL visible
            // par marche : le clavier s'ouvre et se ferme, il ne se
            // transfère plus jamais d'un champ à l'autre.
            ChampsSession(
                configuration: configurationChamps,
                email: $email,
                motDePasse: $motDePasse,
                code: $code,
                nouveau: $nouveauMotDePasse,
                session: session
            ) {
                Task { await validationParClavier() }
            }

            boutonPrincipal

            if let information {
                message(information, couleur: Couleurs.lu)
            }
            if let erreur {
                message(erreur, couleur: .red)
            }

            if confirmationAttendue {
                // Le premier courrier se perd, s'efface, part dans les
                // indésirables. Sans cette porte, un compte créé mais non
                // confirmé reste inutilisable pour toujours.
                Button {
                    Task { await renvoyerLaConfirmation() }
                } label: {
                    Text("Renvoyer le courrier de confirmation")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .foregroundStyle(Couleurs.accent)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Couleurs.accent.opacity(0.12))
                        )
                }
                .buttonStyle(.plain)
                .disabled(enCours)
            }

            liens
            liensLegaux
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
        .animation(.snappy(duration: 0.25), value: marche)
    }

    /// Le retour de la boîte aux lettres : l'adresse est confirmée, il ne
    /// reste qu'à entrer. Vert, comme tout ce qui est accompli dans Honya.
    private var bandeauConfirmee: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Couleurs.lu)
            Text("Adresse confirmée. Connectez-vous.")
                .font(.system(size: 13.5, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Couleurs.lu.opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Couleurs.lu.opacity(0.45), lineWidth: 1)
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var configurationChamps: ChampsSessionVue.Configuration {
        switch marche {
        case .adresse, .oubliEnvoi: return .email
        case .motDePasse: return .motDePasse(inscription: mode == .inscription)
        case .oubliCode: return .code
        case .oubliNouveau: return .nouveau
        }
    }

    /// Changer de marche ferme d'abord la saisie : le clavier descend avec
    /// la plaque, la marche suivante s'ouvre d'un toucher sur son champ.
    /// JAMAIS de transfert de focus — c'est lui qui faisait plonger le
    /// clavier.
    private func aller(a nouvelle: Marche) {
        fermerLeClavier()
        erreur = nil
        information = nil
        withAnimation(.snappy(duration: 0.25)) { marche = nouvelle }
    }

    @ViewBuilder
    private var enTeteDeMarche: some View {
        switch marche {
        case .adresse:
            // Un sélecteur maison plutôt que le segmenté d'iOS : sur la
            // plaque translucide posée devant les couvertures, ce dernier
            // s'effaçait au point qu'on ne voyait plus lequel des deux
            // chemins était pris — et on créait un compte en croyant se
            // connecter. Ici la pastille active porte la couleur de
            // l'application et du texte blanc.
            HStack(spacing: 4) {
                ForEach(connexionSeulement ? [Mode.connexion] : Mode.allCases) { cas in
                    Button {
                        guard mode != cas else { return }
                        erreur = nil
                        information = nil
                        confirmationAttendue = false
                        withAnimation(.snappy(duration: 0.22)) { mode = cas }
                    } label: {
                        Text(cas.libelle)
                            .font(.system(size: 15, weight: .semibold))
                            // Les deux branches nommées explicitement : un
                            // ternaire entre deux styles de nature différente
                            // ne se laisse pas déduire.
                            .foregroundStyle(mode == cas ? Color.white : Color.primary.opacity(0.7))
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .background {
                                if mode == cas {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Couleurs.accent)
                                        .shadow(color: Couleurs.accent.opacity(0.35), radius: 6, y: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            )

        case .motDePasse:
            // L'adresse retenue, et la porte pour la corriger : le lecteur
            // sait toujours pour quel compte il tape son mot de passe.
            HStack(spacing: 10) {
                Image(systemName: "envelope")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text(email)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Button("Modifier") { aller(a: .adresse) }
                    .font(.system(size: 13, weight: .semibold))
                    .tint(Couleurs.accent)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground).opacity(0.6))
            )

        case .oubliEnvoi, .oubliCode, .oubliNouveau:
            VStack(spacing: 4) {
                Text("Réinitialiser le mot de passe")
                    .font(.system(size: 16, weight: .semibold))
                Text(sousTitreOubli)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 2)
        }
    }

    private var sousTitreOubli: String {
        switch marche {
        case .oubliCode:
            return String(localized: "Recopiez le code reçu, puis choisissez votre nouveau mot de passe.")
        case .oubliNouveau:
            return String(localized: "Choisissez votre nouveau mot de passe.")
        default:
            return String(localized: "Un code part vers votre adresse, à recopier ici même.")
        }
    }

    @ViewBuilder
    private var boutonPrincipal: some View {
        switch marche {
        case .adresse:
            bouton(titre: "Continuer", actif: adresseValable) {
                aller(a: .motDePasse)
            }
        case .motDePasse:
            bouton(
                titre: mode == .inscription ? "Créer mon compte" : "Se connecter",
                actif: motDePasse.count >= 6
            ) {
                await valider()
            }
        case .oubliEnvoi:
            bouton(titre: "Envoyer le code", actif: adresseValable) {
                await envoyerReinitialisation()
            }
        case .oubliCode:
            bouton(titre: "Valider le code", actif: code.count >= 4) {
                await validerLeCode()
            }
        case .oubliNouveau:
            bouton(titre: "Valider et me connecter", actif: nouveauMotDePasse.count >= 6) {
                await terminerReinitialisation()
            }
        }
    }

    private var adresseValable: Bool {
        let adresse = email.trimmingCharacters(in: .whitespaces)
        return adresse.contains("@") && adresse.contains(".")
    }

    /// La touche retour du champ vaut le bouton de la marche.
    private func validationParClavier() async {
        switch marche {
        case .adresse:
            guard adresseValable else { return }
            aller(a: .motDePasse)
        case .motDePasse:
            guard motDePasse.count >= 6 else { return }
            await valider()
        case .oubliEnvoi:
            guard adresseValable else { return }
            await envoyerReinitialisation()
        case .oubliCode:
            guard code.count >= 4 else { return }
            await validerLeCode()
        case .oubliNouveau:
            guard nouveauMotDePasse.count >= 6 else { return }
            await terminerReinitialisation()
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
            Button("Retour") { revenir() }
            Spacer(minLength: 0)
            switch marche {
            case .adresse, .motDePasse:
                Button("Mot de passe oublié ?") { aller(a: .oubliEnvoi) }
            case .oubliCode:
                Button("Renvoyer le code") {
                    Task { await envoyerReinitialisation() }
                }
                .disabled(enCours)
            case .oubliEnvoi, .oubliNouveau:
                EmptyView()
            }
        }
        .font(.system(size: 14, weight: .semibold))
        .tint(.primary.opacity(0.75))
        .padding(.top, 2)
    }

    /// Accessible avant toute transmission d'adresse e-mail ou d'identite
    /// Apple, comme l'exige une creation de compte transparente.
    private var liensLegaux: some View {
        VStack(spacing: 5) {
            HStack(spacing: 16) {
                Link(
                    "Politique de confidentialité",
                    destination: URL(string: "https://www.honya.app/en/privacy/")!
                )
                Link(
                    "Conditions d’utilisation",
                    destination: URL(
                        string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
                    )!
                )
            }
            if !attributionsMur.isEmpty {
                // Une mention consolidee, pas un credit repete sur chaque case.
                // La provenance et la date viennent telles quelles du
                // fournisseur afin de respecter sa licence dans toute langue.
                Text(verbatim: attributionsMur.joined(separator: " · "))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(.top, 2)
    }

    private var attributionsMur: [String] {
        var vues = Set<String>()
        return vignettes.compactMap(\.attribution).filter { attribution in
            !attribution.isEmpty && vues.insert(attribution).inserted
        }
    }

    /// Chaque marche redescend d'où elle vient.
    private func revenir() {
        switch marche {
        case .adresse:
            fermerLeClavier()
            erreur = nil
            information = nil
            parEmail = false
        case .motDePasse, .oubliEnvoi:
            aller(a: .adresse)
        case .oubliCode:
            aller(a: .oubliEnvoi)
        case .oubliNouveau:
            aller(a: .oubliCode)
        }
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
        let besoin = 18
        // Une vraie couverture par colonne suffit pour composer le décor :
        // les colonnes savent répéter le jeu. Ce seuil bas garde donc le mur
        // disponible dans les langues dont les catalogues sont moins fournis.
        let minimumPresentable = 3
        let langueDemandee = langue
        let cleDemandee = cleCacheMur
        let codeLangue = langueDemandee.lowercased()
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .first.map(String.init) ?? langueDemandee.lowercased()

        // Le cache contient les métadonnées du mur, pas ses pixels. On décode
        // donc d'abord les images hors écran ; le premier frame du mur est
        // déjà entièrement réel, même lorsque URLCache répond très vite.
        let cacheUtilisable = await poserDepuisCache(
            cle: cleDemandee,
            minimum: minimumPresentable,
            limite: besoin
        )
        guard !Task.isCancelled, cleDemandee == cleCacheMur else { return }

        for essai in 0..<3 {
            if Task.isCancelled || cleDemandee != cleCacheMur { return }
            if essai > 0 {
                do {
                    try await Task.sleep(for: .seconds(Double(essai + 1)))
                } catch {
                    return
                }
            }

            // Les deux classements couvrent ensemble les six suggestions
            // localisees de `Decouverte`, sans ajouter une requete brute que
            // certains catalogues prendraient pour un titre litteral.
            async let payants = Decouverte.classement(
                gratuits: false, langue: langueDemandee
            )
            async let libres = Decouverte.classement(
                gratuits: true, langue: langueDemandee
            )
            let lots = await (payants, libres)
            guard !Task.isCancelled else { return }
            let tirage = lots.0 + lots.1
            guard !tirage.isEmpty else { continue }

            var vues = Set<String>()
            let jeu = tirage.shuffled().compactMap { resultat -> Vignette? in
                // Uniquement de vraies couvertures : une case de remplacement
                // au milieu des tendances se verrait tout de suite.
                guard let langueResultat = resultat.langue else { return nil }
                let codeResultat = langueResultat.lowercased()
                    .split(whereSeparator: { $0 == "-" || $0 == "_" })
                    .first.map(String.init) ?? langueResultat.lowercased()
                guard codeResultat == codeLangue,
                      let url = resultat.couvertureURL,
                      vues.insert(url).inserted else { return nil }
                return Vignette(
                    id: resultat.id,
                    url: url,
                    titre: resultat.titreAffiche(langueDemandee),
                    manga: resultat.type != .livre,
                    attribution: resultat.attributionCouverture
                )
            }
            if !jeu.isEmpty {
                let candidat = Array(jeu.prefix(besoin))
                let pret = await precharger(candidat, limite: besoin)
                guard !Task.isCancelled, cleDemandee == cleCacheMur else { return }
                guard pret.vignettes.count >= minimumPresentable else { continue }

                // Un cache déjà affiché reste stable pendant cette ouverture :
                // les nouvelles tendances seront le premier mur du prochain
                // lancement, sans second remplacement visible.
                garder(pret.vignettes, cle: cleDemandee)
                if !cacheUtilisable {
                    poser(pret.vignettes, images: pret.images)
                }
                return
            }
        }
    }

    private func poserDepuisCache(
        cle: String,
        minimum: Int,
        limite: Int
    ) async -> Bool {
        guard let donnees = UserDefaults.standard.data(forKey: cle),
              let jeu = try? JSONDecoder().decode([Vignette].self, from: donnees),
              !jeu.isEmpty
        else { return false }

        let pret = await precharger(jeu, limite: limite)
        guard !Task.isCancelled,
              cle == cleCacheMur,
              pret.vignettes.count >= minimum else {
            return false
        }
        garder(pret.vignettes, cle: cle)
        poser(pret.vignettes, images: pret.images)
        return true
    }

    /// Charge et décode les images avant de rendre une seule case. Les URL en
    /// échec sont retirées : le mur ne passe jamais par le fallback graphique
    /// de `CouvertureView`.
    private func precharger(
        _ jeu: [Vignette],
        limite: Int
    ) async -> (vignettes: [Vignette], images: [String: UIImage]) {
        var vues = Set<String>()
        let urls = Array(jeu.compactMap(\.url).filter {
            !$0.isEmpty && vues.insert($0).inserted
        }.prefix(limite))
        guard !urls.isEmpty else { return ([], [:]) }

        let images = await withTaskGroup(
            of: (String?, UIImage?).self,
            returning: [String: UIImage].self
        ) { groupe in
            for url in urls {
                groupe.addTask {
                    guard !Task.isCancelled else { return (url, nil) }
                    let image = await ImageCharge.partage.uiImage(
                        depuis: url, cote: 700
                    )
                    guard !Task.isCancelled else { return (url, nil) }
                    return (url, image)
                }
            }
            // Une image distante muette ne doit pas retenir les autres hors
            // écran pendant le délai de 60 s de URLSession.shared.
            // Après six secondes, on compose avec les vraies images déjà
            // décodées et on annule proprement le reste.
            groupe.addTask {
                try? await Task.sleep(for: .seconds(6))
                return (nil, nil)
            }

            var chargees: [String: UIImage] = [:]
            var restantes = urls.count
            for await (url, image) in groupe {
                guard let url else {
                    groupe.cancelAll()
                    break
                }
                restantes -= 1
                if let image {
                    chargees[url] = image
                }
                if restantes == 0 {
                    groupe.cancelAll()
                    break
                }
            }
            return chargees
        }
        guard !Task.isCancelled else { return ([], [:]) }

        let pretes = Array(jeu.filter { vignette in
            vignette.url.map { images[$0] != nil } == true
        }.prefix(limite))
        return (pretes, images)
    }

    private func garder(_ jeu: [Vignette], cle: String) {
        if let donnees = try? JSONEncoder().encode(jeu) {
            UserDefaults.standard.set(donnees, forKey: cle)
        }
    }

    /// Pose métadonnées ET pixels dans la même transaction, sans fondu. Une
    /// case du mur n'existe donc jamais avant sa vraie image.
    private func poser(_ jeu: [Vignette], images: [String: UIImage]) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            imagesMur = images
            vignettes = jeu
            if !jeu.isEmpty { debutMur = Date() }
        }
    }

    // MARK: - Actions

    private func traiterApple(_ resultat: Result<ASAuthorization, Error>) {
        switch resultat {
        case .success(let autorisation):
            guard let identite = autorisation.credential as? ASAuthorizationAppleIDCredential
            else { return }
            Task { @MainActor in
                do {
                    try await compte.connecterAvecApple(identite)
                } catch {
                    self.erreur = error.localizedDescription
                }
            }
        case .failure(let souci):
            // Une annulation n'est pas une erreur : on ne dit rien.
            let code = (souci as? ASAuthorizationError)?.code
            if code != .canceled && code != .unknown {
                erreur = String(localized: "La connexion n'a pas abouti. Réessayez dans un instant.")
            }
        }
    }

    private func renvoyerLaConfirmation() async {
        fermerLeClavier()
        erreur = nil
        information = nil
        enCours = true
        defer { enCours = false }
        do {
            try await compte.renvoyerConfirmation(
                email: email.trimmingCharacters(in: .whitespaces)
            )
            confirmationAttendue = false
            information = String(localized: "Un nouveau courrier de confirmation vient de partir.")
        } catch {
            erreur = error.localizedDescription
        }
    }

    private func valider() async {
        fermerLeClavier()
        erreur = nil
        information = nil
        confirmationAttendue = false
        enCours = true
        defer { enCours = false }

        let adresse = email.trimmingCharacters(in: .whitespaces)
        do {
            if mode == .inscription {
                if let attente = try await compte.inscrire(email: adresse, motDePasse: motDePasse) {
                    information = attente
                    // Le courrier vient de partir, mais il peut se perdre :
                    // la porte de renvoi reste ouverte tout de suite.
                    confirmationAttendue = true
                    mode = .connexion
                }
            } else {
                try await compte.connecter(email: adresse, motDePasse: motDePasse)
            }
        } catch SupabaseAuth.Souci.adresseNonConfirmee {
            erreur = SupabaseAuth.Souci.adresseNonConfirmee.errorDescription
            confirmationAttendue = true
        } catch {
            erreur = error.localizedDescription
        }
    }

    private func envoyerReinitialisation() async {
        let adresse = email.trimmingCharacters(in: .whitespaces)
        guard !adresse.isEmpty else { return }
        fermerLeClavier()
        erreur = nil
        enCours = true
        defer { enCours = false }
        do {
            try await compte.envoyerReinitialisation(email: adresse)
            withAnimation(.snappy(duration: 0.25)) { marche = .oubliCode }
            information = String(localized: "Un courrier vient de partir vers \(adresse).")
        } catch {
            erreur = error.localizedDescription
        }
    }

    private func validerLeCode() async {
        fermerLeClavier()
        erreur = nil
        information = nil
        enCours = true
        defer { enCours = false }
        do {
            try await compte.verifierCode(
                email: email.trimmingCharacters(in: .whitespaces),
                code: code.trimmingCharacters(in: .whitespaces)
            )
            withAnimation(.snappy(duration: 0.25)) { marche = .oubliNouveau }
        } catch {
            erreur = error.localizedDescription
        }
    }

    private func terminerReinitialisation() async {
        fermerLeClavier()
        erreur = nil
        information = nil
        enCours = true
        defer { enCours = false }
        do {
            try await compte.poserNouveauMotDePasse(
                nouveauMotDePasse,
                email: email.trimmingCharacters(in: .whitespaces)
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

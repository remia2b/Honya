import AuthenticationServices
import SwiftUI

/// La toute première page : une étagère qui s'ouvre, le nom en serif, et deux
/// chemins pour entrer — l'identifiant Apple, ou une adresse e-mail. Même
/// grammaire visuelle que le reste de l'app.
struct BienvenueView: View {
    @Environment(\.colorScheme) private var apparence
    @State private var compte = Compte.partage
    @State private var mode: Mode = .inscription
    @State private var parEmail = false
    @State private var apparu = false

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

    var body: some View {
        ZStack {
            fond.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    if !parEmail {
                        etagere.padding(.bottom, 30)
                    }

                    VStack(spacing: 9) {
                        Text("Honya")
                            .font(.system(size: parEmail ? 34 : 46, weight: .semibold, design: .serif))
                        Text(parEmail ? sousTitreEmail : "Votre bibliothèque, tome après tome.")
                            .font(parEmail ? .subheadline : .title3)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, parEmail ? 24 : 0)

                    if parEmail {
                        formulaire
                            .padding(.horizontal, 28)
                            .padding(.top, 26)
                    } else {
                        arguments
                            .padding(.horizontal, 34)
                            .padding(.top, 30)
                    }

                    actions
                        .padding(.horizontal, 28)
                        .padding(.top, 26)
                        .padding(.bottom, 24)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, parEmail ? 8 : 20)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
        }
        .animation(.snappy(duration: 0.3), value: parEmail)
        .onAppear { withAnimation(.spring(duration: 0.9)) { apparu = true } }
    }

    private var sousTitreEmail: String {
        mode == .inscription
            ? String(localized: "Créez votre compte avec une adresse e-mail.")
            : String(localized: "Content de vous revoir.")
    }

    // MARK: - Le fond, chaud comme une lampe de chevet

    private var fond: some View {
        ZStack {
            Color(uiColor: .systemBackground)
            RadialGradient(
                colors: [Couleurs.accent.opacity(apparence == .dark ? 0.26 : 0.18), .clear],
                center: .init(x: 0.5, y: 0.16),
                startRadius: 20,
                endRadius: 520
            )
        }
    }

    // MARK: - L'étagère qui accueille

    private var etagere: some View {
        HStack(alignment: .bottom, spacing: -26) {
            couverture(index: 0, largeur: 92, angle: -11, hauteur: 10)
            couverture(index: 1, largeur: 112, angle: -4, hauteur: -6)
            couverture(index: 2, largeur: 128, angle: 3, hauteur: -16)
            couverture(index: 3, largeur: 112, angle: 9, hauteur: -4)
            couverture(index: 4, largeur: 92, angle: 15, hauteur: 12)
        }
        .padding(.top, 22)
    }

    private static let teintes: [(Color, Color)] = [
        (Color(red: 0.85, green: 0.44, blue: 0.30), Color(red: 0.66, green: 0.26, blue: 0.18)),
        (Color(red: 0.33, green: 0.45, blue: 0.62), Color(red: 0.18, green: 0.27, blue: 0.42)),
        (Color(red: 0.93, green: 0.66, blue: 0.28), Color(red: 0.78, green: 0.44, blue: 0.14)),
        (Color(red: 0.42, green: 0.56, blue: 0.44), Color(red: 0.23, green: 0.35, blue: 0.27)),
        (Color(red: 0.62, green: 0.42, blue: 0.66), Color(red: 0.40, green: 0.24, blue: 0.46)),
    ]

    private func couverture(index: Int, largeur: CGFloat, angle: Double, hauteur: CGFloat) -> some View {
        let teinte = Self.teintes[index % Self.teintes.count]
        return RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [teinte.0, teinte.1],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            .frame(width: largeur, height: largeur * 1.5)
            .overlay(alignment: .leading) {
                // La gorge de reliure, comme sur les couvertures de l'app.
                HStack(spacing: 0) {
                    Rectangle().fill(.black.opacity(0.26)).frame(width: 2.5)
                    Rectangle().fill(.white.opacity(0.22)).frame(width: 1)
                    Rectangle()
                        .fill(LinearGradient(
                            colors: [.black.opacity(0.22), .clear],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(width: 8)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(LinearGradient(
                        colors: [.white.opacity(0.16), .clear],
                        startPoint: .top, endPoint: .bottom
                    ))
            )
            .shadow(color: .black.opacity(0.4), radius: 16, y: 10)
            .rotationEffect(.degrees(apparu ? angle : 0))
            .offset(y: apparu ? hauteur : 40)
            .opacity(apparu ? 1 : 0)
            .animation(.spring(duration: 0.85).delay(Double(index) * 0.07), value: apparu)
    }

    // MARK: - Ce que le compte apporte

    private var arguments: some View {
        VStack(alignment: .leading, spacing: 16) {
            argument(
                "books.vertical.fill",
                "Tous vos tomes, à jour",
                "Ajoutez un tome, la série entière apparaît — dates de sortie comprises."
            )
            argument(
                "globe",
                "Dans votre langue",
                "Titres, couvertures et résumés dans l'édition de votre pays."
            )
            argument(
                "lock.fill",
                "Vos lectures vous appartiennent",
                "Rien n'est partagé, et votre compte s'efface d'un bouton."
            )
        }
    }

    private func argument(
        _ symbole: String,
        _ titre: LocalizedStringKey,
        _ detail: LocalizedStringKey
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbole)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Couleurs.accent)
                .frame(width: 28, height: 28)
                .background(Couleurs.accent.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(titre)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Le formulaire e-mail

    private var formulaire: some View {
        VStack(spacing: 12) {
            champ(
                "Adresse e-mail",
                systemImage: "envelope",
                texte: $email,
                champ: .email
            )
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
        _ invite: String,
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

    // MARK: - Les chemins d'entrée

    private var actions: some View {
        VStack(spacing: 14) {
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

            if !parEmail {
                SignInWithAppleButton(
                    mode == .inscription ? .signUp : .signIn,
                    onRequest: { requete in
                        compte.preparerDemandeApple(requete)
                    },
                    onCompletion: { resultat in
                        traiterApple(resultat)
                    }
                )
                .signInWithAppleButtonStyle(apparence == .dark ? .white : .black)
                .frame(height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            Button {
                erreur = nil
                information = nil
                parEmail.toggle()
            } label: {
                Label(
                    parEmail ? "Utiliser mon identifiant Apple" : "Utiliser une adresse e-mail",
                    systemImage: parEmail ? "apple.logo" : "envelope"
                )
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    Color(uiColor: .secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
            }
            .buttonStyle(.plain)

            if let information {
                message(information, couleur: Couleurs.lu)
            }
            if let erreur {
                message(erreur, couleur: .red)
            }

            Button("Continuer sans compte") {
                compte.continuerSansCompte()
            }
            .font(.subheadline.weight(.semibold))
            .tint(.secondary)
            .padding(.top, 2)

            Text("Vos lectures restent sur votre appareil. Vous pouvez supprimer votre compte à tout moment depuis les réglages.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
    }

    private func message(_ texte: String, couleur: Color) -> some View {
        Text(texte)
            .font(.caption)
            .foregroundStyle(couleur)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
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
                erreur = "La connexion n'a pas abouti. Réessayez dans un instant."
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
            erreur = "Saisissez d'abord votre adresse e-mail."
            return
        }
        erreur = nil
        do {
            try await compte.envoyerReinitialisation(email: adresse)
            information = "Un courrier vient de partir vers \(adresse)."
        } catch {
            erreur = error.localizedDescription
        }
    }
}

#Preview {
    BienvenueView()
}

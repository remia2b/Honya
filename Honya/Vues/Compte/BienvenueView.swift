import AuthenticationServices
import SwiftUI

/// La toute première page : une étagère qui s'ouvre, le nom en serif, et deux
/// chemins — créer son compte ou se connecter. Même grammaire visuelle que le
/// reste de l'app : grandes couvertures, ombres douces, typographie serif.
struct BienvenueView: View {
    @Environment(\.colorScheme) private var apparence
    @State private var compte = Compte.partage
    @State private var mode: Mode = .inscription
    @State private var erreur: String?
    @State private var apparu = false

    enum Mode: String, CaseIterable, Identifiable {
        case inscription = "Créer un compte"
        case connexion = "Se connecter"

        var id: String { rawValue }
    }

    var body: some View {
        ZStack {
            fond.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 12)

                etagere
                    .padding(.bottom, 34)

                VStack(spacing: 10) {
                    Text("Honya")
                        .font(.system(size: 46, weight: .semibold, design: .serif))
                    Text("Votre bibliothèque, tome après tome.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)

                Spacer(minLength: 24)

                arguments
                    .padding(.horizontal, 34)

                Spacer(minLength: 24)

                actions
                    .padding(.horizontal, 28)
                    .padding(.bottom, 18)
            }
        }
        .onAppear {
            withAnimation(.spring(duration: 0.9)) { apparu = true }
        }
    }

    // MARK: - Le fond, chaud comme une lampe de chevet

    private var fond: some View {
        ZStack {
            Color(uiColor: .systemBackground)
            RadialGradient(
                colors: [Couleurs.accent.opacity(apparence == .dark ? 0.26 : 0.18), .clear],
                center: .init(x: 0.5, y: 0.18),
                startRadius: 20,
                endRadius: 520
            )
        }
    }

    // MARK: - L'étagère qui accueille

    private var etagere: some View {
        HStack(alignment: .bottom, spacing: -26) {
            couverture(index: 0, largeur: 96, angle: -11, hauteur: 10)
            couverture(index: 1, largeur: 116, angle: -4, hauteur: -6)
            couverture(index: 2, largeur: 132, angle: 3, hauteur: -16)
            couverture(index: 3, largeur: 116, angle: 9, hauteur: -4)
            couverture(index: 4, largeur: 96, angle: 15, hauteur: 12)
        }
        .padding(.top, 26)
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
            .animation(
                .spring(duration: 0.85).delay(Double(index) * 0.07),
                value: apparu
            )
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
                "Rien n'est partagé. Votre nom et votre adresse restent sur l'appareil."
            )
        }
    }

    private func argument(_ symbole: String, _ titre: String, _ detail: String) -> some View {
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

    // MARK: - Créer un compte ou se connecter

    private var actions: some View {
        VStack(spacing: 14) {
            Picker("", selection: $mode) {
                ForEach(Mode.allCases) { cas in
                    Text(cas.rawValue).tag(cas)
                }
            }
            .pickerStyle(.segmented)

            SignInWithAppleButton(
                mode == .inscription ? .signUp : .signIn,
                onRequest: { requete in
                    requete.requestedScopes = [.fullName, .email]
                },
                onCompletion: { resultat in
                    switch resultat {
                    case .success(let autorisation):
                        if let identite = autorisation.credential as? ASAuthorizationAppleIDCredential {
                            compte.connecter(identite)
                        }
                    case .failure(let souci):
                        // Une annulation n'est pas une erreur : on ne dit rien.
                        let code = (souci as? ASAuthorizationError)?.code
                        if code != .canceled && code != .unknown {
                            erreur = "La connexion n'a pas abouti. Réessayez dans un instant."
                        }
                    }
                }
            )
            .signInWithAppleButtonStyle(apparence == .dark ? .white : .black)
            .frame(height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            if let erreur {
                Text(erreur)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button("Continuer sans compte") {
                compte.continuerSansCompte()
            }
            .font(.subheadline.weight(.semibold))
            .tint(.secondary)

            Text("Un compte Honya, c'est votre identifiant Apple : aucun mot de passe à créer, et vous pouvez le supprimer à tout moment depuis les réglages.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
    }
}

#Preview {
    BienvenueView()
}

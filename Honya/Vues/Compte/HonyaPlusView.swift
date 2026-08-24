import SwiftData
import SwiftUI

/// L'écran Honya+, sous deux formes selon d'où il vient.
///
/// Avec un `Verrou`, il montre la chose exacte qui manque, avec les livres
/// concernés, et une seule offre : une seule décision à prendre. Sans verrou —
/// depuis les réglages — il déroule tout, avec les trois tarifs.
///
/// Refuser mène à la roue, une fois par personne.
struct HonyaPlusView: View {
    var verrou: Verrou?

    @Environment(\.dismiss) private var dismiss
    @Query private var oeuvres: [Oeuvre]

    @State private var droits = Droits.partage
    @State private var toutVoir = false
    @State private var roueVisible = false
    @State private var apparu = false
    /// De quoi garnir le rayon quand la bibliothèque est encore vide.
    @State private var tendances: [String] = []

    private var contextuel: Bool { verrou != nil && !toutVoir }

    var body: some View {
        ZStack {
            fond.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    if contextuel, let verrou {
                        enTeteContexte(verrou)
                    } else {
                        enTeteListe
                    }

                    if !contextuel {
                        avantages
                    }

                    offres
                }
                .padding(.bottom, 20)
            }
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaInset(edge: .bottom) { bouton }

            fermer
        }
        .animation(.snappy(duration: 0.3), value: toutVoir)
        .onAppear { withAnimation(.easeOut(duration: 0.55)) { apparu = true } }
        .task {
            guard oeuvres.isEmpty else { return }
            let top = await Decouverte.classement(gratuits: false, langue: Langues.codeAppareil)
            tendances = top.compactMap(\.couvertureURL)
        }
        .fullScreenCover(isPresented: $roueVisible) {
            RoueSheet { dismiss() }
        }
    }

    /// Une lueur chaude qui descend vers le fond du système : le noir plein
    /// donnait à l'écran de vente un air de boîte de dialogue.
    private var fond: some View {
        ZStack {
            Color(uiColor: .systemBackground)
            LinearGradient(
                colors: [
                    Couleurs.accent.opacity(0.22),
                    Couleurs.accent.opacity(0.05),
                    .clear,
                ],
                startPoint: .top, endPoint: .center
            )
            RadialGradient(
                colors: [Couleurs.accent.opacity(0.16), .clear],
                center: .init(x: 0.5, y: 0.34),
                startRadius: 10, endRadius: 340
            )
        }
    }

    // MARK: - En-tête contextuel : les livres concernés

    private func enTeteContexte(_ verrou: Verrou) -> some View {
        VStack(spacing: 0) {
            eventail(verrou)
                .padding(.top, 40)
                .padding(.bottom, 30)

            Text(verrou.titre)
                .font(.system(size: 30, weight: .semibold, design: .serif))
                .multilineTextAlignment(.center)
            Text(verrou.detail)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 10)
        }
        .padding(.horizontal, 30)
        .padding(.bottom, 26)
    }

    /// Trois couvertures en éventail, avec le cadenas posé dessus. Faute de
    /// couvertures, le symbole du verrou suffit.
    private func eventail(_ verrou: Verrou) -> some View {
        let couvertures = Array(verrou.couvertures.prefix(3))
        return ZStack {
            if couvertures.isEmpty {
                Image(systemName: verrou.symbole)
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(Couleurs.accent)
                    .frame(height: 180)
            } else {
                ForEach(Array(couvertures.enumerated()), id: \.offset) { rang, url in
                    let ecart = Double(rang) - Double(couvertures.count - 1) / 2
                    CouvertureView(urlString: url, titre: "", coins: 7, cote: 400)
                        .frame(width: 116, height: 174)
                        .shadow(color: .black.opacity(0.28), radius: 14, y: 8)
                        .rotationEffect(.degrees(ecart * 8))
                        .offset(x: ecart * 74, y: abs(ecart) * 10)
                        .zIndex(ecart == 0 ? 2 : 1)
                        .scaleEffect(apparu ? 1 : 0.9)
                        .opacity(apparu ? 1 : 0)
                        .animation(
                            .spring(duration: 0.6).delay(Double(rang) * 0.06),
                            value: apparu
                        )
                }
            }

            Image(systemName: "lock.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(Couleurs.accent, in: Circle())
                .shadow(color: Couleurs.accent.opacity(0.5), radius: 12, y: 4)
                .zIndex(3)
                .scaleEffect(apparu ? 1 : 0.4)
                .animation(.spring(duration: 0.5).delay(0.24), value: apparu)
        }
        .frame(height: 190)
    }

    // MARK: - En-tête complet : le rayon et la promesse

    private var enTeteListe: some View {
        VStack(alignment: .leading, spacing: 0) {
            rayon
                .frame(height: 128)
                .clipped()
                .padding(.bottom, 22)

            HStack(spacing: 0) {
                Text(verbatim: "Honya")
                    .font(.system(size: 38, weight: .semibold, design: .serif))
                Text(verbatim: "+")
                    .font(.system(size: 38, weight: .semibold, design: .serif))
                    .foregroundStyle(Couleurs.accent)
            }
            Text("Le libraire qui range à votre place.")
                .font(.system(size: 22, design: .serif))
                .foregroundStyle(.secondary)
                .padding(.top, 6)
        }
        .padding(.horizontal, 28)
        .padding(.top, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Les couvertures du lecteur si sa bibliothèque en a, sinon rien : mieux
    /// vaut pas de rayon qu'un rayon de cases vides.
    private var rayon: some View {
        let siennes = oeuvres.compactMap(\.couvertureAffichee).shuffled()
        let urls = Array((siennes.isEmpty ? tendances : siennes).prefix(7))
        // Une pile horizontale de sept couvertures mesure plus de 600 points :
        // sa largeur intrinsèque emportait tout l'écran vers la gauche. Le
        // défilement horizontal, lui, se contente de la place offerte.
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(urls.enumerated()), id: \.offset) { rang, url in
                    CouvertureView(urlString: url, titre: "", coins: 5, cote: 400)
                        .frame(width: 82, height: 123)
                        .offset(y: Double(rang) * 6)
                }
            }
            .padding(.leading, 14)
        }
        .scrollDisabled(true)
        .rotationEffect(.degrees(-4))
        .opacity(apparu ? 1 : 0)
        .animation(.easeOut(duration: 0.7), value: apparu)
    }

    // MARK: - Les avantages

    private var avantages: some View {
        VStack(alignment: .leading, spacing: 17) {
            avantage("books.vertical.fill", "Séries automatiques sans limite",
                     "un tome ajouté, tout le rayon apparaît")
            avantage("bell.badge.fill", "Alertes à chaque nouveau tome",
                     "sur toutes vos séries, pas une seule")
            avantage("barcode.viewfinder", "Scan illimité, étagères entières",
                     "une rangée de codes-barres à la volée")
            avantage("chart.bar.fill", "Tout votre historique de lecture",
                     "records, heatmap de l'année, humeurs")
            avantage("heart.fill", "Prêts, citations et étagères",
                     "sans compteur qui vous arrête")
        }
        .padding(.horizontal, 28)
        .padding(.top, 26)
    }

    private func avantage(
        _ symbole: String, _ titre: LocalizedStringKey, _ detail: LocalizedStringKey
    ) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: symbole)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Couleurs.accent)
                .frame(width: 26, height: 26)
                .background(Couleurs.accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(titre).font(.system(size: 15.5, weight: .semibold))
                Text(detail).font(.system(size: 13.5)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Les tarifs

    private var offres: some View {
        VStack(spacing: 9) {
            if contextuel {
                tarif("Honya+ annuel", "7 jours offerts, puis 2,50 €/mois",
                      "29,99 €", choisi: true)
            } else {
                tarif("Mensuel", "sans engagement", "4,99 €", choisi: false)
                tarif("Annuel", "2,50 € par mois", "29,99 €",
                      choisi: true, ruban: "7 jours offerts")
                tarif("À vie", "une seule fois", "69,99 €", choisi: false)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
    }

    private func tarif(
        _ nom: LocalizedStringKey, _ detail: LocalizedStringKey,
        _ prix: String, choisi: Bool, ruban: LocalizedStringKey? = nil
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(nom).font(.system(size: 16, weight: .semibold))
                Text(detail).font(.system(size: 12.5)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(prix).font(.system(size: 19, weight: .semibold, design: .serif))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(choisi ? Couleurs.accent.opacity(0.07) : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    choisi ? Couleurs.accent : Color.primary.opacity(0.13),
                    lineWidth: choisi ? 2 : 1.5
                )
        )
        .overlay(alignment: .topLeading) {
            if let ruban {
                Text(ruban)
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Couleurs.accent, in: Capsule())
                    .offset(x: 14, y: -9)
            }
        }
    }

    // MARK: - Le bas

    private var bouton: some View {
        VStack(spacing: 0) {
            Button {
                // Pendant TestFlight : déblocage local, sans achat.
                droits.activerEssai()
                dismiss()
            } label: {
                Text("Essayer 7 jours gratuitement")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .foregroundStyle(.white)
                    .background(Couleurs.accent, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
            .buttonStyle(.plain)

            if contextuel {
                Button("Voir toutes les offres") { toutVoir = true }
                    .font(.system(size: 14.5, weight: .semibold))
                    .padding(.top, 13)
            }

            Text("Puis 29,99 €/an. Résiliable à tout moment.")
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
                .padding(.top, 11)
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 14)
        .background(.thinMaterial)
    }

    private var fermer: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    // Refuser mène à la roue, une fois par personne.
                    if RoueSheet.disponible {
                        roueVisible = true
                    } else {
                        dismiss()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(Color.primary.opacity(0.07), in: Circle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }
}

#Preview("Contexte") {
    HonyaPlusView(verrou: .serie(nom: "Chainsaw Man", tomes: 27, couvertures: []))
        .modelContainer(Apercu.conteneur)
}

#Preview("Liste") {
    HonyaPlusView()
        .modelContainer(Apercu.conteneur)
}

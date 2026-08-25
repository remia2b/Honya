import SwiftData
import SwiftUI

/// L'écran Honya+, sous deux formes selon d'où il vient.
///
/// Avec un `Verrou`, il montre la chose exacte qui manque, avec les livres
/// concernés, et une seule offre : une seule décision à prendre. Sans verrou —
/// depuis les réglages — il déroule tout, avec les trois tarifs.
///
/// Fermer l'écran propose la roue promotionnelle, une fois par personne.
struct HonyaPlusView: View {
    var verrou: Verrou?

    @Environment(\.dismiss) private var dismiss
    @Query private var oeuvres: [Oeuvre]

    @State private var droits = Droits.partage
    @State private var boutique = Boutique.partage
    @State private var formuleChoisie: Boutique.Formule?
    @State private var toutVoir = false
    @State private var roueVisible = false
    @State private var apparu = false
    /// De quoi garnir le rayon quand la bibliothèque est encore vide.
    @State private var tendances: [String] = []

    private var contextuel: Bool { verrou != nil && !toutVoir }

    var body: some View {
        ZStack {
            fond.ignoresSafeArea()

            GeometryReader { geo in
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
                    // Centré tant que ça tient : l'écran contextuel, plus
                    // court, laissait sinon un vide sous son tarif.
                    .frame(maxWidth: .infinity, minHeight: contextuel ? geo.size.height - 60 : 0)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .safeAreaInset(edge: .bottom) { bouton }

            fermer
        }
        .animation(.snappy(duration: 0.3), value: toutVoir)
        .onAppear { withAnimation(.easeOut(duration: 0.55)) { apparu = true } }
        .task {
            // Le catalogue a pu être chargé au lancement ; on redemande si le
            // réseau manquait alors.
            if boutique.articles.isEmpty { await boutique.charger() }
            formuleChoisie = formuleParDefaut
        }
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
            // Le bandeau va d'un bord à l'autre pour que la rangée déborde à
            // droite ; seul le texte est en retrait.
            rayon
                .frame(height: 114)
                .padding(.bottom, 16)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    Text(verbatim: "Honya")
                        .font(.system(size: 34, weight: .semibold, design: .serif))
                    Text(verbatim: "+")
                        .font(.system(size: 34, weight: .semibold, design: .serif))
                        .foregroundStyle(Couleurs.accent)
                }
                Text("Le libraire qui range à votre place.")
                    .font(.system(size: 19, design: .serif))
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            }
            .padding(.horizontal, 28)
        }
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
        // Ni escalier ni inclinaison : les deux rognaient le bas des
        // couvertures contre la hauteur du bandeau. Une rangée nette, qui
        // déborde seulement à droite — une étagère qui continue.
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(urls.enumerated()), id: \.offset) { _, url in
                    CouvertureView(urlString: url, titre: "", coins: 5, cote: 400)
                        .frame(width: 76, height: 114)
                }
            }
            .padding(.leading, 28)
        }
        .scrollDisabled(true)
        .opacity(apparu ? 1 : 0)
        .animation(.easeOut(duration: 0.7), value: apparu)
    }

    // MARK: - Les avantages

    private var avantages: some View {
        VStack(alignment: .leading, spacing: 13) {
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
        .padding(.top, 20)
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
                Text(detail).font(.system(size: 13)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Les tarifs

    /// Ce que l'on met en avant : l'annuel, remisé si la roue l'a accordé.
    private var formuleParDefaut: Boutique.Formule {
        boutique.formulesVisibles.contains(.annuelRemise) ? .annuelRemise : .annuel
    }

    /// En contextuel, une seule décision à prendre — donc une seule offre.
    private var formulesAffichees: [Boutique.Formule] {
        contextuel ? [formuleParDefaut] : boutique.formulesVisibles
    }

    private var offres: some View {
        VStack(spacing: 9) {
            ForEach(formulesAffichees) { formule in
                Button { formuleChoisie = formule } label: { tarif(formule) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }

    /// La mensualité d'un abonnement annuel, calculée depuis le prix réel et
    /// jamais recopiée : dans une autre monnaie, un montant recopié serait faux.
    private func detail(_ formule: Boutique.Formule) -> String {
        if let article = boutique.articles[formule],
           let abonnement = article.subscription,
           abonnement.subscriptionPeriod.unit == .year {
            let parMois = (article.price / 12).formatted(article.priceFormatStyle)
            return String(localized: "\(parMois) par mois")
        }
        return formule.detail
    }

    /// Le ruban ne promet des jours offerts que si l'App Store en propose
    /// vraiment : une promesse d'essai non tenue fait refuser l'application.
    private func ruban(_ formule: Boutique.Formule) -> String? {
        guard let article = boutique.articles[formule] else {
            return formule == .annuel ? String(localized: "7 jours offerts") : nil
        }
        guard let offre = article.subscription?.introductoryOffer,
              offre.paymentMode == .freeTrial else { return nil }
        let jours = offre.period.value * (offre.period.unit == .week ? 7 : 1)
        return String(localized: "\(jours) jours offerts")
    }

    private func tarif(_ formule: Boutique.Formule) -> some View {
        let choisi = formuleChoisie == formule
        return HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(formule.nom).font(.system(size: 16, weight: .semibold))
                Text(detail(formule)).font(.system(size: 12.5)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(boutique.prix(formule)).font(.system(size: 19, weight: .semibold, design: .serif))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
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
            if let ruban = ruban(formule) {
                Text(ruban)
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Couleurs.accent, in: Capsule())
                    .offset(x: 14, y: -9)
            }
        }
        .animation(.snappy(duration: 0.18), value: choisi)
    }

    // MARK: - Le bas

    /// L'intitulé dit exactement ce qui va être débité : « essayer
    /// gratuitement » sur une formule sans essai est un motif de refus.
    private var intituleAchat: String {
        guard let formule = formuleChoisie else { return String(localized: "Continuer") }
        if ruban(formule) != nil { return String(localized: "Commencer l'essai gratuit") }
        return String(localized: "Continuer pour \(boutique.prix(formule))")
    }

    private var mentionAchat: String {
        guard let formule = formuleChoisie else { return "" }
        if formule == .vie { return String(localized: "Paiement unique, sans renouvellement.") }
        return ruban(formule) != nil
            ? String(localized: "Puis \(boutique.prix(formule)). Résiliable à tout moment.")
            : String(localized: "Renouvelé automatiquement. Résiliable à tout moment.")
    }

    private var bouton: some View {
        VStack(spacing: 0) {
            Button {
                Task { await acheter() }
            } label: {
                HStack(spacing: 8) {
                    if boutique.achatEnCours != nil { ProgressView().tint(.white) }
                    Text(intituleAchat)
                        .font(.system(size: 17, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .foregroundStyle(.white)
                .background(Couleurs.accent, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(boutique.achatEnCours != nil || formuleChoisie == nil)
            .opacity(boutique.achatEnCours != nil ? 0.6 : 1)

            if let souci = boutique.souci {
                Text(souci)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.top, 9)
            }

            if contextuel {
                Button("Voir toutes les offres") { toutVoir = true }
                    .font(.system(size: 14.5, weight: .semibold))
                    .padding(.top, 13)
            }

            Text(mentionAchat)
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.top, 11)

            // Obligatoire : l'App Store refuse une application qui vend un
            // abonnement sans permettre de le retrouver sur un autre appareil.
            Button("Restaurer mes achats") {
                Task {
                    await boutique.restaurer()
                    if boutique.abonne { dismiss() }
                }
            }
            .font(.system(size: 12.5))
            .tint(.secondary)
            .padding(.top, 7)
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 14)
        .background(.thinMaterial)
    }

    private func acheter() async {
        guard let formule = formuleChoisie else { return }
        // Tant que les articles n'existent pas côté Apple, la version de test
        // débloque localement plutôt que de laisser un bouton sans effet.
        guard boutique.articles[formule] != nil else {
            droits.activerEssai()
            dismiss()
            return
        }
        if await boutique.acheter(formule) { dismiss() }
    }

    private var fermer: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    if RoueSheet.disponible {
                        roueVisible = true
                    } else {
                        dismiss()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        // Un fond translucide plutôt qu'une teinte : la croix
                        // se posait sur les couvertures et s'y perdait.
                        .background(.regularMaterial, in: Circle())
                        .shadow(color: .black.opacity(0.14), radius: 5, y: 2)
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

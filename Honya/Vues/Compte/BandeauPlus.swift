import SwiftUI

/// L'invitation à Honya+, posée dans le fil de l'accueil.
///
/// Sans elle, un lecteur qui ne bute sur aucun verrou traverse l'application
/// sans jamais savoir qu'un abonnement existe — et la croit entièrement
/// gratuite. Elle disparaît d'elle-même une fois l'abonnement pris.
struct BandeauPlus: View {
    var verrou: Verrou?

    @State private var droits = Droits.partage
    @State private var visible = false

    var body: some View {
        if !droits.plus {
            Button { visible = true } label: {
                HStack(spacing: 14) {
                    Image(systemName: "books.vertical.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(
                            LinearGradient(
                                colors: [Couleurs.accent, Couleurs.accent.opacity(0.72)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Passez à Honya+")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("Un tome ajouté, tout le rayon se pose.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Couleurs.accent.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Couleurs.accent.opacity(0.25), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .ecranHonyaPlus($visible, verrou: verrou)
        }
    }
}

// MARK: - Le cadenas posé sur une fonction payante

/// Une fonction qu'on voit sans pouvoir s'en servir.
///
/// On ne cache jamais ce qu'on vend : la fonction reste visible, à sa place,
/// avec un cadenas qui dit comment l'ouvrir. Cacher revient à faire croire
/// que l'application ne sait pas le faire.
struct CadenasPlus: View {
    var verrou: Verrou?
    var compact = false

    @State private var droits = Droits.partage
    @State private var visible = false

    var body: some View {
        if !droits.plus {
            Button { visible = true } label: {
                HStack(spacing: 5) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: compact ? 9 : 10, weight: .bold))
                    if !compact {
                        Text(verbatim: "Honya+")
                            .font(.system(size: 11, weight: .bold))
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, compact ? 6 : 8)
                .padding(.vertical, compact ? 4 : 5)
                .background(Couleurs.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .ecranHonyaPlus($visible, verrou: verrou)
        }
    }
}

/// Un cadenas purement décoratif, posé sur une commande qui reste
/// tappable — c'est elle qui ouvre Honya+, pas le cadenas.
///
/// `CadenasPlus` est lui-même un bouton : posé sur une commande, il lui
/// volerait le doigt. Celui-ci ne se laisse pas toucher.
struct BadgeCadenas: View {
    var actif: Bool

    var body: some View {
        if actif {
            Image(systemName: "lock.fill")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white)
                .padding(3)
                .background(Couleurs.accent, in: Circle())
                .allowsHitTesting(false)
        }
    }
}

/// Un intitulé de menu qui annonce qu'il mène à Honya+.
///
/// Dans un menu, aucune pastille ne peut se poser par-dessus : le cadenas se
/// glisse donc dans le texte. On ne retire jamais l'entrée — une fonction
/// cachée donne l'impression que l'application ne sait pas la faire.
struct LabelPlus: View {
    var titre: LocalizedStringKey
    var symbole: String

    @State private var droits = Droits.partage

    var body: some View {
        Label {
            HStack(spacing: 5) {
                Text(titre)
                if !droits.plus {
                    Image(systemName: "lock.fill").font(.caption2)
                }
            }
        } icon: {
            Image(systemName: symbole)
        }
    }
}

extension View {
    /// Pose un cadenas décoratif sur une commande verrouillée.
    func badgeCadenas(_ actif: Bool) -> some View {
        overlay(alignment: .topTrailing) {
            BadgeCadenas(actif: actif).offset(x: 6, y: -5)
        }
    }

    /// Pose un cadenas en haut à droite d'une fonction réservée.
    func cadenasPlus(_ verrou: Verrou? = nil, compact: Bool = false) -> some View {
        overlay(alignment: .topTrailing) {
            CadenasPlus(verrou: verrou, compact: compact)
                .offset(x: 6, y: -6)
        }
    }
}

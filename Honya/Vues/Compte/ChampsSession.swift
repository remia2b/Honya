import SwiftUI
import UIKit

// Les champs de l'écran de bienvenue — de vrais UITextField, dans un arbre
// UIKit persistant.
//
// C'est le morceau qui manquait : avec des champs SwiftUI, passer de
// l'e-mail au mot de passe détruit un premier répondant et en crée un autre,
// et iOS rejoue fermeture puis ouverture du clavier — le bref plongeon
// visible à chaque changement de champ. Dans un arbre UIKit persistant, le
// premier répondant se transfère DIRECTEMENT d'un champ à l'autre : le
// clavier ne part jamais. C'est l'architecture validée sur Binjo.

/// Ligne visuelle d'un champ.
///
/// Le décor ne vit volontairement PAS sur le `UITextField` : UIKit rend le
/// texte, le placeholder et le caret dans des couches privées qu'il remplace
/// au passage vers un champ sécurisé. Le décor posé sur le champ lui-même
/// pouvait être capturé à deux positions pendant une image ; ici la ligne
/// reste immobile, le champ natif ne gère que la saisie.
final class RangChamp: UIView {
    let champ = UITextField()
    private let icone = UIImageView()

    init(symbole: String) {
        super.init(frame: .zero)

        layer.cornerRadius = 14
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        clipsToBounds = true

        champ.borderStyle = .none
        champ.backgroundColor = .clear
        champ.font = .systemFont(ofSize: 17)
        champ.contentVerticalAlignment = .center
        champ.autocapitalizationType = .none
        champ.autocorrectionType = .no
        champ.spellCheckingType = .no
        champ.smartQuotesType = .no
        champ.smartDashesType = .no
        champ.smartInsertDeleteType = .no
        champ.clearButtonMode = .never

        let configuration = UIImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        icone.image = UIImage(systemName: symbole, withConfiguration: configuration)
        icone.contentMode = .scaleAspectFit

        addSubview(icone)
        addSubview(champ)
        appliquerCouleurs()

        // Le contour est une CGColor figée : il faut la reprendre quand
        // l'apparence bascule entre clair et sombre.
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) {
            (moi: RangChamp, _) in moi.appliquerCouleurs()
        }

        let toucher = UITapGestureRecognizer(target: self, action: #selector(prendreLeFocus))
        toucher.cancelsTouchesInView = false
        addGestureRecognizer(toucher)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func appliquerCouleurs() {
        backgroundColor = .secondarySystemBackground
        layer.borderColor = UIColor.label
            .resolvedColor(with: traitCollection)
            .withAlphaComponent(0.16)
            .cgColor
        icone.tintColor = .secondaryLabel
        champ.textColor = .label
        champ.tintColor = UIColor(Couleurs.accent)
    }

    @objc private func prendreLeFocus() {
        if !champ.isFirstResponder {
            champ.becomeFirstResponder()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Cadres constants, posés sans animation : la géométrie du champ ne
        // participe jamais aux transferts de premier répondant.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        icone.frame = CGRect(x: 15, y: (bounds.height - 20) / 2, width: 20, height: 20)
        champ.frame = CGRect(x: 46, y: 0, width: max(0, bounds.width - 61), height: bounds.height)
        champ.layoutIfNeeded()
        CATransaction.commit()
    }
}

/// Les quatre champs possibles de l'écran, dans UN SEUL arbre persistant.
///
/// Tous existent en permanence ; la configuration ne fait que montrer ou
/// cacher. Détruire puis recréer un champ, c'est détruire son premier
/// répondant — exactement ce qu'on interdit.
final class ChampsSessionVue: UIView {
    enum Configuration: Equatable {
        case identifiants(inscription: Bool)
        case oubliDemande
        case oubliCode
    }

    static let hauteurRang: CGFloat = 50
    static let ecart: CGFloat = 12

    let rangEmail = RangChamp(symbole: "envelope")
    let rangMotDePasse = RangChamp(symbole: "lock")
    let rangCode = RangChamp(symbole: "number")
    let rangNouveau = RangChamp(symbole: "lock.rotation")

    private(set) var configuration: Configuration = .identifiants(inscription: true)

    var tous: [RangChamp] { [rangEmail, rangMotDePasse, rangCode, rangNouveau] }

    var visibles: [RangChamp] {
        switch configuration {
        case .identifiants: return [rangEmail, rangMotDePasse]
        case .oubliDemande: return [rangEmail]
        case .oubliCode: return [rangEmail, rangCode, rangNouveau]
        }
    }

    var saisieActive: Bool {
        tous.contains { $0.champ.isFirstResponder }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        rangMotDePasse.champ.isSecureTextEntry = true
        rangNouveau.champ.isSecureTextEntry = true
        for rang in tous { addSubview(rang) }

        #if DEBUG
        // Le banc d'essai bascule le focus sans doigt : une notification
        // nomme le champ, la vue transfère le premier répondant — le même
        // chemin exactement qu'un toucher.
        NotificationCenter.default.addObserver(
            forName: Notification.Name("honya.banc.focus"), object: nil, queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self, let nom = notification.userInfo?["champ"] as? String
                else { return }
                let cible: RangChamp
                switch nom {
                case "motDePasse": cible = self.rangMotDePasse
                case "code": cible = self.rangCode
                case "nouveau": cible = self.rangNouveau
                default: cible = self.rangEmail
                }
                journalClavier("banc -> focus \(nom)")
                cible.champ.becomeFirstResponder()
            }
        }
        #endif
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func hauteur(_ configuration: Configuration) -> CGFloat {
        let combien: CGFloat
        switch configuration {
        case .identifiants: combien = 2
        case .oubliDemande: combien = 1
        case .oubliCode: combien = 3
        }
        return combien * hauteurRang + (combien - 1) * ecart
    }

    func appliquer(_ nouvelle: Configuration) {
        guard configuration != nouvelle else { return }
        let focalise = tous.first { $0.champ.isFirstResponder }
        configuration = nouvelle

        for rang in tous { rang.isHidden = !visibles.contains(rang) }

        // Un champ caché ne peut pas garder le clavier : le focus passe à
        // l'e-mail — présent dans toutes les configurations — par transfert
        // direct, sans fermeture du clavier.
        if let focalise, focalise.isHidden {
            rangEmail.champ.becomeFirstResponder()
        }

        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: Self.hauteur(configuration))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (rangee, rang) in visibles.enumerated() {
            rang.frame = CGRect(
                x: 0,
                y: CGFloat(rangee) * (Self.hauteurRang + Self.ecart),
                width: bounds.width,
                height: Self.hauteurRang
            )
            rang.layoutIfNeeded()
        }
        CATransaction.commit()
    }
}

/// Le pont SwiftUI : la vue persistante, ses liaisons, et la session.
struct ChampsSession: UIViewRepresentable {
    let configuration: ChampsSessionVue.Configuration
    @Binding var email: String
    @Binding var motDePasse: String
    @Binding var code: String
    @Binding var nouveau: String
    let session: SessionClavier
    let surValidation: () -> Void

    func makeCoordinator() -> Coordinateur {
        Coordinateur(self)
    }

    func makeUIView(context: Context) -> ChampsSessionVue {
        let vue = ChampsSessionVue(frame: .zero)
        context.coordinator.vue = vue

        for rang in vue.tous {
            rang.champ.delegate = context.coordinator
            rang.champ.addTarget(
                context.coordinator,
                action: #selector(Coordinateur.texteChange(_:)),
                for: .editingChanged
            )
        }

        // La session sait fermer la saisie et lire l'état réel du focus
        // sans connaître les champs : deux poignées, posées ici.
        session.terminerLaSaisie = { [weak vue] in vue?.endEditing(true) ?? false }
        session.saisieEncoreActive = { [weak vue] in vue?.saisieActive ?? false }

        appliquer(a: vue)
        return vue
    }

    func updateUIView(_ vue: ChampsSessionVue, context: Context) {
        context.coordinator.proprietaire = self
        context.coordinator.vue = vue
        appliquer(a: vue)
    }

    static func dismantleUIView(_ vue: ChampsSessionVue, coordinator: Coordinateur) {
        for rang in vue.tous {
            rang.champ.delegate = nil
            rang.champ.removeTarget(
                coordinator,
                action: #selector(Coordinateur.texteChange(_:)),
                for: .editingChanged
            )
        }
        coordinator.vue = nil
        coordinator.proprietaire.session.terminerLaSaisie = { false }
        coordinator.proprietaire.session.saisieEncoreActive = { false }
    }

    func sizeThatFits(
        _ proposition: ProposedViewSize, uiView: ChampsSessionVue, context: Context
    ) -> CGSize? {
        guard let largeur = proposition.width, largeur.isFinite else { return nil }
        return CGSize(width: largeur, height: ChampsSessionVue.hauteur(configuration))
    }

    private func appliquer(a vue: ChampsSessionVue) {
        vue.appliquer(configuration)

        let inscription: Bool
        if case .identifiants(true) = configuration { inscription = true } else { inscription = false }

        configurer(
            vue.rangEmail.champ,
            texte: email,
            invite: String(localized: "Adresse e-mail"),
            clavier: .emailAddress,
            contenu: .username,
            retour: configuration == .oubliDemande ? .go : .next
        )
        vue.rangEmail.champ.autocapitalizationType = .none

        configurer(
            vue.rangMotDePasse.champ,
            texte: motDePasse,
            invite: inscription
                ? String(localized: "Mot de passe (6 caractères min.)")
                : String(localized: "Mot de passe"),
            clavier: .default,
            contenu: inscription ? .newPassword : .password,
            retour: .go
        )
        configurer(
            vue.rangCode.champ,
            texte: code,
            invite: String(localized: "Code reçu par courrier"),
            clavier: .numberPad,
            contenu: .oneTimeCode,
            retour: .next
        )
        configurer(
            vue.rangNouveau.champ,
            texte: nouveau,
            invite: String(localized: "Nouveau mot de passe (6 caractères min.)"),
            clavier: .default,
            contenu: .newPassword,
            retour: .go
        )
    }

    /// `updateUIView` repasse à chaque frappe : ne JAMAIS réécrire un trait
    /// clavier qui n'a pas changé, sinon la barre QuickType se reconstruit.
    private func configurer(
        _ champ: UITextField,
        texte: String,
        invite: String,
        clavier: UIKeyboardType,
        contenu: UITextContentType?,
        retour: UIReturnKeyType
    ) {
        if champ.text != texte { champ.text = texte }
        if champ.keyboardType != clavier { champ.keyboardType = clavier }
        if champ.textContentType != contenu { champ.textContentType = contenu }
        if champ.returnKeyType != retour { champ.returnKeyType = retour }
        if champ.attributedPlaceholder?.string != invite {
            champ.attributedPlaceholder = NSAttributedString(
                string: invite,
                attributes: [.foregroundColor: UIColor.placeholderText]
            )
        }
        champ.accessibilityLabel = invite
    }

    @MainActor
    final class Coordinateur: NSObject, UITextFieldDelegate {
        var proprietaire: ChampsSession
        weak var vue: ChampsSessionVue?

        init(_ proprietaire: ChampsSession) {
            self.proprietaire = proprietaire
        }

        @objc func texteChange(_ champ: UITextField) {
            synchroniser(champ)
        }

        func textFieldDidChangeSelection(_ champ: UITextField) {
            // AutoFill peut remplir un champ sans événement de frappe.
            synchroniser(champ)
        }

        private func synchroniser(_ champ: UITextField) {
            guard let vue else { return }
            let valeur = champ.text ?? ""
            if champ === vue.rangEmail.champ, proprietaire.email != valeur {
                proprietaire.email = valeur
            } else if champ === vue.rangMotDePasse.champ, proprietaire.motDePasse != valeur {
                proprietaire.motDePasse = valeur
            } else if champ === vue.rangCode.champ, proprietaire.code != valeur {
                proprietaire.code = valeur
            } else if champ === vue.rangNouveau.champ, proprietaire.nouveau != valeur {
                proprietaire.nouveau = valeur
            }
        }

        func textFieldDidBeginEditing(_ champ: UITextField) {
            journalClavier("didBeginEditing \(champ.isSecureTextEntry ? "secret" : "clair")")
            // La session s'ouvre une seule fois ; passer ensuite d'un champ
            // à l'autre ne change plus aucun état de géométrie.
            proprietaire.session.ouvrir()
        }

        func textFieldDidEndEditing(_ champ: UITextField) {
            journalClavier("didEndEditing \(champ.isSecureTextEntry ? "secret" : "clair")")
        }

        func textFieldShouldReturn(_ champ: UITextField) -> Bool {
            guard let vue else { return false }
            let champs = vue.visibles.map(\.champ)
            if let position = champs.firstIndex(where: { $0 === champ }),
               position + 1 < champs.count {
                // Transfert DIRECT : aucun resign intermédiaire, le clavier
                // reste en place.
                champs[position + 1].becomeFirstResponder()
            } else {
                proprietaire.surValidation()
            }
            return false
        }
    }
}

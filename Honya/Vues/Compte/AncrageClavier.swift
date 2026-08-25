import SwiftUI
import UIKit

// L'ancrage clavier de l'écran de bienvenue — l'architecture éprouvée sur
// Binjo, dont l'écran de connexion a le même décor et les mêmes champs.
//
// Le contenu vit dans un contrôleur UIKit dont le bord bas est contraint au
// guide clavier d'Apple (`UIKeyboardLayoutGuide`, la méthode documentée), et
// l'évitement automatique de SwiftUI est explicitement coupé : deux pilotes
// pour le même déplacement, c'était précisément l'origine des sauts.
//
// Surtout, la position n'est SUIVIE que pendant l'ouverture. À
// `keyboardDidShow`, elle est capturée puis verrouillée jusqu'à la fin de la
// saisie : le passage e-mail → mot de passe, où la barre « Mots de passe »
// change la hauteur du clavier, ne peut alors plus rien déplacer du tout.

/// La saisie vue comme une session : ouverte au premier champ touché,
/// inchangée tant qu'on passe d'un champ à l'autre, fermée une seule fois.
@MainActor
@Observable
final class SessionClavier {
    enum Phase { case inactive, active, fermeture }

    private(set) var phase: Phase = .inactive

    /// Le clavier est-il à l'écran — la seule question que le décor se pose.
    var enSaisie: Bool { phase == .active }

    func ouvrir() {
        guard phase != .active else { return }
        phase = .active
    }

    /// À appeler AVANT de rendre le focus : le contrôleur doit savoir que
    /// cette disparition du clavier est voulue — pendant la saisie, AutoFill
    /// en annonce de fausses qu'il faut ignorer.
    func fermer() {
        guard phase == .active else { return }
        phase = .fermeture
    }

    func clavierRange() {
        guard phase == .fermeture else { return }
        phase = .inactive
    }

    /// Une interruption (permission, AutoFill, changement d'app) peut avaler
    /// la fin de session : on tranche d'après l'état réel du focus.
    func reconcilier(enSaisie: Bool) {
        guard phase == .fermeture else { return }
        phase = enSaisie ? .active : .inactive
    }
}

/// Héberge le contenu dans le contrôleur qui ancre au guide clavier.
struct AncrageClavier<Contenu: View>: UIViewControllerRepresentable {
    let phase: SessionClavier.Phase
    let fermetureVoulue: () -> Bool
    let clavierRange: () -> Void
    @ViewBuilder var contenu: () -> Contenu

    func makeUIViewController(context: Context) -> ControleurAncrageClavier<Contenu> {
        let controleur = ControleurAncrageClavier(
            rootView: contenu(),
            fermetureVoulue: fermetureVoulue,
            clavierRange: clavierRange
        )
        controleur.appliquerPhase(phase)
        return controleur
    }

    func updateUIViewController(
        _ controleur: ControleurAncrageClavier<Contenu>, context: Context
    ) {
        controleur.contenu.rootView = contenu()
        controleur.fermetureVoulue = fermetureVoulue
        controleur.clavierRange = clavierRange
        controleur.appliquerPhase(phase)
    }
}

final class ControleurAncrageClavier<Contenu: View>: UIViewController {
    let contenu: UIHostingController<Contenu>
    private var suitLeClavier: NSLayoutConstraint?
    private var positionGelee: NSLayoutConstraint?
    private var phase: SessionClavier.Phase = .inactive
    private var observateurs: [NSObjectProtocol] = []

    var fermetureVoulue: () -> Bool
    var clavierRange: () -> Void

    init(
        rootView: Contenu,
        fermetureVoulue: @escaping () -> Bool,
        clavierRange: @escaping () -> Void
    ) {
        contenu = UIHostingController(rootView: rootView)
        self.fermetureVoulue = fermetureVoulue
        self.clavierRange = clavierRange
        super.init(nibName: nil, bundle: nil)
        // Ce contrôleur pilote seul le clavier. Sans cette exclusion, SwiftUI
        // appliquerait SON évitement par-dessus le nôtre — deux animations
        // concurrentes sur le même trajet, et l'écran saute.
        contenu.safeAreaRegions = .container
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        for observateur in observateurs {
            NotificationCenter.default.removeObserver(observateur)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        let guide = view.keyboardLayoutGuide
        // Pas de poursuite d'un clavier flottant d'iPad, et clavier fermé, le
        // guide colle au bord physique : le contenu garde alors sa marge de
        // zone sûre habituelle, rien ne change à l'écran.
        guide.followsUndockedKeyboard = false
        guide.usesBottomSafeArea = false

        addChild(contenu)
        let hote = contenu.view!
        hote.translatesAutoresizingMaskIntoConstraints = false
        hote.backgroundColor = .clear
        view.addSubview(hote)

        let suit = hote.bottomAnchor.constraint(equalTo: guide.topAnchor)
        suitLeClavier = suit
        NSLayoutConstraint.activate([
            hote.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hote.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hote.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            suit,
        ])
        contenu.didMove(toParent: self)

        observer(UIResponder.keyboardDidShowNotification) { [weak self] in
            self?.gelerLaPosition()
        }
        observer(UIResponder.keyboardWillHideNotification) { [weak self] in
            // Une fermeture voulue se prépare AVANT la disparition : on
            // rattache au guide pour que le formulaire redescende AVEC le
            // clavier. Un willHide pendant la saisie — AutoFill qui remplace
            // la barre — reste ignoré : la position gelée ne bouge pas.
            guard let self, self.fermetureVoulue() else { return }
            self.suivreANouveau()
        }
        observer(UIResponder.keyboardDidHideNotification) { [weak self] in
            guard let self, self.fermetureVoulue() else { return }
            self.suivreANouveau()
            self.clavierRange()
        }
    }

    private func observer(_ nom: Notification.Name, _ action: @escaping () -> Void) {
        observateurs.append(NotificationCenter.default.addObserver(
            forName: nom, object: nil, queue: .main
        ) { _ in action() })
    }

    /// Tout changement de phase rend la vue au guide ; le gel ne se
    /// réarme qu'au prochain `keyboardDidShow` d'une session active.
    func appliquerPhase(_ nouvelle: SessionClavier.Phase) {
        guard phase != nouvelle else { return }
        phase = nouvelle
        suivreANouveau()
    }

    /// La capture : le guide et la constante décrivent exactement la même
    /// position à cet instant, l'échange est invisible. À partir d'ici, plus
    /// rien ne suit le clavier — c'est le gel qui supprime le saut.
    private func gelerLaPosition() {
        guard phase == .active,
              positionGelee == nil,
              isViewLoaded,
              view.window != nil,
              let suitLeClavier
        else { return }

        view.layoutIfNeeded()
        let hautDuClavier = view.keyboardLayoutGuide.layoutFrame.minY
        guard hautDuClavier.isFinite,
              hautDuClavier > view.safeAreaInsets.top,
              hautDuClavier < view.bounds.maxY - 1
        else { return }

        let gelee = contenu.view.bottomAnchor.constraint(
            equalTo: view.topAnchor, constant: hautDuClavier
        )
        UIView.performWithoutAnimation {
            suitLeClavier.isActive = false
            gelee.isActive = true
            view.layoutIfNeeded()
        }
        positionGelee = gelee
    }

    private func suivreANouveau() {
        guard isViewLoaded, let suitLeClavier, let positionGelee else { return }
        UIView.performWithoutAnimation {
            positionGelee.isActive = false
            suitLeClavier.isActive = true
            view.layoutIfNeeded()
        }
        self.positionGelee = nil
    }
}

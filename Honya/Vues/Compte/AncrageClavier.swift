import SwiftUI
import UIKit

// L'ancrage clavier de l'écran de bienvenue.
//
// Le contenu vit dans un contrôleur UIKit dont le bord bas est contraint au
// guide clavier d'Apple (`UIKeyboardLayoutGuide`) — le mécanisme documenté :
// contraint au guide, le contenu suit les animations du clavier sans écouter
// soi-même les notifications. L'évitement automatique de SwiftUI est coupé
// (`safeAreaRegions = .container`) : deux pilotes sur le même trajet, c'était
// l'origine des sauts.
//
// Le guide seul ne suffit pourtant pas : au passage e-mail → mot de passe, la
// barre d'AutoFill change la hauteur du clavier et iOS émet parfois de FAUX
// willHide/didHide alors que le clavier reste à l'écran. Quiconque suit ces
// événements — le guide compris — rejoue le trajet. D'où les deux règles :
//
// 1. LE GEL. Une fois le clavier posé (`keyboardDidShow`), la position du
//    contenu est capturée puis verrouillée : plus rien ne suit le guide, les
//    reconfigurations d'AutoFill ne déplacent plus un pixel.
// 2. LA GÉOMÉTRIE, PAS LES ÉVÉNEMENTS. Le dégel ne se décide jamais sur
//    willHide/didHide — invérifiables — mais sur la destination réelle du
//    clavier, lue dans `keyboardWillChangeFrame` : une frame d'arrivée hors
//    écran veut dire « le clavier part vraiment ». Fermeture voulue, le
//    contenu se rattache au guide et redescend avec lui ; départ subi (fiche
//    AutoFill, dictée, clavier matériel), on marque un temps court — le temps
//    qu'un éventuel faux départ se démente — puis on rend le contenu au guide
//    plutôt que de le laisser flotter au milieu de l'écran.

#if DEBUG
/// Trace du banc d'essai. La console d'un simulateur sans terminal ne
/// remonte pas : le journal s'écrit dans Documents, que la CI récupère
/// avec `simctl get_app_container` une fois le banc déroulé.
@MainActor
func journalClavier(_ message: String) {
    let temps = Date().timeIntervalSinceReferenceDate
    let ligne = String(format: "[%.3f] %@", temps, message) + "\n"
    print(ligne, terminator: "")
    if let documents = FileManager.default.urls(
        for: .documentDirectory, in: .userDomainMask
    ).first {
        let fichier = documents.appendingPathComponent("journal-clavier.log")
        if let donnees = ligne.data(using: .utf8) {
            if let poignee = try? FileHandle(forWritingTo: fichier) {
                _ = try? poignee.seekToEnd()
                try? poignee.write(contentsOf: donnees)
                try? poignee.close()
            } else {
                try? donnees.write(to: fichier)
            }
        }
    }
}
#else
@MainActor
@inline(__always)
func journalClavier(_ message: String) {}
#endif

/// La saisie vue comme une session : ouverte au premier champ touché,
/// inchangée tant qu'on passe d'un champ à l'autre, fermée une seule fois.
@MainActor
@Observable
final class SessionClavier {
    enum Phase { case inactive, active, fermeture }

    private(set) var phase: Phase = .inactive

    /// Le clavier est-il à l'écran — la seule question que le décor se pose.
    var enSaisie: Bool { phase == .active }

    /// Les deux poignées vers les champs natifs, posées à leur arrivée à
    /// l'écran : fermer la saisie, et lire l'état réel du focus. La session
    /// n'a pas besoin d'en savoir plus sur eux.
    @ObservationIgnored var terminerLaSaisie: () -> Bool = { false }
    @ObservationIgnored var saisieEncoreActive: () -> Bool = { false }

    func ouvrir() {
        guard phase != .active else { return }
        phase = .active
    }

    /// Ferme dans le bon ordre : la phase d'abord, le focus ensuite — le
    /// contrôleur sait ainsi que le départ du clavier qui suit est voulu.
    func fermerLaSaisie() {
        guard phase == .active else { return }
        phase = .fermeture
        if !terminerLaSaisie() { phase = .inactive }
    }

    func clavierRange() {
        guard phase == .fermeture else { return }
        phase = .inactive
    }

    /// Une interruption (permission, AutoFill, changement d'app) peut avaler
    /// la fin de session : on tranche d'après l'état réel du focus.
    func reconcilier() {
        guard phase == .fermeture else { return }
        phase = saisieEncoreActive() ? .active : .inactive
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
    /// Numérote les départs subis : un faux départ, démenti par la frame
    /// suivante, périme le dégel programmé avant qu'il ne s'exécute.
    private var generationDepart = 0

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
        // Ce contrôleur pilote seul le clavier : on retire la région
        // `.keyboard` de la zone sûre du contenu, sans quoi SwiftUI
        // appliquerait SON évitement par-dessus le nôtre.
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

        observer(UIResponder.keyboardDidShowNotification) { [weak self] _ in
            journalClavier("didShow")
            self?.gelerLaPosition()
        }
        observer(UIResponder.keyboardWillChangeFrameNotification) { [weak self] notification in
            let cadre = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey]
                         as? NSValue)?.cgRectValue ?? .zero
            journalClavier("willChangeFrame -> \(Int(cadre.minY)) h\(Int(cadre.height))")
            self?.traiterChangementDeFrame(notification)
        }
        observer(UIResponder.keyboardWillShowNotification) { _ in
            journalClavier("willShow")
        }
        observer(UIResponder.keyboardWillHideNotification) { _ in
            journalClavier("willHide")
        }
        observer(UIResponder.keyboardDidHideNotification) { _ in
            journalClavier("didHide")
        }
    }

    private func observer(
        _ nom: Notification.Name, _ action: @escaping (Notification) -> Void
    ) {
        observateurs.append(NotificationCenter.default.addObserver(
            forName: nom, object: nil, queue: .main
        ) { notification in
            MainActor.assumeIsolated { action(notification) }
        })
    }

    // MARK: - Les décisions

    /// Tout changement de phase rend la vue au guide ; le gel ne se réarme
    /// qu'au prochain `keyboardDidShow` d'une session active.
    func appliquerPhase(_ nouvelle: SessionClavier.Phase) {
        guard phase != nouvelle else { return }
        phase = nouvelle
        generationDepart += 1
        suivreANouveau()
    }

    /// Où le clavier va-t-il VRAIMENT ? La frame d'arrivée fait foi.
    private func traiterChangementDeFrame(_ notification: Notification) {
        guard isViewLoaded, view.window != nil else { return }
        guard let valeur = notification
            .userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue
        else { return }

        let arrivee = valeur.cgRectValue
        let ecran = view.window?.screen.bounds ?? UIScreen.main.bounds
        let resteVisible = arrivee.minY < ecran.maxY - 1 && arrivee.height > 0

        if resteVisible {
            // Le clavier reste (ou revient) : tout départ annoncé était faux,
            // le dégel programmé ne doit plus s'exécuter. La position gelée,
            // elle, n'a jamais bougé — c'est tout l'intérêt.
            generationDepart += 1
            return
        }

        if fermetureVoulue() {
            // Fermeture demandée par l'écran : on se rattache au guide tout
            // de suite — les deux contraintes décrivent la même position à
            // cet instant — et le contenu redescend AVEC le clavier.
            generationDepart += 1
            suivreANouveau()
            clavierRange()
            return
        }

        // Départ subi en pleine saisie : fiche AutoFill, dictée, clavier
        // matériel… ou un faux départ d'iOS. On laisse au démenti le temps
        // d'arriver ; s'il ne vient pas, le contenu est rendu au guide —
        // un formulaire figé au milieu d'un écran sans clavier n'a pas de
        // sens. La session, elle, reste ouverte : si le clavier revient,
        // `keyboardDidShow` regèlera au bon endroit.
        generationDepart += 1
        let generation = generationDepart
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, generation == self.generationDepart else { return }
                self.suivreANouveau()
            }
        }
    }

    // MARK: - Le gel

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
        journalClavier("gel a y=\(Int(hautDuClavier))")
    }

    private func suivreANouveau() {
        guard isViewLoaded, let suitLeClavier, let positionGelee else { return }
        journalClavier("degel")
        UIView.performWithoutAnimation {
            positionGelee.isActive = false
            suitLeClavier.isActive = true
            view.layoutIfNeeded()
        }
        self.positionGelee = nil
    }

    /// Rotation ou changement de fenêtre : une constante capturée dans
    /// l'ancienne géométrie serait fausse — on rend la vue au guide.
    override func viewWillTransition(
        to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator
    ) {
        super.viewWillTransition(to: size, with: coordinator)
        generationDepart += 1
        suivreANouveau()
    }
}

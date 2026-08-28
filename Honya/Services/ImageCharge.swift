import UIKit
import SwiftUI
import CryptoKit
import CoreImage

// MARK: - Vignettes Apple en pleine résolution

/// Les serveurs d'images d'Apple (mzstatic) renvoient la taille demandée dans
/// le dernier segment de l'URL. Une couverture portrait demandée en 600x600
/// ne fait en réalité que 400 px de large — flou garanti sur un écran 3x.
/// On réécrit donc toute vignette vers 1200x1200 avant de la charger.
enum ArtworkApple {
    /// 1200 px pour une fiche plein écran ; beaucoup moins pour une vignette.
    /// Demander systématiquement du 1200 coûte ~5,8 Mo décodés par couverture :
    /// sur un mur d'une vingtaine, la mémoire s'envole pour rien.
    static func nette(_ chaine: String, cote: Int = 1200) -> String {
        guard chaine.contains("mzstatic.com"),
              var composants = URLComponents(string: chaine) else { return chaine }
        var morceaux = composants.path.split(separator: "/").map(String.init)
        guard let dernier = morceaux.last,
              dernier.range(of: #"^\d{2,4}x\d{2,4}"#, options: .regularExpression) != nil
        else { return chaine }
        let ext = (dernier as NSString).pathExtension
        let calibre = "\(cote)x\(cote)bb"
        morceaux[morceaux.count - 1] = ext.isEmpty ? calibre : "\(calibre).\(ext)"
        composants.path = "/" + morceaux.joined(separator: "/")
        return composants.url?.absoluteString ?? chaine
    }
}

// MARK: - Chargeur d'images de couvertures (mémoire + cache HTTP système)

actor ImageCharge {
    static let partage = ImageCharge()

    private let memoire = NSCache<NSString, UIImage>()

    init() {
        memoire.countLimit = 200
        memoire.totalCostLimit = 80_000_000
    }

    func vider() {
        memoire.removeAllObjects()
    }

    func uiImage(depuis chaine: String?, cote: Int = 1200) async -> UIImage? {
        guard var chaine, !chaine.isEmpty else { return nil }

        // Une reference locale est autorisee AVANT le cache. Sans cet ordre,
        // une image de A deja en memoire pourrait ressortir lorsque B presente
        // par erreur la meme ancienne reference relative.
        if CouverturesPersonnelles.estReferencePersonnelle(chaine) {
            guard let urlLocale = await CouverturesPersonnelles.urlLecture(chaine) else {
                return nil
            }
            let cle = Self.empreinte("locale|" + urlLocale.path)
            if let enMemoire = memoire.object(forKey: cle as NSString) {
                return enMemoire
            }
            guard let donnees = try? Data(contentsOf: urlLocale),
                  let image = UIImage(data: donnees) else { return nil }
            let pixels = Int(image.size.width * image.scale)
                * Int(image.size.height * image.scale) * 4
            memoire.setObject(image, forKey: cle as NSString, cost: pixels)
            return image
        }

        // Les URLs Google Books arrivent parfois en http.
        if chaine.hasPrefix("http://") {
            chaine = "https://" + chaine.dropFirst("http://".count)
        }
        // Même les couvertures enregistrées en petit ressortent nettes :
        // la réécriture se fait au chargement, pas dans les données.
        let brute = chaine
        chaine = ArtworkApple.nette(chaine, cote: cote)
        guard URL(string: chaine) != nil else { return nil }

        let cle = Self.empreinte(chaine)
        if let enMemoire = memoire.object(forKey: cle as NSString) {
            return enMemoire
        }
        // Certaines vignettes n'existent pas au calibre demandé : le serveur
        // répond alors autre chose qu'une image. On retombe sur l'adresse
        // d'origine plutôt que d'abandonner la couverture.
        let candidates = chaine == brute ? [chaine] : [chaine, brute]
        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            let donnees: Data?
            if let (telechargees, _) = try? await URLSession.shared.data(from: url) {
                donnees = telechargees
            } else {
                donnees = nil
            }
            guard let donnees, let image = UIImage(data: donnees) else { continue }
            let pixels = Int(image.size.width * image.scale)
                * Int(image.size.height * image.scale) * 4
            memoire.setObject(image, forKey: cle as NSString, cost: pixels)
            return image
        }
        return nil
    }

    private static func empreinte(_ chaine: String) -> String {
        let hachage = SHA256.hash(data: Data(chaine.utf8))
        return hachage.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Couvertures fournies par le lecteur

/// Une édition rare peut être parfaitement identifiée par son ISBN sans que
/// les catalogues autorisés exposent sa couverture. Honya conserve alors une
/// photo choisie par le lecteur dans son conteneur privé, sans l'envoyer à un
/// serveur ni la faire passer pour l'image d'une autre édition.
enum CouverturesPersonnelles {
    private static let prefixeLegacy = "honya-cover:"
    private static let prefixeV2 = "honya-cover-v2:"

    @MainActor
    static func enregistrer(_ donnees: Data) throws -> String {
        guard let identifiant = StockageCompte.partage.identifiantActif else {
            throw Erreur.compteIndisponible
        }
        guard let image = UIImage(data: donnees) else { throw Erreur.imageInvalide }
        let imageReduite = reduire(image)
        guard let jpeg = imageReduite.jpegData(compressionQuality: 0.88) else {
            throw Erreur.imageInvalide
        }

        let repertoire = try urlDossierActif(creer: true)
        let url = repertoire
            .appendingPathComponent(UUID().uuidString.lowercased())
            .appendingPathExtension("jpg")
        try jpeg.write(to: url, options: [.atomic, .completeFileProtection])
        // Ne jamais persister l'URL absolue du sandbox : son UUID change lors
        // d'une mise à jour App Store. Seul le nom relatif est stable.
        return prefixeV2
            + identifiant.uuidString.lowercased()
            + "/"
            + url.lastPathComponent
    }

    @MainActor
    static func estPersonnelle(_ chaine: String?) -> Bool {
        urlLecture(chaine) != nil
    }

    static func estReferencePersonnelle(_ chaine: String?) -> Bool {
        chaine.flatMap(reference) != nil
    }

    /// Résout le nom relatif dans le conteneur courant. Les anciennes valeurs
    /// `file://` de développement restent lisibles puis survivront au prochain
    /// remplacement de photo sous le nouveau format stable.
    @MainActor
    static func urlLecture(_ chaine: String?) -> URL? {
        guard let chaine, let reference = reference(chaine),
              let repertoire = StockageCompte.partage.dossierCouverturesActif
        else { return nil }

        switch reference {
        case .v2(let proprietaire, let nom):
            guard StockageCompte.partage.identifiantActif == proprietaire else {
                return nil
            }
            return repertoire.appendingPathComponent(nom, isDirectory: false)
        case .legacy(let nom):
            guard StockageCompte.partage.accepteReferencesCouverturesLegacy else {
                return nil
            }
            // On reconstruit toujours le chemin sous le dossier autorise. Une
            // ancienne URL absolue persiste seulement son nom de fichier.
            return repertoire.appendingPathComponent(nom, isDirectory: false)
        }
    }

    @MainActor
    static func supprimer(_ chaine: String?) {
        guard let url = urlLecture(chaine) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    @MainActor
    static func supprimerToutes() throws {
        let url = try urlDossierActif(creer: false)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    @MainActor
    private static func urlDossierActif(creer: Bool) throws -> URL {
        guard let url = StockageCompte.partage.dossierCouverturesActif else {
            throw Erreur.dossierIndisponible
        }
        if creer {
            try FileManager.default.createDirectory(
                at: url, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete]
            )
        }
        return url
    }

    private static func reduire(_ image: UIImage) -> UIImage {
        let maximum: CGFloat = 1_800
        let grandCote = max(image.size.width, image.size.height)
        guard grandCote > maximum else { return image }
        let facteur = maximum / grandCote
        let taille = CGSize(
            width: max(1, image.size.width * facteur),
            height: max(1, image.size.height * facteur)
        )
        return UIGraphicsImageRenderer(size: taille).image { _ in
            image.draw(in: CGRect(origin: .zero, size: taille))
        }
    }

    private enum Reference {
        case v2(UUID, String)
        case legacy(String)
    }

    private static func reference(_ chaine: String) -> Reference? {
        if chaine.hasPrefix(prefixeV2) {
            let morceaux = chaine.dropFirst(prefixeV2.count).split(
                separator: "/",
                omittingEmptySubsequences: false
            )
            guard morceaux.count == 2,
                  let proprietaire = UUID(uuidString: String(morceaux[0])),
                  let nom = nomFichierValide(String(morceaux[1])) else { return nil }
            return .v2(proprietaire, nom)
        }
        if chaine.hasPrefix(prefixeLegacy) {
            guard let nom = nomFichierValide(
                String(chaine.dropFirst(prefixeLegacy.count))
            ) else { return nil }
            return .legacy(nom)
        }
        if let url = URL(string: chaine), url.isFileURL,
           url.deletingLastPathComponent().lastPathComponent == "Couvertures",
           let nom = nomFichierValide(url.lastPathComponent) {
            return .legacy(nom)
        }
        return nil
    }

    private static func nomFichierValide(_ nom: String) -> String? {
        guard !nom.isEmpty,
              !nom.contains("/"), !nom.contains("\\"),
              (nom as NSString).pathExtension.lowercased() == "jpg"
        else { return nil }
        return nom
    }

    private enum Erreur: Error {
        case imageInvalide, dossierIndisponible, compteIndisponible
    }
}

// MARK: - Couleur dominante d'une couverture (fiche teintée, à la Apple Books)

enum CouleurCouverture {
    /// Couleur moyenne de l'image (CIAreaAverage), assombrie pour garantir un texte blanc lisible.
    static func teinteDeFond(_ image: UIImage) -> Color? {
        guard let ci = CIImage(image: image) else { return nil }
        guard let filtre = CIFilter(
            name: "CIAreaAverage",
            parameters: [kCIInputImageKey: ci, kCIInputExtentKey: CIVector(cgRect: ci.extent)]
        ), let sortie = filtre.outputImage else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        let contexte = CIContext(options: [.workingColorSpace: NSNull()])
        contexte.render(
            sortie,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )
        let rouge = Double(pixel[0]) / 255
        let vert = Double(pixel[1]) / 255
        let bleu = Double(pixel[2]) / 255

        // Assombrit et sature légèrement : le fond doit porter du texte blanc (contraste AA).
        let facteur = 0.52
        return Color(
            red: rouge * facteur,
            green: vert * facteur,
            blue: bleu * facteur
        )
    }
}

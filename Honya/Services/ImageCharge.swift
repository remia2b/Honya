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

// MARK: - Chargeur d'images de couvertures (mémoire + disque, hors ligne ensuite)

actor ImageCharge {
    static let partage = ImageCharge()

    private let memoire = NSCache<NSString, UIImage>()
    private let dossier: URL

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        dossier = caches.appendingPathComponent("Couvertures", isDirectory: true)
        try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
    }

    func uiImage(depuis chaine: String?, cote: Int = 1200) async -> UIImage? {
        guard var chaine, !chaine.isEmpty else { return nil }
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
        let fichier = dossier.appendingPathComponent(cle)
        if let donnees = try? Data(contentsOf: fichier), let image = UIImage(data: donnees) {
            memoire.setObject(image, forKey: cle as NSString)
            return image
        }
        // Certaines vignettes n'existent pas au calibre demandé : le serveur
        // répond alors autre chose qu'une image. On retombe sur l'adresse
        // d'origine plutôt que d'abandonner la couverture.
        let candidates = chaine == brute ? [chaine] : [chaine, brute]
        for candidate in candidates {
            guard let url = URL(string: candidate),
                  let (donnees, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: donnees)
            else { continue }
            try? donnees.write(to: fichier)
            memoire.setObject(image, forKey: cle as NSString)
            return image
        }
        return nil
    }

    private static func empreinte(_ chaine: String) -> String {
        let hachage = SHA256.hash(data: Data(chaine.utf8))
        return hachage.map { String(format: "%02x", $0) }.joined()
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

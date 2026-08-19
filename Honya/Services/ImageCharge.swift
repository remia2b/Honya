import UIKit
import SwiftUI
import CryptoKit
import CoreImage

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

    func uiImage(depuis chaine: String?) async -> UIImage? {
        guard var chaine, !chaine.isEmpty else { return nil }
        // Les URLs Google Books arrivent parfois en http.
        if chaine.hasPrefix("http://") {
            chaine = "https://" + chaine.dropFirst("http://".count)
        }
        guard let url = URL(string: chaine) else { return nil }

        let cle = Self.empreinte(chaine)
        if let enMemoire = memoire.object(forKey: cle as NSString) {
            return enMemoire
        }
        let fichier = dossier.appendingPathComponent(cle)
        if let donnees = try? Data(contentsOf: fichier), let image = UIImage(data: donnees) {
            memoire.setObject(image, forKey: cle as NSString)
            return image
        }
        do {
            let (donnees, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: donnees) else { return nil }
            try? donnees.write(to: fichier)
            memoire.setObject(image, forKey: cle as NSString)
            return image
        } catch {
            return nil
        }
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

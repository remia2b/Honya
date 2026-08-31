import CryptoKit
import Foundation
import ImageIO
import UIKit

/// Une couverture du mur de connexion, indépendante de la vue qui l'affiche.
///
/// Le modèle reste volontairement compatible avec l'ancien JSON conservé
/// dans `UserDefaults` : cette compatibilité permet de récupérer, une seule
/// fois, les pixels encore présents dans `URLCache` après une mise à jour.
struct VignetteMurBienvenue: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let url: String?
    let titre: String
    let manga: Bool
    let attribution: String?

    init(
        id: String,
        url: String?,
        titre: String,
        manga: Bool,
        attribution: String? = nil
    ) {
        self.id = id
        self.url = url
        self.titre = titre
        self.manga = manga
        self.attribution = attribution
    }
}

/// Cache durable du mur de bienvenue.
///
/// Contrairement au cache HTTP, ce fichier appartient à l'application et peut
/// donc être lu de façon synchrone avant le premier rendu SwiftUI. Métadonnées
/// et images sont réunies dans une même archive binaire, remplacée de façon
/// atomique : un arrêt pendant l'écriture laisse toujours l'ancien mur intact.
enum CacheMurBienvenue {
    static let minimumParDefaut = 3
    static let limiteParDefaut = 18

    struct Contenu {
        let vignettes: [VignetteMurBienvenue]
        /// Les clés sont les URL originales des vignettes, comme dans la vue.
        let images: [String: UIImage]
    }

    /// Charge immédiatement les pixels propres à une langue/storefront.
    ///
    /// Lorsqu'aucune archive durable n'existe encore, la méthode tente une
    /// migration synchrone et sans réseau depuis l'ancien couple
    /// `UserDefaults` + `URLCache`. Cela rend la première version équipée du
    /// nouveau cache immédiate elle aussi, si iOS possède encore les réponses.
    static func charger(
        cle: String,
        minimum: Int = minimumParDefaut,
        limite: Int = limiteParDefaut,
        migrerDepuisURLCache: Bool = true
    ) -> Contenu? {
        guard let bornes = bornesValides(minimum: minimum, limite: limite),
              !cle.isEmpty else { return nil }

        if let archive = lireArchive(cle: cle),
           let contenu = contenu(
               depuis: archive,
               minimum: bornes.minimum,
               limite: bornes.limite
           ) {
            return contenu
        }

        guard migrerDepuisURLCache else { return nil }
        return migrerAncienCache(
            cle: cle,
            minimum: bornes.minimum,
            limite: bornes.limite
        )
    }

    /// Encode et enregistre un nouveau mur hors du thread d'interface.
    ///
    /// Seules les vignettes qui possèdent une vraie image sont persistées.
    /// La valeur de retour indique qu'une archive complète (au moins
    /// `minimum` couvertures) a bien remplacé l'ancienne.
    static func enregistrer(
        cle: String,
        vignettes: [VignetteMurBienvenue],
        images: [String: UIImage],
        minimum: Int = minimumParDefaut,
        limite: Int = limiteParDefaut
    ) async -> Bool {
        guard let bornes = bornesValides(minimum: minimum, limite: limite),
              !cle.isEmpty else { return false }

        let lot = LotEcriture(vignettes: vignettes, images: images)
        return await ecrivain.enregistrer(
            lot,
            cle: cle,
            minimum: bornes.minimum,
            limite: bornes.limite
        )
    }

    /// Lance l'écriture dans une tâche autonome. La préparation du prochain
    /// mur doit survivre à la disparition de `BienvenueView` lorsqu'une
    /// connexion réussit pendant l'enregistrement.
    static func programmerEnregistrement(
        cle: String,
        vignettes: [VignetteMurBienvenue],
        images: [String: UIImage],
        minimum: Int = minimumParDefaut,
        limite: Int = limiteParDefaut
    ) {
        guard let bornes = bornesValides(minimum: minimum, limite: limite),
              !cle.isEmpty else { return }
        let lot = LotEcriture(vignettes: vignettes, images: images)
        Task.detached(priority: .utility) {
            _ = await ecrivain.enregistrer(
                lot,
                cle: cle,
                minimum: bornes.minimum,
                limite: bornes.limite
            )
        }
    }

    // MARK: - Archive

    private static let versionArchive = 1
    private static let largeurDecodeeMaximum = 700
    private static let octetsMaximumParImage = 16_000_000
    private static let octetsMaximumArchive = 96_000_000
    private static let ecrivain = Ecrivain()

    private struct Archive: Codable {
        let version: Int
        let enregistreeLe: Date
        let vignettes: [VignetteMurBienvenue]
        let images: [ImagePersistee]
    }

    private struct ImagePersistee: Codable {
        let url: String
        let donnees: Data
    }

    /// UIKit expose `UIImage` comme type de référence non Sendable. Le lot
    /// franchit ici un acteur dédié uniquement parce que les images reçues
    /// sont des instantanés immuables déjà décodés par `ImageCharge`.
    private struct LotEcriture: @unchecked Sendable {
        let vignettes: [VignetteMurBienvenue]
        let images: [String: UIImage]
    }

    private actor Ecrivain {
        func enregistrer(
            _ lot: LotEcriture,
            cle: String,
            minimum: Int,
            limite: Int
        ) -> Bool {
            guard !Task.isCancelled,
                  let archive = CacheMurBienvenue.fabriquerArchive(
                      lot,
                      minimum: minimum,
                      limite: limite
                  ),
                  !Task.isCancelled else { return false }
            return CacheMurBienvenue.ecrire(archive, cle: cle)
        }
    }

    private static func fabriquerArchive(
        _ lot: LotEcriture,
        minimum: Int,
        limite: Int
    ) -> Archive? {
        var identifiants = Set<String>()
        var urls = Set<String>()
        var vignettes: [VignetteMurBienvenue] = []
        var images: [ImagePersistee] = []
        var tailleCumulee = 0

        for vignette in lot.vignettes {
            guard vignettes.count < limite,
                  !identifiants.contains(vignette.id),
                  let url = vignette.url,
                  !url.isEmpty,
                  !urls.contains(url),
                  let image = lot.images[url],
                  let donnees = image.jpegData(compressionQuality: 0.90),
                  !donnees.isEmpty,
                  donnees.count <= octetsMaximumParImage,
                  tailleCumulee + donnees.count <= octetsMaximumArchive,
                  decoderImage(donnees) != nil
            else { continue }

            identifiants.insert(vignette.id)
            urls.insert(url)
            vignettes.append(vignette)
            images.append(.init(url: url, donnees: donnees))
            tailleCumulee += donnees.count
        }

        guard vignettes.count >= minimum else { return nil }
        return Archive(
            version: versionArchive,
            enregistreeLe: Date(),
            vignettes: vignettes,
            images: images
        )
    }

    private static func lireArchive(cle: String) -> Archive? {
        guard let url = try? urlArchive(cle: cle, creerDossier: false),
              let donnees = try? Data(contentsOf: url, options: [.mappedIfSafe]),
              donnees.count <= octetsMaximumArchive,
              let archive = try? decodeur.decode(Archive.self, from: donnees),
              archive.version == versionArchive else { return nil }
        return archive
    }

    private static func contenu(
        depuis archive: Archive,
        minimum: Int,
        limite: Int
    ) -> Contenu? {
        let donneesParURL = Dictionary(
            archive.images.map { ($0.url, $0.donnees) },
            uniquingKeysWith: { premiere, _ in premiere }
        )
        var identifiants = Set<String>()
        var urls = Set<String>()
        var vignettes: [VignetteMurBienvenue] = []
        var images: [String: UIImage] = [:]

        for vignette in archive.vignettes {
            guard vignettes.count < limite,
                  !identifiants.contains(vignette.id),
                  let url = vignette.url,
                  !url.isEmpty,
                  !urls.contains(url),
                  let donnees = donneesParURL[url],
                  donnees.count <= octetsMaximumParImage,
                  let image = decoderImage(donnees) else { continue }
            identifiants.insert(vignette.id)
            urls.insert(url)
            vignettes.append(vignette)
            images[url] = image
        }

        guard vignettes.count >= minimum else { return nil }
        return Contenu(vignettes: vignettes, images: images)
    }

    private static var encodeur: PropertyListEncoder {
        let encodeur = PropertyListEncoder()
        encodeur.outputFormat = .binary
        return encodeur
    }

    private static var decodeur: PropertyListDecoder { PropertyListDecoder() }

    private static func ecrire(_ archive: Archive, cle: String) -> Bool {
        do {
            let donnees = try encodeur.encode(archive)
            guard donnees.count <= octetsMaximumArchive else { return false }
            let url = try urlArchive(cle: cle, creerDossier: true)
            try donnees.write(
                to: url,
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )
            try exclureDeLaSauvegarde(url)
            return true
        } catch {
            return false
        }
    }

    private static func urlArchive(cle: String, creerDossier: Bool) throws -> URL {
        let fichiers = FileManager.default
        guard let support = fichiers.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { throw Erreur.dossierIndisponible }

        let dossier = support
            .appendingPathComponent("Honya", isDirectory: true)
            .appendingPathComponent("MurBienvenue", isDirectory: true)
        if creerDossier {
            try fichiers.createDirectory(
                at: dossier,
                withIntermediateDirectories: true,
                attributes: [
                    .protectionKey:
                        FileProtectionType.completeUntilFirstUserAuthentication,
                ]
            )
            try exclureDeLaSauvegarde(dossier)
        }

        return dossier
            .appendingPathComponent(empreinte(cle), isDirectory: false)
            .appendingPathExtension("plist")
    }

    private static func exclureDeLaSauvegarde(_ url: URL) throws {
        var url = url
        var valeurs = URLResourceValues()
        valeurs.isExcludedFromBackup = true
        try url.setResourceValues(valeurs)
    }

    private static func empreinte(_ chaine: String) -> String {
        SHA256.hash(data: Data(chaine.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func bornesValides(
        minimum: Int,
        limite: Int
    ) -> (minimum: Int, limite: Int)? {
        guard minimum > 0, limite >= minimum else { return nil }
        return (minimum, limite)
    }

    /// Décode et prépare réellement les pixels. `UIImage(data:)` seul peut
    /// rester paresseux et repousser le coût au premier dessin SwiftUI.
    private static func decoderImage(_ donnees: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(donnees as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(
                  source,
                  0,
                  [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceShouldCacheImmediately: true,
                      kCGImageSourceThumbnailMaxPixelSize:
                          largeurDecodeeMaximum,
                  ] as CFDictionary
              ) else { return nil }
        return UIImage(cgImage: image)
    }

    // MARK: - Migration de l'ancien cache HTTP

    private static func migrerAncienCache(
        cle: String,
        minimum: Int,
        limite: Int
    ) -> Contenu? {
        guard let metadonnees = UserDefaults.standard.data(forKey: cle),
              let anciennes = try? JSONDecoder().decode(
                  [VignetteMurBienvenue].self,
                  from: metadonnees
              ) else { return nil }

        var identifiants = Set<String>()
        var urls = Set<String>()
        var vignettes: [VignetteMurBienvenue] = []
        var images: [String: UIImage] = [:]
        var imagesPersistees: [ImagePersistee] = []
        var tailleCumulee = 0

        for vignette in anciennes {
            guard vignettes.count < limite,
                  !identifiants.contains(vignette.id),
                  let url = vignette.url,
                  !url.isEmpty,
                  !urls.contains(url),
                  let cachee = imageDansURLCache(url),
                  cachee.donnees.count <= octetsMaximumParImage,
                  tailleCumulee + cachee.donnees.count <= octetsMaximumArchive
            else { continue }

            identifiants.insert(vignette.id)
            urls.insert(url)
            vignettes.append(vignette)
            images[url] = cachee.image
            imagesPersistees.append(.init(url: url, donnees: cachee.donnees))
            tailleCumulee += cachee.donnees.count
        }

        guard vignettes.count >= minimum else { return nil }
        let archive = Archive(
            version: versionArchive,
            enregistreeLe: Date(),
            vignettes: vignettes,
            images: imagesPersistees
        )
        // La migration reste utile pour ce lancement même si le stockage
        // durable est momentanément indisponible.
        _ = ecrire(archive, cle: cle)
        return Contenu(vignettes: vignettes, images: images)
    }

    private static func imageDansURLCache(
        _ chaine: String
    ) -> (donnees: Data, image: UIImage)? {
        let normalisee = chaine.hasPrefix("http://")
            ? "https://" + chaine.dropFirst("http://".count)
            : chaine
        let apple = ArtworkApple.nette(normalisee, cote: 700)
        let adaptee = ArtworkBnF.adaptee(apple, cote: 700)
        var candidates = adaptee == normalisee
            ? [normalisee]
            : [adaptee, normalisee]
        if normalisee != chaine { candidates.append(chaine) }

        var urlsVues = Set<String>()
        for candidate in candidates where urlsVues.insert(candidate).inserted {
            guard let url = URL(string: candidate) else { continue }
            var requete = URLRequest(url: url)
            requete.cachePolicy = .returnCacheDataDontLoad
            guard let reponse = URLCache.shared.cachedResponse(for: requete),
                  !reponse.data.isEmpty,
                  reponse.data.count <= octetsMaximumParImage,
                  let image = decoderImage(reponse.data) else { continue }
            return (reponse.data, image)
        }
        return nil
    }

    private enum Erreur: Error {
        case dossierIndisponible
    }
}

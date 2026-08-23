import Foundation
import SwiftData

/// Le cœur du « tout arrive dans ma langue, tout seul » : va chercher dans le
/// catalogue du pays du lecteur l'édition locale d'une série ou d'un livre,
/// et l'applique — nom, couvertures de CHAQUE tome, quatrième de couverture.
///
/// Trois règles d'or, tirées des échecs passés :
/// 1. On n'ÉCRIT que sur correspondance STRICTE (même série vérifiée, même
///    numéro de tome). Dans le doute, on n'écrit rien.
/// 2. Jamais un titre dans un alphabet que le lecteur ne lit pas.
/// 3. Jamais écraser une donnée sûre par une incertaine — mais une donnée
///    sûre remplace une donnée héritée d'une autre édition.
@MainActor
enum EditionsLocales {

    /// UNE requête pour toute la série : le catalogue renvoie tous les tomes
    /// d'un coup, on les matche strictement et on remplit tout — série,
    /// couvertures des tomes, résumé. Persisté ensuite : plus jamais redemandé.
    static func rafraichirSerieComplete(_ serie: Serie, langue: String) async {
        let referenceBase = Tomaison.decomposer(
            serie.noms["en"] ?? serie.nomRomaji ?? serie.nom
        ).base
        guard referenceBase.count >= 2 else { return }

        let resultats = await AgregateurMetadonnees.partage
            .rechercherLivres(referenceBase, langue: langue)

        // Ne garder que les éditions FIABLES de CETTE série.
        var parNumero: [Int: ResultatRecherche] = [:]
        var horsNumero: ResultatRecherche?
        for resultat in resultats {
            guard estFiable(resultat, langue: langue) else { continue }
            let (base, numero) = Tomaison.decomposer(resultat.titre)
            guard Tomaison.memeSerie(base, referenceBase) else { continue }
            if let numero {
                if parNumero[numero] == nil { parNumero[numero] = resultat }
            } else if horsNumero == nil {
                horsNumero = resultat
            }
        }

        // La série elle-même : nom local, couverture du tome 1, résumé.
        let representant = parNumero[1]
            ?? parNumero.sorted { $0.key < $1.key }.first?.value
            ?? horsNumero
        if let representant {
            let base = Tomaison.decomposer(representant.titre).base
            if !Titres.estNonLatin(base) || Titres.litScriptNonLatin(langue) {
                serie.noms[langue] = base
            }
            if let couverture = representant.couvertureURL {
                serie.couvertureLocaleURL = couverture
            }
            if serie.resumeLocal == nil,
               let resume = representant.resume, !resume.isEmpty {
                serie.resumeLocal = resume
            }
        }

        // Chaque tome reçoit SA couverture — celle de son édition locale.
        for tome in serie.tomesTries {
            guard let edition = parNumero[tome.numero] else { continue }
            if let couverture = edition.couvertureURL {
                tome.couvertureURL = couverture
            }
            tome.titre = edition.titre
            if tome.pages == nil { tome.pages = edition.pages }
            if tome.isbn == nil { tome.isbn = edition.isbn }
        }
    }

    /// Un livre isolé : même logique, même prudence.
    static func rafraichirOeuvre(_ oeuvre: Oeuvre, langue: String) async {
        let reference = oeuvre.titres["en"] ?? oeuvre.titreRomaji ?? oeuvre.titreOriginal
        let referenceBase = Tomaison.decomposer(reference).base
        guard referenceBase.count >= 2 else { return }

        let resultats = await AgregateurMetadonnees.partage
            .rechercherLivres(referenceBase, langue: langue)

        let candidat = resultats.first { resultat in
            guard estFiable(resultat, langue: langue),
                  resultat.couvertureURL != nil else { return false }
            return Tomaison.memeSerie(
                Tomaison.decomposer(resultat.titre).base,
                referenceBase
            )
        }
        guard let candidat else { return }

        if oeuvre.titres[langue] == nil,
           !Titres.estNonLatin(candidat.titre) || Titres.litScriptNonLatin(langue) {
            oeuvre.titres[langue] = candidat.titre
        }
        if let couverture = candidat.couvertureURL {
            oeuvre.couvertureLocaleURL = couverture
        }
        if oeuvre.resumeLocal == nil, let resume = candidat.resume, !resume.isEmpty {
            oeuvre.resumeLocal = resume
        }
        if oeuvre.pages == nil { oeuvre.pages = candidat.pages }
    }

    /// Une édition est fiable si elle vient du catalogue du pays du lecteur
    /// (Apple Books) ou si sa langue est explicitement celle du lecteur.
    private static func estFiable(_ resultat: ResultatRecherche, langue: String) -> Bool {
        resultat.source == "Apple Books" || resultat.langue == langue
    }
}

import Foundation
import SwiftData

/// Va chercher l'édition publiée dans la langue du lecteur — nom, couverture,
/// quatrième de couverture — et l'applique. Appelé automatiquement : à l'ajout,
/// au lancement (rattrapage) et à l'ouverture d'une fiche incomplète.
/// L'utilisateur n'a JAMAIS à demander la bonne édition : elle arrive seule.
@MainActor
enum EditionsLocales {

    static func rafraichirSerie(_ serie: Serie, langue: String) async {
        let reference = Tomaison.decomposer(
            serie.noms["en"] ?? serie.nomRomaji ?? serie.nom
        ).base
        guard !reference.isEmpty else { return }

        let editions = await AgregateurMetadonnees.partage
            .rechercherLivres(reference, langue: langue)
        guard let locale = editions.first(where: { $0.langue == langue && $0.couvertureURL != nil })
            ?? editions.first(where: { $0.couvertureURL != nil })
        else { return }

        serie.noms[langue] = Tomaison.decomposer(locale.titre).base
        serie.couvertureLocaleURL = locale.couvertureURL
        if serie.resumeLocal == nil, let resume = locale.resume, !resume.isEmpty {
            serie.resumeLocal = resume
        }
    }

    static func rafraichirOeuvre(_ oeuvre: Oeuvre, langue: String) async {
        let reference = oeuvre.titres["en"] ?? oeuvre.titreRomaji ?? oeuvre.titreOriginal
        guard !reference.isEmpty else { return }

        let editions = await AgregateurMetadonnees.partage
            .rechercherLivres(reference, langue: langue)
        guard let locale = editions.first(where: { $0.langue == langue && $0.couvertureURL != nil })
            ?? editions.first(where: { $0.couvertureURL != nil })
        else { return }

        if oeuvre.titres[langue] == nil,
           !Titres.estNonLatin(locale.titre) || Titres.litScriptNonLatin(langue) {
            oeuvre.titres[langue] = locale.titre
        }
        oeuvre.couvertureLocaleURL = locale.couvertureURL
        if oeuvre.resumeLocal == nil, let resume = locale.resume, !resume.isEmpty {
            oeuvre.resumeLocal = resume
        }
    }
}

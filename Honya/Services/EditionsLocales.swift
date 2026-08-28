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
/// 4. Le titre seul ne désigne personne. « Instinct » est le livre d'Inoxtag
///    et un manuel de survie chez Amphora ; l'auteur départage, comme le
///    ferait un libraire.
@MainActor
enum EditionsLocales {
    /// Plusieurs tomes ajoutés en rafale ne doivent lancer qu'une requête de
    /// série. Une requête pour une NOUVELLE langue remplace toutefois l'ancienne :
    /// sans ce jeton, une réponse française lente pouvait revenir après le passage
    /// au japonais et repeindre la fiche avec l'ancienne édition.
    private struct Enrichissement {
        let langue: String
        let profonde: Bool
        let jeton: UUID
    }

    private static var enrichissementsSeries: [ObjectIdentifier: Enrichissement] = [:]
    private static var enrichissementsOeuvres: [ObjectIdentifier: Enrichissement] = [:]

    /// UNE requête pour toute la série : le catalogue renvoie tous les tomes
    /// d'un coup, on les matche strictement et on remplit tout — série,
    /// couvertures des tomes, résumé. Persisté ensuite : plus jamais redemandé.
    /// Trois rayons remplis en gratuit. Une série qui en a déjà bénéficié
    /// garde le sien : on ne reprend jamais un acquis.
    private static func reserverRayonSiAutorise(_ serie: Serie) -> Bool {
        if serie.rayonEnrichi {
            if !serie.rayonHonyaPlus || Droits.partage.plus {
                serie.rayonRefuse = false
                return true
            }
            // Le contenu acquis n'est jamais supprimé. Après expiration,
            // ce rayon Honya+ peut toutefois devenir l'un des trois gratuits.
            if let contexte = serie.modelContext,
               let gratuits = try? contexte.fetchCount(
                   FetchDescriptor<Serie>(predicate: #Predicate {
                       $0.rayonEnrichi && !$0.rayonHonyaPlus
                   })
               ), gratuits < Limites.seriesCompletes {
                serie.rayonHonyaPlus = false
                serie.rayonRefuse = false
                return true
            }
            serie.rayonRefuse = true
            return false
        }

        if Droits.partage.plus {
            serie.rayonEnrichi = true
            serie.rayonHonyaPlus = true
            serie.rayonRefuse = false
            return true
        }

        // Sans contexte, impossible de prouver qu'une place gratuite reste.
        // Toutes les séries de l'application sont insérées avant cette passe.
        guard let contexte = serie.modelContext else {
            serie.rayonRefuse = true
            return false
        }
        guard let deja = try? contexte.fetchCount(
            FetchDescriptor<Serie>(predicate: #Predicate {
                $0.rayonEnrichi && !$0.rayonHonyaPlus
            })
        ) else {
            // Une erreur de lecture ne doit jamais transformer le quota en
            // accès illimité. Honya+ reste, lui, indépendant de ce compteur.
            serie.rayonRefuse = true
            return false
        }
        guard deja < Limites.seriesCompletes else {
            serie.rayonRefuse = true
            return false
        }

        // La vérification et la réservation sont synchrones sur MainActor :
        // plusieurs recherches qui reviennent ensemble ne peuvent pas toutes
        // observer la troisième place avant qu'elle soit prise.
        serie.rayonEnrichi = true
        serie.rayonHonyaPlus = false
        serie.rayonRefuse = false
        return true
    }

    static func rafraichirSerieComplete(
        _ serie: Serie, langue: String, profonde: Bool = false
    ) async {
        let identifiant = ObjectIdentifier(serie)
        if let courant = enrichissementsSeries[identifiant],
           courant.langue == langue,
           (courant.profonde || !profonde) {
            return
        }
        let jeton = UUID()
        enrichissementsSeries[identifiant] = Enrichissement(
            langue: langue, profonde: profonde, jeton: jeton
        )
        defer {
            if enrichissementsSeries[identifiant]?.jeton == jeton {
                enrichissementsSeries.removeValue(forKey: identifiant)
            }
        }

        var nomsConnus = Array(serie.noms.values) + serie.nomsAlternatifs
        nomsConnus.append(serie.nom)
        if let romaji = serie.nomRomaji { nomsConnus.append(romaji) }
        let referenceBase = Tomaison.decomposer(
            serie.noms[langue] ?? serie.noms["en"] ?? serie.nomRomaji ?? serie.nom
        ).base
        let basesConnues = nomsConnus.map { Tomaison.decomposer($0).base }
        guard referenceBase.count >= 2 else { return }
        serie.dernierEssaiEditionLocale = Date()

        let resultats: [ResultatRecherche]
        if profonde {
            resultats = await AgregateurMetadonnees.partage
                .rechercherEditionsSerie(referenceBase, langue: langue)
        } else {
            resultats = await AgregateurMetadonnees.partage
                .rechercherLivres(referenceBase, langue: langue)
        }
        guard !Task.isCancelled,
              enrichissementsSeries[identifiant]?.jeton == jeton
        else { return }

        // Ne garder que les éditions FIABLES de CETTE série.
        var parNumero: [Int: ResultatRecherche] = [:]
        var horsNumero: ResultatRecherche?
        let auteurs = [serie.auteur].compactMap { $0 }
        for resultat in resultats {
            guard estFiable(resultat, langue: langue),
                  memeAuteur(resultat, que: auteurs) else { continue }
            let (base, numero) = Tomaison.decomposer(resultat.titre)
            guard basesConnues.contains(where: { Tomaison.memeSerie(base, $0) })
            else { continue }
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
            if Titres.estLisible(base, langue: langue) {
                serie.noms[langue] = base
            }
            if let couverture = representant.couvertureURL {
                serie.couvertureLocaleURL = couverture
                serie.attributionCouverture = representant.attributionCouverture
            }
            if serie.resumeLocal == nil,
               let resume = representant.resume, !resume.isEmpty {
                serie.resumeLocal = resume
            }
        }

        // Chaque tome reçoit SA couverture — celle de son édition locale.
        for tome in serie.tomesTries {
            guard let edition = parNumero[tome.numero] else { continue }
            // Un ISBN déjà présent désigne une édition précise, généralement
            // celle qui vient d'être scannée. Une recherche par titre ne peut
            // l'enrichir que si elle rend exactement le même code-barres ; un
            // ebook voisin ne remplace jamais la couverture papier.
            if let exact = tome.isbn.flatMap(ISBNUtil.canonique) {
                guard edition.isbn.flatMap(ISBNUtil.canonique) == exact else { continue }
            }
            if let couverture = edition.couvertureURL {
                tome.couvertureURL = couverture
                tome.attributionCouverture = edition.attributionCouverture
            }
            tome.titre = edition.titre
            tome.dateSortie = edition.dateSortie ?? tome.dateSortie
            if tome.pages == nil { tome.pages = edition.pages }
            if tome.isbn == nil { tome.isbn = edition.isbn }
        }

        // Le rayon COMPLET : tout tome du catalogue absent de la série est
        // créé, grisé tant qu'il n'est pas possédé — précommandes comprises.
        //
        // C'est LE geste que Honya+ ouvre en grand : le gratuit en remplit
        // trois, au-delà on ajoute ses tomes à la main. Les éditions locales,
        // elles, restent gratuites — on ne dégrade pas ce qui est déjà là.
        // Le total AniList décrit l'édition d'origine. Une édition locale peut
        // regrouper ou découper autrement ses volumes (omnibus, perfect, BD).
        // On ne matérialise donc que les numéros réellement confirmés par le
        // catalogue local : jamais de tomes fantômes déduits de 1...N.
        let totalAnnonce = serie.tomesTotal.flatMap { $0 > 0 ? $0 : nil }
        guard !parNumero.isEmpty else { return }
        guard reserverRayonSiAutorise(serie) else { return }

        let numerosDuRayon = Set(parNumero.keys)

        let numerosConnus = Set(serie.tomes.map(\.numero))
        for numero in numerosDuRayon.subtracting(numerosConnus).sorted() {
            let tome = Tome(numero: numero)
            if let edition = parNumero[numero] {
                tome.titre = edition.titre
                tome.couvertureURL = edition.couvertureURL
                tome.attributionCouverture = edition.attributionCouverture
                tome.pages = edition.pages
                tome.isbn = edition.isbn
                tome.dateSortie = edition.dateSortie
            }
            serie.tomes.append(tome)
        }

        // Une édition numérotée au-delà du total annoncé prouve que ce total
        // est périmé ; le plus grand numéro trouvé n'est pas un nouveau total.
        if let totalAnnonce,
           let maxCatalogue = parNumero.keys.max(),
           maxCatalogue > totalAnnonce {
            serie.tomesTotal = nil
        }

        // Même un total explicite venu de l'œuvre originale ne ferme le rayon
        // physique que si le catalogue de CETTE langue confirme chaque numéro.
        if let total = serie.tomesTotal, total > 0 {
            serie.rayonComplet = (1...total).allSatisfy {
                parNumero[$0] != nil
            }
        } else {
            serie.rayonComplet = false
        }

        // Les précommandes du catalogue donnent la prochaine sortie, tout seul.
        let aVenir = parNumero
            .compactMap { numero, edition -> (Int, Date)? in
                guard let date = edition.dateSortie,
                      DateCivile.estAVenir(date) else { return nil }
                return (numero, date)
            }
            .min { $0.1 < $1.1 }
        if let (numero, date) = aVenir,
           numero != serie.prochaineSortieNumero || date != serie.prochaineSortieDate {
            // Les catalogues peuvent corriger une date de précommande. Si le
            // lecteur suit déjà cette sortie, l'ancienne requête doit partir
            // avant que ses valeurs soient remplacées.
            let devaitReplanifier = serie.rappelActive
            if devaitReplanifier {
                NotificationsService.annulerRappel(pour: serie)
                // Dès cet instant il n'existe plus de requête système. Si la
                // tâche est annulée avant la suite, la cloche doit le refléter.
                serie.rappelActive = false
            }
            serie.prochaineSortieNumero = numero
            serie.prochaineSortieDate = date
            if devaitReplanifier {
                guard !Task.isCancelled,
                      enrichissementsSeries[identifiant]?.jeton == jeton
                else { return }
                serie.rappelActive = await NotificationsService.planifierRappelSortie(
                    pour: serie, langue: langue
                )
            }
        } else if case nil = aVenir,
                  let ancienneDate = serie.prochaineSortieDate,
                  !DateCivile.estAujourdhuiOuApres(ancienneDate) {
            // Une échéance livrée ne reste pas éternellement « prochaine ».
            // On ne retire qu'une date déjà passée : une saisie manuelle
            // encore future est conservée si le catalogue est incomplet.
            if serie.rappelActive {
                NotificationsService.annulerRappel(pour: serie)
            }
            serie.rappelActive = false
            serie.prochaineSortieNumero = nil
            serie.prochaineSortieDate = nil
        }
    }

    /// Un livre isolé : même logique, même prudence.
    static func rafraichirOeuvre(_ oeuvre: Oeuvre, langue: String) async {
        let identifiant = ObjectIdentifier(oeuvre)
        if enrichissementsOeuvres[identifiant]?.langue == langue { return }
        let jeton = UUID()
        enrichissementsOeuvres[identifiant] = Enrichissement(
            langue: langue, profonde: false, jeton: jeton
        )
        defer {
            if enrichissementsOeuvres[identifiant]?.jeton == jeton {
                enrichissementsOeuvres.removeValue(forKey: identifiant)
            }
        }

        let reference = oeuvre.titres[langue]
            ?? oeuvre.titres["en"] ?? oeuvre.titreRomaji ?? oeuvre.titreOriginal
        let referenceBase = Tomaison.decomposer(reference).base
        var titresConnus = Array(oeuvre.titres.values)
        titresConnus.append(oeuvre.titreOriginal)
        if let romaji = oeuvre.titreRomaji { titresConnus.append(romaji) }
        let basesConnues = titresConnus.map { Tomaison.decomposer($0).base }
        guard referenceBase.count >= 2 else { return }
        oeuvre.dernierEssaiEditionLocale = Date()

        let resultats = await AgregateurMetadonnees.partage
            .rechercherLivres(referenceBase, langue: langue)
        guard !Task.isCancelled,
              enrichissementsOeuvres[identifiant]?.jeton == jeton
        else { return }

        let candidat = resultats.first { resultat in
            guard estFiable(resultat, langue: langue),
                  resultat.couvertureURL != nil,
                  memeAuteur(resultat, que: oeuvre.auteurs) else { return false }
            // Un exemplaire scanné désigne une édition physique précise. Une
            // recherche par titre ne peut pas lui greffer la couverture d'un
            // ebook ou d'un autre tirage, même si le titre et l'auteur collent.
            if let exact = oeuvre.exemplaire?.isbn.flatMap(ISBNUtil.canonique) {
                guard resultat.isbn.flatMap(ISBNUtil.canonique) == exact else {
                    return false
                }
            }
            let base = Tomaison.decomposer(resultat.titre).base
            return basesConnues.contains { Tomaison.memeSerie(base, $0) }
        }
        guard let candidat else { return }

        if oeuvre.titres[langue] == nil,
           Titres.estLisible(candidat.titre, langue: langue) {
            oeuvre.titres[langue] = candidat.titre
        }
        if let couverture = candidat.couvertureURL {
            oeuvre.couvertureLocaleURL = couverture
            oeuvre.attributionCouverture = candidat.attributionCouverture
        }
        if oeuvre.resumeLocal == nil, let resume = candidat.resume, !resume.isEmpty {
            oeuvre.resumeLocal = resume
        }
        if oeuvre.pages == nil { oeuvre.pages = candidat.pages }
    }

    /// Une édition est fiable uniquement si sa langue est explicite. Le
    /// storefront Apple est un pays de vente, pas une garantie linguistique :
    /// le store français contient aussi des livres anglais.
    private static func estFiable(_ resultat: ResultatRecherche, langue: String) -> Bool {
        resultat.langue == langue
    }

    /// Ce candidat est-il du même auteur ?
    ///
    /// Deux livres différents portent parfois exactement le même titre. Le
    /// titre seul ne désigne donc personne : c'est l'auteur qui tranche. On
    /// compare des mots plutôt que des chaînes entières, parce que les
    /// catalogues écrivent « Rowling, J. K. » là où un autre écrit
    /// « J.K. Rowling » — un seul mot en commun suffit à reconnaître.
    ///
    /// Si une seule notice omet l'auteur, on refuse la fusion : une couverture
    /// absente se répare, une couverture d'homonyme mine la confiance dans le
    /// code-barres scanné.
    static func memeAuteur(_ candidat: ResultatRecherche, que auteurs: [String]) -> Bool {
        AuteursUtil.correspondent(candidat.auteurs, auteurs)
    }
}

import Foundation

/// L'étal du libraire : rayons thématiques issus des sources autorisées et,
/// uniquement si son parcours promotionnel a été déclaré conforme, classements
/// Apple. Tout arrive dans la langue du lecteur, comme le reste de l'app.
@MainActor
enum Decouverte {

    // MARK: - Suggestions localisées

    /// Livres qui montent réellement en ce moment dans l'activité Open
    /// Library, résolus vers une édition de la langue du lecteur. Le signal de
    /// popularité est mondial ; les rayons thématiques ci-dessous réinjectent
    /// ensuite les catalogues et éditions propres à son marché.
    static func tendances(langue: String) async -> [ResultatRecherche] {
        let code = langue.lowercased()
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .first.map(String.init) ?? langue.lowercased()
        let cle = "tendances|" + code
        if let connues = await CacheRecherche.partage.lire(cle) {
            return connues
        }
        let brutes = (try? await OpenLibraryProvider().tendances(
            langue: code,
            limite: 24
        )) ?? []
        let presentees = Array(parSerie(brutes).prefix(18))
        await CacheRecherche.partage.ecrire(cle, presentees)
        return presentees
    }

    /// Un étal vivant construit uniquement avec des éditions dont la langue est
    /// explicitement celle du lecteur. `gratuits` sépare simplement deux jeux
    /// de requêtes afin que l'accueil obtienne un mur varié ; aucune notion de
    /// prix n'est affichée ni inventée.
    static func classement(gratuits: Bool, langue: String) async -> [ResultatRecherche] {
        let tous = termesSuggestions(pour: langue)
        let termes = gratuits
            ? Array(tous.dropFirst(tous.count / 2))
            : Array(tous.prefix(tous.count / 2))
        var trouves: [ResultatRecherche] = []
        let code = langue.lowercased()
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .first.map(String.init) ?? langue.lowercased()

        func presentables(_ resultats: [ResultatRecherche]) -> [ResultatRecherche] {
            parSerie(resultats.filter { resultat in
                guard resultat.couvertureURL != nil,
                      let langueResultat = resultat.langue else { return false }
                let locale = langueResultat.lowercased()
                    .split(whereSeparator: { $0 == "-" || $0 == "_" })
                    .first.map(String.init) ?? langueResultat.lowercased()
                return locale == code
            })
        }

        // Deux appels à la fois au maximum : assez rapide pour l'écran, sans
        // transformer chaque lancement en rafale contre les catalogues ouverts.
        for paire in stride(from: 0, to: termes.count, by: 2) {
            guard !Task.isCancelled else { return [] }
            let premier = termes[paire]
            let second = paire + 1 < termes.count ? termes[paire + 1] : nil
            if let second {
                async let a = rayonBrut(premier, langue: langue)
                async let b = rayonBrut(second, langue: langue)
                let paireTrouvee = await (a, b)
                trouves += paireTrouvee.0 + paireTrouvee.1
            } else {
                trouves += await rayonBrut(premier, langue: langue)
            }
            // Douze couvertures suffisent à la rangée Recherche ; les deux
            // moitiés réunies donnent les vingt-quatre cases du mur d'accueil.
            // Ne pas lancer une troisième requête quand les deux premières ont
            // déjà rempli leur rayon rend les vraies images visibles plus vite.
            let deja = presentables(trouves)
            if deja.count >= 12 { return Array(deja.prefix(12)) }
        }

        return Array(presentables(trouves).prefix(12))
    }

    /// Les libellés sont cherchés dans le catalogue de traductions de l'app
    /// avec la langue D'ÉDITION choisie. Cela reste correct lorsqu'un iPhone
    /// français cherche volontairement des livres allemands ou japonais, et le
    /// même tableau sert de repli visible dans l'écran Recherche.
    static func termesSuggestions(pour langue: String) -> [String] {
        let code = langue.lowercased().replacingOccurrences(of: "_", with: "-")
        // Le sélecteur d'éditions utilise les codes bibliographiques courts,
        // tandis que le catalogue de l'app distingue ces variantes régionales.
        let identifiantLocale: String
        switch code.split(separator: "-").first.map(String.init) ?? code {
        case "pt": identifiantLocale = "pt-BR"
        case "zh": identifiantLocale = "zh-Hans"
        default: identifiantLocale = code
        }
        let locale = Locale(identifier: identifiantLocale)
        let termes = [
            String(localized: "Manga", locale: locale),
            String(localized: "BD & Comics", locale: locale),
            String(localized: "Jeunesse", locale: locale),
            String(localized: "Romance", locale: locale),
            String(localized: "SF & Fantasy", locale: locale),
            String(localized: "Polar", locale: locale),
        ]
        var vus = Set<String>()
        return termes.filter { terme in
            let propre = terme.trimmingCharacters(in: .whitespacesAndNewlines)
            return !propre.isEmpty
                && vus.insert(TexteUtil.normaliser(propre)).inserted
        }
    }

    // MARK: - Rayons thématiques (recherche catalogue)

    /// Les résultats bruts d'un rayon — mêmes requêtes que la recherche, donc
    /// même cache et même file d'attente.
    static func rayonBrut(_ terme: String, langue: String) async -> [ResultatRecherche] {
        await AgregateurMetadonnees.partage.rechercherLivres(terme, langue: langue)
    }

    /// Un rayon présentable : un seul représentant par série (pas dix tomes du
    /// même titre), couverture obligatoire.
    static func parSerie(_ resultats: [ResultatRecherche]) -> [ResultatRecherche] {
        var vues = Set<String>()
        return resultats.filter { resultat in
            guard resultat.couvertureURL != nil else { return false }
            let base = TexteUtil.normaliser(Tomaison.decomposer(resultat.titre).base)
            guard !base.isEmpty else { return false }
            return vues.insert(base).inserted
        }
    }

    /// Les parutions à venir parmi des résultats déjà chargés (précommandes).
    static func aParaitre(_ resultats: [ResultatRecherche]) -> [ResultatRecherche] {
        resultats
            .filter {
                $0.couvertureURL != nil
                    && $0.dateSortie.map { DateCivile.estAVenir($0) } == true
            }
            .sorted { ($0.dateSortie ?? .distantFuture) < ($1.dateSortie ?? .distantFuture) }
    }

}

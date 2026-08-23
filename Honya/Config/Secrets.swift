import Foundation

// FICHIER GÉNÉRÉ PAR LA CI AU MOMENT DU BUILD.
//
// La version committée dans le dépôt est volontairement VIDE : les vraies
// valeurs vivent dans des variables d'environnement chiffrées de Codemagic
// (GOOGLE_BOOKS_API_KEY, SUPABASE_URL, SUPABASE_ANON_KEY) et ne sont écrites
// ici que sur la machine de build, juste avant la compilation. Elles
// n'apparaissent donc ni dans le code source, ni dans l'historique git, ni
// dans une interface de l'app.
enum Secrets {
    static let cleGoogleBooks = ""
    /// Racine de l'API du projet Supabase de Honya (distinct de tout autre projet).
    static let supabaseURL = ""
    /// Clé publique « anon » : elle ne donne accès qu'à ce que les règles du
    /// projet autorisent, jamais aux données d'un autre lecteur.
    static let supabaseCleAnon = ""
}

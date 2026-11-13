import Foundation

/// Évite de réécrire un fichier de cache dont le contenu n'a pas changé (environ 96 écritures par jour).
/// La date de modification est quand même remise à maintenant : l'heure « mis à jour » affichée
/// au démarrage hors ligne vient de cette date.
public enum SkipIdenticalWrite {
    /// Appelle `write` seulement si `url` n'existe pas ou diffère de `data`.
    public static func perform(_ data: Data, at url: URL, write: () throws -> Void) throws {
        if let current = try? Data(contentsOf: url), current == data {
            try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
            return
        }
        try write()
    }
}

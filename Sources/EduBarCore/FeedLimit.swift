/// Plafond du flux iCal téléchargé : un an d'Edusign pèse environ 0,3 Mo, 5 Mo laissent de la marge
/// sans qu'un serveur hostile puisse faire gonfler la mémoire de l'app.
public enum FeedLimit {
    public static let maxBytes = 5_000_000

    /// Taille annoncée par le serveur (`expectedContentLength`, -1 si inconnue).
    public static func declaredTooLarge(expected: Int64) -> Bool {
        expected > Int64(maxBytes)
    }

    /// Octets déjà reçus.
    public static func exceeded(received: Int) -> Bool {
        received > maxBytes
    }
}

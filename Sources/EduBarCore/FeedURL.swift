import Foundation

public enum FeedURL {
    /// Accepte `webcal://` (converti en `https://`) ou `https://`, avec un hôte. Sinon `nil`.
    public static func normalize(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.lowercased().hasPrefix("webcal://") { s = "https://" + s.dropFirst("webcal://".count) }
        guard let url = URL(string: s), url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty
        else { return nil }
        return url
    }

    /// URL sans ses paramètres (ils contiennent les jetons d'accès), pour les messages et logs.
    public static func redacted(_ url: URL) -> String {
        guard var c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return "?" }
        let hadQuery = c.query != nil
        c.query = nil
        c.fragment = nil
        return (c.string ?? "?") + (hadQuery ? "?…" : "")
    }
}

import Foundation

/// Identifiants myGES : login et mot de passe.
public struct MyGESCredentials: Sendable, Equatable {
    public let login: String
    public let password: String

    public init(login: String, password: String) {
        self.login = login
        self.password = password
    }
}

/// Fichier des identifiants (0600, dossier 0700), à côté de `feed-url`.
/// Format : le login sur la 1re ligne, le mot de passe sur la 2e (tout sauf un saut de ligne).
public enum MyGESCredentialsFile {
    public static var standard: FeedFile {
        FeedFile(directory: FeedFile.standard.url.deletingLastPathComponent(), name: "myges-credentials")
    }

    /// Jusqu'à la première 1.0.0, `.standard` ici désignait `FeedFile.standard` (le fichier `feed-url`) :
    /// les identifiants y étaient écrits à la place de l'URL iCal. On les déplace une fois.
    /// Renvoie vrai si une migration a eu lieu.
    @discardableResult
    public static func migrateFromFeedFile(feed: FeedFile = FeedFile.standard, to file: FeedFile = MyGESCredentialsFile.standard) -> Bool {
        guard read(file) == nil, let creds = read(feed), !creds.login.contains("://") else { return false }
        guard (try? write(creds, to: file)) != nil else { return false }
        feed.remove()
        return true
    }

    public static func read(_ file: FeedFile = MyGESCredentialsFile.standard) -> MyGESCredentials? {
        guard let raw = try? String(contentsOf: file.url, encoding: .utf8) else { return nil }
        let lines = raw.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        guard lines.count == 2 else { return nil }
        let login = lines[0].trimmingCharacters(in: .whitespacesAndNewlines)
        var password = String(lines[1])
        if password.hasSuffix("\r") { password.removeLast() }
        guard !login.isEmpty, !password.isEmpty else { return nil }
        return MyGESCredentials(login: login, password: password)
    }

    /// Un saut de ligne dans le login ou le mot de passe casserait le format : refusé.
    public static func write(_ creds: MyGESCredentials, to file: FeedFile = MyGESCredentialsFile.standard) throws {
        let login = creds.login.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !login.isEmpty, !creds.password.isEmpty,
              !login.contains("\n"), !creds.password.contains("\n"), !creds.password.contains("\r")
        else { throw CocoaError(.fileWriteInvalidFileName) }
        try file.writeExact(login + "\n" + creds.password)
    }

    public static func remove(from file: FeedFile = MyGESCredentialsFile.standard) {
        file.remove()
    }
}

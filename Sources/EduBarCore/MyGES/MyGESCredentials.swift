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

    public static func read(_ file: FeedFile = .standard) -> MyGESCredentials? {
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
    public static func write(_ creds: MyGESCredentials, to file: FeedFile = .standard) throws {
        let login = creds.login.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !login.isEmpty, !creds.password.isEmpty,
              !login.contains("\n"), !creds.password.contains("\n"), !creds.password.contains("\r")
        else { throw CocoaError(.fileWriteInvalidFileName) }
        try file.writeExact(login + "\n" + creds.password)
    }

    public static func remove(from file: FeedFile = .standard) {
        file.remove()
    }
}

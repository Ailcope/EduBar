import Foundation

/// L'URL du flux, dans un fichier lisible par l'utilisateur seul (0600, dossier 0700).
/// Remplace le Trousseau : l'app est signée ad-hoc, chaque version y était vue comme une nouvelle app
/// et perdait l'accès à l'URL après une mise à jour.
public struct FeedFile: Sendable {
    public let url: URL

    public init(directory: URL) {
        url = directory.appending(path: "feed-url")
    }

    /// `~/Library/Application Support/EduBar/feed-url`
    public static var standard: FeedFile {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return FeedFile(directory: support.appending(path: "EduBar"))
    }

    public func read() -> String? {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    public func write(_ value: String) throws {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        // Créé vide en 0600 avant d'y écrire : l'URL n'est jamais lisible par les autres comptes.
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data(value.trimmingCharacters(in: .whitespacesAndNewlines).utf8))
    }

    public func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}

import Foundation

/// L'URL du flux, dans un fichier lisible par l'utilisateur seul (0600, dossier 0700).
/// Remplace le Trousseau : l'app est signée ad-hoc, chaque version y était vue comme une nouvelle app
/// et perdait l'accès à l'URL après une mise à jour.
public struct FeedFile: Sendable {
    public let url: URL

    /// Exclu de Time Machine : le mot de passe myGES et les URL privées ne doivent pas partir sur un disque de
    /// sauvegarde. Grades et historique restent sauvegardés (l'utilisateur veut pouvoir les restaurer).
    public let excludedFromBackup: Bool

    /// Par défaut, l'exclusion est décidée d'après le nom : `feed-url`, `friend-url*`, `myges-credentials`.
    public init(directory: URL, name: String = "feed-url", excludedFromBackup: Bool? = nil) {
        url = directory.appending(path: name)
        self.excludedFromBackup = excludedFromBackup
            ?? (name == "feed-url" || name == "myges-credentials" || name.hasPrefix("friend-url"))
    }

    /// `~/Library/Application Support/EduBar/feed-url`
    public static var standard: FeedFile {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return FeedFile(directory: support.appending(path: "EduBar"))
    }

    /// Nombre de potes pour les pauses communes.
    public static let friendSlots = 3

    /// Calendrier d'un pote (pauses communes), à côté du tien : `friend-url`, `friend-url-2`, `friend-url-3`.
    public static func friend(_ slot: Int) -> FeedFile {
        FeedFile(directory: standard.url.deletingLastPathComponent(), name: slot == 0 ? "friend-url" : "friend-url-\(slot + 1)")
    }

    /// Pose l'exclusion de Time Machine sur un fichier sensible déjà présent (écrit par une ancienne version).
    /// Sans effet s'il est déjà exclu, absent, ou non sensible.
    public func protectExisting() {
        guard excludedFromBackup,
              let current = try? url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup,
              !current
        else { return }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var target = url
        try? target.setResourceValues(values)
    }

    public func read() -> String? {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        protectExisting()
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    public func write(_ value: String) throws {
        try writeExact(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Comme `write`, sans retirer les espaces (un mot de passe peut en porter au bord).
    public func writeExact(_ value: String) throws {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        // Fichier temporaire du même dossier, créé en 0600 avant d'y écrire : le contenu n'est jamais lisible
        // par les autres comptes. Puis rename atomique : le fichier final n'est jamais vide ni tronqué.
        let tmp = dir.appending(path: ".\(url.lastPathComponent).tmp-\(UUID().uuidString)")
        guard fm.createFile(atPath: tmp.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: tmp.path])
        }
        do {
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tmp.path)
            let handle = try FileHandle(forWritingTo: tmp)
            defer { try? handle.close() }
            try handle.write(contentsOf: Data(value.utf8))
            try handle.synchronize()
            // Posé sur le temporaire avant le rename : l'attribut suit le nouvel inode, sans fenêtre non exclue.
            if excludedFromBackup {
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                var target = tmp
                try target.setResourceValues(values)
            }
            if rename(tmp.path, url.path) != 0 {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        } catch {
            try? fm.removeItem(at: tmp)
            throw error
        }
    }

    public func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}

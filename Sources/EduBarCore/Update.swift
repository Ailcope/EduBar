import CryptoKit
import Foundation

/// Numéro de version "1.2.3" (préfixe "v" accepté), comparé partie par partie.
public struct Version: Comparable, Hashable, Sendable, CustomStringConvertible {
    public let parts: [Int]

    public init?(_ raw: String) {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        let parts = s.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil && $0! >= 0 }) else { return nil }
        self.parts = parts.map { $0! }
    }

    public var description: String { parts.map(String.init).joined(separator: ".") }

    private func padded(to n: Int) -> [Int] { parts + Array(repeating: 0, count: max(0, n - parts.count)) }

    public static func == (a: Version, b: Version) -> Bool {
        let n = max(a.parts.count, b.parts.count)
        return a.padded(to: n) == b.padded(to: n)
    }

    public func hash(into h: inout Hasher) {
        var p = parts
        while p.last == 0 { p.removeLast() }
        h.combine(p)
    }

    public static func < (a: Version, b: Version) -> Bool {
        let n = max(a.parts.count, b.parts.count)
        return a.padded(to: n).lexicographicallyPrecedes(b.padded(to: n))
    }
}

/// Dernière release publiée sur GitHub.
public struct Release: Equatable, Sendable {
    public let version: Version
    public let page: URL
    public let dmg: URL?
    /// Archive de l'app, pour la mise à jour automatique.
    public let zip: URL?
    /// Empreinte SHA-256 du zip (hexadécimal minuscule), fournie par GitHub.
    public let zipSHA256: String?

    public init(version: Version, page: URL, dmg: URL?, zip: URL? = nil, zipSHA256: String? = nil) {
        self.version = version
        self.page = page
        self.dmg = dmg
        self.zip = zip
        self.zipSHA256 = zipSHA256
    }
}

public enum Update {
    public static let latestURL = URL(string: "https://api.github.com/repos/Ailcope/EduBar/releases/latest")!

    private struct Payload: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
            let digest: String?
        }
        let tag_name: String
        let html_url: URL
        let assets: [Asset]?
    }

    struct BadTag: Error {}

    /// Lit la réponse de `GET /repos/{owner}/{repo}/releases/latest`.
    public static func decode(_ data: Data) throws -> Release {
        let p = try JSONDecoder().decode(Payload.self, from: data)
        guard let version = Version(p.tag_name) else { throw BadTag() }
        let asset = { (ext: String) in p.assets?.first { $0.name.lowercased().hasSuffix(ext) } }
        let zip = asset(".zip")
        return Release(
            version: version, page: p.html_url, dmg: asset(".dmg")?.browser_download_url,
            zip: zip?.browser_download_url, zipSHA256: zip?.digest.flatMap(sha256Hex)
        )
    }

    /// "sha256:<64 hex>" → "<64 hex>" en minuscules ; tout autre format → nil.
    static func sha256Hex(_ digest: String) -> String? {
        guard digest.lowercased().hasPrefix("sha256:") else { return nil }
        let hex = digest.dropFirst(7).lowercased()
        return hex.count == 64 && hex.allSatisfy(\.isHexDigit) ? hex : nil
    }

    /// Empreinte SHA-256 d'un fichier, en hexadécimal minuscule.
    public static func sha256(of file: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: file)).map { String(format: "%02x", $0) }.joined()
    }

    /// Identifiant et version d'un bundle .app, lus dans son Info.plist.
    public static func bundleInfo(at app: URL) -> (id: String, version: Version)? {
        let plist = app.appending(path: "Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let id = info["CFBundleIdentifier"] as? String,
              let version = (info["CFBundleShortVersionString"] as? String).flatMap(Version.init)
        else { return nil }
        return (id, version)
    }

    /// La release si elle est plus récente que la version installée (inconnue → jamais).
    public static func available(_ release: Release, current: String?) -> Release? {
        guard let current = current.flatMap(Version.init), release.version > current else { return nil }
        return release
    }
}

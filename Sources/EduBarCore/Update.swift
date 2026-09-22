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
}

public enum Update {
    public static let latestURL = URL(string: "https://api.github.com/repos/Ailcope/EduBar/releases/latest")!

    private struct Payload: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
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
        let dmg = p.assets?.first { $0.name.lowercased().hasSuffix(".dmg") }?.browser_download_url
        return Release(version: version, page: p.html_url, dmg: dmg)
    }

    /// La release si elle est plus récente que la version installée (inconnue → jamais).
    public static func available(_ release: Release, current: String?) -> Release? {
        guard let current = current.flatMap(Version.init), release.version > current else { return nil }
        return release
    }
}

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
    /// Signature Ed25519 détachée du zip (asset `<nom du zip>.sig`), vérifiée avant toute extraction.
    public let zipSignature: URL?

    public init(version: Version, page: URL, dmg: URL?, zip: URL? = nil, zipSHA256: String? = nil, zipSignature: URL? = nil) {
        self.version = version
        self.page = page
        self.dmg = dmg
        self.zip = zip
        self.zipSHA256 = zipSHA256
        self.zipSignature = zipSignature
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
        // Tout ce qui se télécharge ou s'ouvre (zip, signature, dmg) : en HTTPS seulement.
        let assets = (p.assets ?? []).filter { isHTTPS($0.browser_download_url) }
        let asset = { (ext: String) in assets.first { $0.name.lowercased().hasSuffix(ext) } }
        let zip = asset(".zip")
        // Signature du zip : asset `<nom du zip>.sig`, nom exact.
        let signature = zip.flatMap { zip in assets.first { $0.name == zip.name + ".sig" } }
        return Release(
            version: version, page: p.html_url, dmg: asset(".dmg")?.browser_download_url,
            zip: zip?.browser_download_url, zipSHA256: zip?.digest.flatMap(sha256Hex),
            zipSignature: signature?.browser_download_url
        )
    }

    static func isHTTPS(_ url: URL) -> Bool { url.scheme?.lowercased() == "https" }

    /// "sha256:<64 hex>" → "<64 hex>" en minuscules ; tout autre format → nil.
    static func sha256Hex(_ digest: String) -> String? {
        guard digest.lowercased().hasPrefix("sha256:") else { return nil }
        let hex = digest.dropFirst(7).lowercased()
        return hex.count == 64 && hex.allSatisfy(\.isHexDigit) ? hex : nil
    }

    /// Empreinte SHA-256 d'un fichier, en hexadécimal minuscule.
    public static func sha256(of file: URL) throws -> String {
        sha256(of: try Data(contentsOf: file))
    }

    /// Empreinte SHA-256 d'octets, en hexadécimal minuscule.
    public static func sha256(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
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

    /// La release si elle est plus récente que la version installée (inconnue → jamais) et signée.
    /// Sans asset .sig, elle n'est ni installée ni proposée : rien n'invite à télécharger à la main
    /// un binaire non authentifié.
    public static func available(_ release: Release, current: String?) -> Release? {
        guard isNewer(release, than: current), release.zipSignature != nil else { return nil }
        return release
    }

    /// Vrai si la release est plus récente que la version installée (inconnue → jamais).
    public static func isNewer(_ release: Release, than current: String?) -> Bool {
        guard let current = current.flatMap(Version.init) else { return false }
        return release.version > current
    }

    // MARK: - Signature de publication

    /// Clé publique Ed25519 de publication (32 octets bruts, en base64). La clé privée reste hors du
    /// dépôt, de la CI et de GitHub (scripts/sign-release.swift, docs/deploiement.md).
    /// Une clé nulle (32 octets à zéro) est refusée par `publicKey(base64:)`.
    public static let releasePublicKey = "xNtMNNpK58dmggfrK/M6p7Fhmr1EogW9iGBFuXBIBNE="

    /// Taille maximale d'un fichier .sig : 89 octets par signature, de quoi en porter plusieurs
    /// pendant une rotation de clé.
    public static let maxSignatureBytes = 512

    /// Clé publique Ed25519 depuis son base64 (32 octets). Nil si mal formée ou nulle.
    public static func publicKey(base64: String) -> Curve25519.Signing.PublicKey? {
        guard let raw = Data(base64Encoded: base64.trimmingCharacters(in: .whitespacesAndNewlines)),
              raw.count == 32, raw.contains(where: { $0 != 0 })
        else { return nil }
        return try? Curve25519.Signing.PublicKey(rawRepresentation: raw)
    }

    /// Contenu d'un fichier .sig : une signature par ligne (base64 de 64 octets bruts, blancs tolérés).
    /// Plusieurs lignes servent à la rotation de clé : la release est signée par l'ancienne et la
    /// nouvelle. Vide si le fichier est vide, trop gros, ou si une seule ligne est mal formée.
    public static func signatures(fromFile data: Data) -> [Data] {
        guard data.count <= maxSignatureBytes, let text = String(data: data, encoding: .utf8) else { return [] }
        var result: [Data] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            guard let raw = Data(base64Encoded: trimmed), raw.count == 64 else { return [] }
            result.append(raw)
        }
        return result
    }

    /// Vrai seulement si `signatureFile` (contenu du .sig) porte une signature Ed25519 valide des octets
    /// exacts de `archive` par `publicKey` (par défaut la clé épinglée). Tout le reste est refusé.
    public static func verifySignature(_ signatureFile: Data, of archive: Data, publicKey: String = releasePublicKey) -> Bool {
        guard let key = Self.publicKey(base64: publicKey) else { return false }
        return signatures(fromFile: signatureFile).contains { key.isValidSignature($0, for: archive) }
    }
}

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
        let asset = { (ext: String) in p.assets?.first { $0.name.lowercased().hasSuffix(ext) } }
        // Archive de mise à jour et sa signature (`<nom du zip>.sig`, nom exact) : en HTTPS seulement.
        let zip = p.assets?.first { $0.name.lowercased().hasSuffix(".zip") && isHTTPS($0.browser_download_url) }
        let signature = zip.flatMap { zip in
            p.assets?.first { $0.name == zip.name + ".sig" && isHTTPS($0.browser_download_url) }
        }
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
    /// CLE_PUBLIQUE_A_REMPLACER : valeur provisoire (32 octets à zéro), refusée par `publicKey(base64:)`.
    /// Tant qu'elle est là, aucune mise à jour automatique ne s'installe.
    public static let releasePublicKey = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=" // CLE_PUBLIQUE_A_REMPLACER

    /// Taille maximale d'un fichier .sig : 88 caractères base64 attendus, le reste est de la marge.
    public static let maxSignatureBytes = 512

    /// Clé publique Ed25519 depuis son base64 (32 octets). Nil si mal formée ou nulle (valeur provisoire).
    public static func publicKey(base64: String) -> Curve25519.Signing.PublicKey? {
        guard let raw = Data(base64Encoded: base64.trimmingCharacters(in: .whitespacesAndNewlines)),
              raw.count == 32, raw.contains(where: { $0 != 0 })
        else { return nil }
        return try? Curve25519.Signing.PublicKey(rawRepresentation: raw)
    }

    /// Contenu d'un fichier .sig (base64 d'une signature brute de 64 octets, blancs de début et de fin
    /// tolérés) → les 64 octets. Nil si vide, trop gros, pas en base64 ou d'une autre longueur.
    public static func signature(fromFile data: Data) -> Data? {
        guard data.count <= maxSignatureBytes, let text = String(data: data, encoding: .utf8),
              let raw = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              raw.count == 64
        else { return nil }
        return raw
    }

    /// Vrai seulement si `signatureFile` (contenu du .sig) est une signature Ed25519 valide des octets
    /// exacts de `archive` par `publicKey` (par défaut la clé épinglée). Tout le reste est refusé.
    public static func verifySignature(_ signatureFile: Data, of archive: Data, publicKey: String = releasePublicKey) -> Bool {
        guard let key = Self.publicKey(base64: publicKey), let signature = signature(fromFile: signatureFile) else { return false }
        return key.isValidSignature(signature, for: archive)
    }
}

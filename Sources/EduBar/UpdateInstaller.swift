import AppKit
import EduBarCore
import Foundation

/// Remplace l'app en cours par une release, puis la relance.
/// Chaque étape est vérifiée (signature Ed25519 de publication, empreinte GitHub, identifiant, version,
/// signature de code) ; au moindre écart, l'app installée n'est pas touchée.
enum UpdateInstaller {
    enum Failure: LocalizedError, Equatable {
        /// `badSignature` : signature de publication absente, mal formée ou invalide. La release est
        /// alors écartée (ni réessayée par le bouton, ni proposée au téléchargement).
        case noArchive, badSignature, notReplaceable, http(Int), digestMismatch, badBundle, tool(String)

        var errorDescription: String? {
            switch self {
            // Signature refusée : même message que l'absence d'archive (aucun nouveau texte).
            case .noArchive, .badSignature: L10n.tr("la release n'a pas d'archive vérifiable.", "the release has no verifiable archive.")
            case .notReplaceable:
                L10n.tr(
                    "l'app ne peut pas se remplacer ici (glisse-la dans Applications).",
                    "the app cannot replace itself here (drag it into Applications)."
                )
            case .http(let code): L10n.tr("téléchargement impossible (HTTP \(code)).", "download failed (HTTP \(code)).")
            case .digestMismatch:
                L10n.tr(
                    "l'archive téléchargée ne correspond pas à l'empreinte publiée.",
                    "the downloaded archive does not match the published checksum."
                )
            case .badBundle:
                L10n.tr("l'archive ne contient pas la bonne version d'EduBar.", "the archive does not contain the right EduBar version.")
            case .tool(let name): L10n.tr("échec de \(name).", "\(name) failed.")
            }
        }
    }

    /// Faux si l'app ne peut pas se remplacer elle-même : lancée hors d'un .app, depuis le .dmg,
    /// translocalisée par Gatekeeper, ou dans un dossier non inscriptible.
    static var canReplaceSelf: Bool {
        let app = Bundle.main.bundleURL
        guard app.pathExtension == "app", Bundle.main.bundleIdentifier != nil else { return false }
        let path = app.path
        guard !path.contains("/AppTranslocation/"), !path.hasPrefix("/Volumes/") else { return false }
        let fm = FileManager.default
        return fm.isWritableFile(atPath: path) && fm.isWritableFile(atPath: app.deletingLastPathComponent().path)
    }

    /// Télécharge, vérifie et met en place la release. Ne relance pas.
    static func install(_ release: Release) async throws {
        guard let zip = release.zip, let digest = release.zipSHA256 else { throw Failure.noArchive }
        guard let signatureURL = release.zipSignature else { throw rejected("pas d'asset .sig") }
        guard canReplaceSelf, let bundleID = Bundle.main.bundleIdentifier else { throw Failure.notReplaceable }
        let fm = FileManager.default
        let current = Bundle.main.bundleURL
        // Sur le même volume que l'app : le remplacement final est un simple échange.
        let work = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: current, create: true)
        defer { try? fm.removeItem(at: work) }

        // La signature d'abord (quelques octets) : inutile de télécharger l'archive si elle est illisible.
        let signatureFile = try await downloadSignature(from: signatureURL)
        guard Update.signature(fromFile: signatureFile) != nil else { throw rejected("signature mal formée") }

        let (downloaded, response) = try await Network.session.download(from: zip)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw Failure.http(code) }
        let archive = work.appending(path: "update.zip")
        try fm.moveItem(at: downloaded, to: archive)
        // Empreinte et signature portent sur les mêmes octets, ceux que ditto extrait ensuite.
        let bytes = try Data(contentsOf: archive)
        guard Update.sha256(of: bytes) == digest else { throw Failure.digestMismatch }
        guard Update.verifySignature(signatureFile, of: bytes) else { throw rejected("signature invalide pour cette archive") }

        let unpacked = work.appending(path: "unpacked")
        try run("/usr/bin/ditto", ["-x", "-k", archive.path, unpacked.path])
        let apps = try fm.contentsOfDirectory(at: unpacked, includingPropertiesForKeys: nil).filter { $0.pathExtension == "app" }
        guard apps.count == 1, let app = apps.first,
              let info = Update.bundleInfo(at: app), info.id == bundleID, info.version == release.version
        else { throw Failure.badBundle }
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])

        _ = try fm.replaceItemAt(current, withItemAt: app)
    }

    /// Lancée depuis une image disque montée (le .dmg) : l'image ne peut pas être éjectée
    /// et l'app ne peut pas se mettre à jour.
    static var diskImageVolume: URL? {
        let app = Bundle.main.bundleURL
        guard app.pathExtension == "app", app.path.hasPrefix("/Volumes/") else { return nil }
        return (try? app.resourceValues(forKeys: [.volumeURLKey]))?.volume
    }

    /// Translocalisée par Gatekeeper (lancée depuis Téléchargements sans avoir été déplacée).
    static var isTranslocated: Bool { Bundle.main.bundleURL.path.contains("/AppTranslocation/") }

    /// Copie l'app en cours dans /Applications (en remplaçant une ancienne copie). Renvoie la copie.
    static func copyToApplications() throws -> URL {
        let fm = FileManager.default
        let apps = URL(fileURLWithPath: "/Applications", isDirectory: true)
        guard fm.isWritableFile(atPath: apps.path) else { throw Failure.notReplaceable }
        let destination = apps.appending(path: "EduBar.app")
        let work = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: apps, create: true)
        defer { try? fm.removeItem(at: work) }
        let staged = work.appending(path: "EduBar.app")
        try run("/usr/bin/ditto", [Bundle.main.bundleURL.path, staged.path])
        // La copie hérite de la quarantaine du .dmg : macOS la lancerait isolée (App Translocation)
        // et Gatekeeper la bloquerait. L'utilisateur a déjà autorisé l'app qui tourne.
        try run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", staged.path])
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", staged.path])
        if fm.fileExists(atPath: destination.path) {
            _ = try fm.replaceItemAt(destination, withItemAt: staged)
        } else {
            try fm.moveItem(at: staged, to: destination)
        }
        return destination
    }

    /// Quitte, puis rouvre l'app (`app`, par défaut elle-même) une fois ce processus terminé.
    /// `ejecting` : image disque à éjecter entre les deux.
    @MainActor static func relaunch(at app: URL = Bundle.main.bundleURL, ejecting volume: URL? = nil) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Chemins et PID passés en arguments, jamais interpolés dans le script.
        task.arguments = [
            "-c",
            "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.2; done; "
                + "if [ -n \"$3\" ]; then /usr/bin/hdiutil detach \"$3\" -quiet || /usr/bin/hdiutil detach \"$3\" -force -quiet || true; fi; /usr/bin/open -n \"$2\"",
            "sh", String(ProcessInfo.processInfo.processIdentifier), app.path, volume?.path ?? "",
        ]
        do {
            try task.run()
            NSApp.terminate(nil)
        } catch {
            NSLog("EduBar: relance impossible : \(error.localizedDescription)")
        }
    }

    /// Télécharge le fichier .sig, plafonné à `Update.maxSignatureBytes` (au-delà : refusé sans tout lire).
    private static func downloadSignature(from url: URL) async throws -> Data {
        let (stream, response) = try await Network.session.bytes(from: url)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw Failure.http(code) }
        guard response.expectedContentLength <= Int64(Update.maxSignatureBytes) else {
            stream.task.cancel()
            throw rejected("fichier .sig trop gros")
        }
        var data = Data()
        for try await byte in stream {
            data.append(byte)
            if data.count > Update.maxSignatureBytes {
                stream.task.cancel()
                throw rejected("fichier .sig trop gros")
            }
        }
        return data
    }

    /// Signature refusée : le détail va au journal, l'utilisateur voit le message de `.badSignature`.
    private static func rejected(_ reason: String) -> Failure {
        NSLog("EduBar: mise à jour refusée, signature de publication : \(reason)")
        return .badSignature
    }

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failure.tool(URL(fileURLWithPath: tool).lastPathComponent) }
    }
}

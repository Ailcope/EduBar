import AppKit
import EduBarCore
import Foundation

/// Remplace l'app en cours par une release, puis la relance.
/// Chaque étape est vérifiée (empreinte GitHub, identifiant, version, signature) ; au moindre écart,
/// l'app installée n'est pas touchée.
enum UpdateInstaller {
    enum Failure: LocalizedError {
        case noArchive, notReplaceable, http(Int), digestMismatch, badBundle, tool(String)

        var errorDescription: String? {
            switch self {
            case .noArchive: "la release n'a pas d'archive vérifiable."
            case .notReplaceable: "l'app ne peut pas se remplacer ici (glisse-la dans Applications)."
            case .http(let code): "téléchargement impossible (HTTP \(code))."
            case .digestMismatch: "l'archive téléchargée ne correspond pas à l'empreinte publiée."
            case .badBundle: "l'archive ne contient pas la bonne version d'EduBar."
            case .tool(let name): "échec de \(name)."
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
        guard canReplaceSelf, let bundleID = Bundle.main.bundleIdentifier else { throw Failure.notReplaceable }
        let fm = FileManager.default
        let current = Bundle.main.bundleURL
        // Sur le même volume que l'app : le remplacement final est un simple échange.
        let work = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: current, create: true)
        defer { try? fm.removeItem(at: work) }

        let (downloaded, response) = try await URLSession.shared.download(from: zip)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw Failure.http(code) }
        let archive = work.appending(path: "update.zip")
        try fm.moveItem(at: downloaded, to: archive)
        guard try Update.sha256(of: archive) == digest else { throw Failure.digestMismatch }

        let unpacked = work.appending(path: "unpacked")
        try run("/usr/bin/ditto", ["-x", "-k", archive.path, unpacked.path])
        let apps = try fm.contentsOfDirectory(at: unpacked, includingPropertiesForKeys: nil).filter { $0.pathExtension == "app" }
        guard apps.count == 1, let app = apps.first,
              let info = Update.bundleInfo(at: app), info.id == bundleID, info.version == release.version
        else { throw Failure.badBundle }
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])

        _ = try fm.replaceItemAt(current, withItemAt: app)
    }

    /// Quitte, puis rouvre l'app une fois ce processus terminé.
    @MainActor static func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Chemin et PID passés en arguments, jamais interpolés dans le script.
        task.arguments = [
            "-c", "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open -n \"$2\"",
            "sh", String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundleURL.path,
        ]
        do {
            try task.run()
            NSApp.terminate(nil)
        } catch {
            NSLog("EduBar: relance impossible : \(error.localizedDescription)")
        }
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

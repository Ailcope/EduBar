import Foundation

/// App Raccourcis de macOS, par son outil en ligne de commande.
enum ShortcutRunner {
    private static let tool = URL(fileURLWithPath: "/usr/bin/shortcuts")

    /// Noms des raccourcis de l'utilisateur, triés.
    nonisolated static func list() -> [String] {
        let process = Process()
        process.executableURL = tool
        process.arguments = ["list"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Lance le raccourci sans attendre sa fin.
    static func run(_ name: String) {
        let process = Process()
        process.executableURL = tool
        process.arguments = ["run", name]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { NSLog("EduBar: raccourci impossible à lancer : \(error.localizedDescription)") }
    }
}

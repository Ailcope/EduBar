import AppKit
import EduBarCore
import Foundation
import Observation

/// Regarde sur GitHub si une version plus récente est publiée (au lancement, puis une fois par jour).
/// N'installe rien : propose de télécharger le .dmg.
@MainActor @Observable
final class UpdateChecker {
    /// Version plus récente disponible, s'il y en a une.
    private(set) var available: Release?
    /// Résultat de la dernière vérification manuelle, pour les réglages.
    private(set) var message: String?
    private(set) var checking = false

    @ObservationIgnored private var lastCheck: Date?

    let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String

    /// Vérification automatique : silencieuse, au plus une fois par jour.
    func checkIfDue() async {
        if let lastCheck, Date().timeIntervalSince(lastCheck) < 24 * 60 * 60 { return }
        _ = await check()
    }

    /// Vérification demandée depuis les réglages.
    func checkNow() {
        Task { message = await check() }
    }

    func install() {
        guard let r = available else { return }
        NSWorkspace.shared.open(r.dmg ?? r.page)
    }

    private func check() async -> String {
        guard Version(current ?? "") != nil else { return "Version inconnue (app lancée hors du .app)." }
        checking = true
        defer { checking = false }
        do {
            let release = try await Self.fetchLatest(current: current)
            lastCheck = Date()
            available = Update.available(release, current: current)
            return available.map { "Version \($0.version) disponible." } ?? "EduBar est à jour."
        } catch {
            return "Vérification impossible : \(error.localizedDescription)"
        }
    }

    private struct HTTPStatus: LocalizedError {
        let code: Int
        var errorDescription: String? { code == 404 ? "aucune release publique trouvée." : "erreur HTTP \(code)." }
    }

    nonisolated private static func fetchLatest(current: String?) async throws -> Release {
        var request = URLRequest(url: Update.latestURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("EduBar/\(current ?? "dev")", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw HTTPStatus(code: code) }
        return try Update.decode(data)
    }
}

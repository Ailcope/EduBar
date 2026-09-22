import AppKit
import EduBarCore
import Foundation
import Observation

/// Regarde sur GitHub si une version plus récente est publiée (au lancement, puis une fois par jour)
/// et l'installe toute seule : téléchargement vérifié, remplacement de l'app, relance.
/// Si l'app ne peut pas se remplacer (lancée depuis le .dmg, par exemple), propose le .dmg.
@MainActor @Observable
final class UpdateChecker {
    /// Version plus récente disponible, s'il y en a une.
    private(set) var available: Release?
    /// Résultat de la dernière vérification ou installation, pour les réglages.
    private(set) var message: String?
    private(set) var checking = false
    private(set) var installing = false

    @ObservationIgnored private var lastCheck: Date?

    let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String

    /// Vrai si le bouton installe directement (sinon il ouvre le .dmg).
    var canInstallInPlace: Bool { available?.zipSHA256 != nil && UpdateInstaller.canReplaceSelf }

    /// Clé posée juste avant la relance, pour annoncer la mise à jour au démarrage suivant.
    static let updatedFromKey = "updatedFrom"

    /// Vérification automatique : au plus une fois par jour, et installe ce qu'elle trouve.
    func checkIfDue() async {
        if let lastCheck, Date().timeIntervalSince(lastCheck) < 24 * 60 * 60 { return }
        _ = await check()
        if canInstallInPlace { await installInPlace() }
    }

    /// Vérification demandée depuis les réglages.
    func checkNow() {
        Task { message = await check() }
    }

    /// Bouton des réglages.
    func install() {
        guard let r = available else { return }
        if canInstallInPlace {
            Task { await installInPlace() }
        } else {
            NSWorkspace.shared.open(r.dmg ?? r.page)
        }
    }

    private func installInPlace() async {
        guard let r = available, !installing else { return }
        installing = true
        message = "Installation de la version \(r.version)…"
        do {
            try await UpdateInstaller.install(r)
            NSLog("EduBar: version \(r.version) installée, relance")
            UserDefaults.standard.set(current, forKey: Self.updatedFromKey)
            UpdateInstaller.relaunch()
        } catch {
            NSLog("EduBar: mise à jour impossible : \(error.localizedDescription)")
            message = "Mise à jour impossible : \(error.localizedDescription)"
            installing = false
        }
    }

    private func check() async -> String {
        guard Version(current ?? "") != nil else { return "Version inconnue (app lancée hors du .app)." }
        checking = true
        defer { checking = false }
        do {
            let release = try await Self.fetchLatest(current: current)
            lastCheck = Date()
            available = Update.available(release, current: current)
            let result = available.map { "Version \($0.version) disponible." } ?? "EduBar est à jour."
            NSLog("EduBar: mises à jour (\(current ?? "?") installée, \(release.version) publiée) : \(result)")
            return result
        } catch {
            NSLog("EduBar: vérification des mises à jour impossible : \(error.localizedDescription)")
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

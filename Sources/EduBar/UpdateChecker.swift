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
    /// Appelé une fois par version trouvée qui ne peut pas s'installer toute seule (notification).
    @ObservationIgnored var onFound: ((Release) -> Void)?

    let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String

    /// Vrai si le bouton installe directement (sinon il ouvre le .dmg).
    var canInstallInPlace: Bool { available?.zipSHA256 != nil && UpdateInstaller.canReplaceSelf }

    /// Clé posée juste avant la relance, pour annoncer la mise à jour au démarrage suivant.
    static let updatedFromKey = "updatedFrom"

    /// Vérification automatique : au plus toutes les 6 h, et installe ce qu'elle trouve.
    /// Si elle ne peut pas (lancée depuis le .dmg…), prévient par une notification.
    func checkIfDue() async {
        if let lastCheck, Date().timeIntervalSince(lastCheck) < 6 * 60 * 60 { return }
        _ = await check()
        if canInstallInPlace {
            await installInPlace()
        } else if let r = available, UserDefaults.standard.string(forKey: "notifiedVersion") != r.version.description {
            UserDefaults.standard.set(r.version.description, forKey: "notifiedVersion")
            onFound?(r)
        }
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
        message = L10n.tr("Installation de la version \(r.version)…", "Installing version \(r.version)…")
        do {
            try await UpdateInstaller.install(r)
            NSLog("EduBar: version \(r.version) installée, relance")
            UserDefaults.standard.set(current, forKey: Self.updatedFromKey)
            UpdateInstaller.relaunch()
        } catch {
            NSLog("EduBar: mise à jour impossible : \(error.localizedDescription)")
            message = L10n.tr("Mise à jour impossible : \(error.localizedDescription)", "Update failed: \(error.localizedDescription)")
            installing = false
        }
    }

    private func check() async -> String {
        guard Version(current ?? "") != nil else {
            return L10n.tr("Version inconnue (app lancée hors du .app).", "Unknown version (app launched outside its .app).")
        }
        checking = true
        defer { checking = false }
        do {
            let release = try await Self.fetchLatest(current: current)
            lastCheck = Date()
            available = Update.available(release, current: current)
            let result = available.map { L10n.tr("Version \($0.version) disponible.", "Version \($0.version) available.") }
                ?? L10n.tr("EduBar est à jour.", "EduBar is up to date.")
            NSLog("EduBar: mises à jour (\(current ?? "?") installée, \(release.version) publiée) : \(result)")
            return result
        } catch {
            NSLog("EduBar: vérification des mises à jour impossible : \(error.localizedDescription)")
            return L10n.tr("Vérification impossible : \(error.localizedDescription)", "Check failed: \(error.localizedDescription)")
        }
    }

    private struct HTTPStatus: LocalizedError {
        let code: Int
        var errorDescription: String? {
            code == 404
                ? L10n.tr("aucune release publique trouvée.", "no public release found.")
                : L10n.tr("erreur HTTP \(code).", "HTTP error \(code).")
        }
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

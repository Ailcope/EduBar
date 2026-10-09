import EduBarCore
import Foundation

/// Envoie au plus un signal anonyme par jour à edu.mathys.cc : un identifiant tiré au hasard par le
/// serveur (rangé au trousseau) et la version. Ni l'URL du calendrier ni rien d'autre ne part.
@MainActor
final class UsageReporter {
    static let enabledKey = "usageEnabled"
    private static let lastDayKey = "usageLastDay"
    private static let account = "installation"

    /// Version du bundle ; absente en `swift run`, donc rien n'est envoyé.
    private let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    /// Un seul nouvel identifiant demandé par lancement après un 404.
    private var reRegistered = false
    private var running = false

    /// Jour du dernier signal réussi (`yyyy-MM-dd`), pour le diagnostic.
    var lastDay: String? { UserDefaults.standard.string(forKey: Self.lastDayKey) }

    /// À appeler régulièrement : n'envoie que si le comptage est actif et qu'aucun signal n'est parti aujourd'hui.
    func sendIfDue(enabled: Bool, calendar: Calendar) async {
        guard enabled, !running, let version, Version(version) != nil else { return }
        guard Usage.isDue(lastSentDay: lastDay, now: Date(), calendar: calendar) else { return }
        running = true
        defer { running = false }

        var id = Keychain.get(Self.account).flatMap { Usage.isValidID($0) ? $0 : nil }
        if id == nil {
            guard let (status, body) = await Self.perform(Usage.registerRequest()),
                  let fresh = Usage.parseRegistration(status: status, body: body)
            else { return }
            Keychain.set(fresh, for: Self.account)
            id = fresh
        }
        guard let id, let (status, _) = await Self.perform(Usage.signalRequest(id: id, version: version)) else { return }
        switch Usage.outcome(status: status) {
        case .sent:
            UserDefaults.standard.set(Usage.dayKey(Date(), calendar: calendar), forKey: Self.lastDayKey)
        case .unknownID:
            // Le serveur ne connaît plus cet identifiant : on l'oublie, un nouveau sera demandé au prochain essai (une fois par lancement).
            guard !reRegistered else { return }
            reRegistered = true
            Keychain.set(nil, for: Self.account)
        case .retryLater:
            break
        }
    }

    /// Session éphémère : ni cookies, ni cache, ni en-tête en plus.
    nonisolated private static func perform(_ request: URLRequest) async -> (Int, Data)? {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.timeoutIntervalForRequest = 15
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }
        guard let (data, response) = try? await session.data(for: request),
              let code = (response as? HTTPURLResponse)?.statusCode
        else { return nil }
        return (code, data)
    }
}

import EduBarCore
import Foundation
import Observation

enum FetchError: LocalizedError {
    case http(Int)
    case notACalendar
    case emptyFeed

    var errorDescription: String? {
        switch self {
        case let .http(code): L10n.tr("Le serveur a répondu \(code).", "The server replied \(code).")
        case .notACalendar: L10n.tr("La réponse n'est pas un calendrier iCal.", "The response is not an iCal calendar.")
        case .emptyFeed:
            L10n.tr(
                "La source a renvoyé un calendrier vide, les cours déjà connus sont gardés.",
                "The source returned an empty calendar, known classes are kept."
            )
        }
    }
}

/// Télécharge le flux, garde un cache disque et les derniers cours valides si le réseau tombe.
/// Les journées passées, qu'Edusign retire du flux, sont archivées à part.
@MainActor @Observable
final class CalendarStore {
    private(set) var courses: [Course] = []
    private(set) var lastUpdated: Date?
    private(set) var lastError: String?
    private(set) var isLoading = false

    private let cacheURL: URL
    /// Cours de la source myGES (JSON). Seul le calendrier principal en a un.
    private let jsonCacheURL: URL?
    private let historyURL: URL
    private var archived: [Course] = []

    /// `cacheName` : fichier du cache disque (un par calendrier).
    init(cacheName: String = "calendar.ics") {
        cacheURL = Self.cacheDirectory.appendingPathComponent(cacheName)
        jsonCacheURL = cacheName == "calendar.ics" ? Self.cacheDirectory.appendingPathComponent("calendar-myges.json") : nil
        // Hors de Caches, que macOS peut vider : ces cours-là ne se retéléchargent pas.
        historyURL = FeedFile.standard.url.deletingLastPathComponent()
            .appendingPathComponent("history-" + (cacheName as NSString).deletingPathExtension + ".json")
        if let data = try? Data(contentsOf: historyURL), let saved = try? JSONDecoder().decode([Course].self, from: data) {
            archived = saved
        }
        courses = archived
        if let text = try? String(contentsOf: cacheURL, encoding: .utf8) {
            courses = History.merge(archived: archived, fresh: ICSParser.parse(text), now: Date(), calendar: .current)
            lastUpdated = Self.modified(cacheURL)
        } else if let jsonCacheURL, let data = try? Data(contentsOf: jsonCacheURL),
                  let saved = try? JSONDecoder().decode([Course].self, from: data) {
            courses = History.merge(archived: archived, fresh: saved, now: Date(), calendar: .current)
            lastUpdated = Self.modified(jsonCacheURL)
        }
    }

    private static let cacheDirectory: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EduBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    func refresh(from url: URL?) async {
        guard let url else { return }
        await refresh {
            let (text, parsed) = try await Self.fetch(url)
            return (parsed, { [cacheURL, jsonCacheURL] in
                try? text.write(to: cacheURL, atomically: true, encoding: .utf8)
                if let jsonCacheURL { try? FileManager.default.removeItem(at: jsonCacheURL) }
            })
        }
    }

    /// Source myGES : les cours viennent de l'API, le cache est un JSON.
    func refresh(using fetch: @Sendable () async throws -> [Course]) async {
        await refresh {
            let parsed = try await fetch()
            return (parsed, { [cacheURL, jsonCacheURL] in
                guard let jsonCacheURL, let data = try? JSONEncoder().encode(parsed) else { return }
                try? data.write(to: jsonCacheURL, options: .atomic)
                // Le cache iCal d'une ancienne source ne doit plus l'emporter au prochain lancement.
                try? FileManager.default.removeItem(at: cacheURL)
            })
        }
    }

    /// Logique commune : garde anti-flux vide, fusion avec l'historique, archive, cache.
    private func refresh(_ load: () async throws -> (courses: [Course], persist: () -> Void)) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let (parsed, persist) = try await load()
            let now = Date()
            if Freshness.suspiciousEmpty(fresh: parsed, previous: courses, now: now) { throw FetchError.emptyFeed }
            courses = History.merge(archived: archived, fresh: parsed, now: now, calendar: .current)
            archive(History.archivable(courses, now: now, calendar: .current))
            lastUpdated = now
            lastError = nil
            persist()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private static func modified(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    /// Oublie tout (URL supprimée).
    func clear() {
        courses = []
        lastUpdated = nil
        lastError = nil
        try? FileManager.default.removeItem(at: cacheURL)
        if let jsonCacheURL { try? FileManager.default.removeItem(at: jsonCacheURL) }
        archived = []
        try? FileManager.default.removeItem(at: historyURL)
    }

    /// Même protection que l'URL (0600, dossier 0700) : l'emploi du temps reste privé.
    private func archive(_ past: [Course]) {
        guard past != archived, let data = try? JSONEncoder().encode(past) else { return }
        let file = FeedFile(directory: historyURL.deletingLastPathComponent(), name: historyURL.lastPathComponent)
        guard (try? file.write(String(decoding: data, as: UTF8.self))) != nil else { return }
        archived = past
    }

    nonisolated static func fetch(_ url: URL) async throws -> (text: String, courses: [Course]) {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("text/calendar", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 { throw FetchError.http(http.statusCode) }
        guard let text = String(data: data, encoding: .utf8), text.contains("BEGIN:VCALENDAR") else {
            throw FetchError.notACalendar
        }
        return (text, ICSParser.parse(text))
    }
}

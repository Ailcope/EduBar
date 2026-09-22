import EduBarCore
import Foundation
import Observation

enum FetchError: LocalizedError {
    case http(Int)
    case notACalendar
    case emptyFeed

    var errorDescription: String? {
        switch self {
        case let .http(code): "Le serveur a répondu \(code)."
        case .notACalendar: "La réponse n'est pas un calendrier iCal."
        case .emptyFeed: "Edusign a renvoyé un calendrier vide, les cours déjà connus sont gardés."
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
    private let historyURL: URL
    private var archived: [Course] = []

    /// `cacheName` : fichier du cache disque (un par calendrier).
    init(cacheName: String = "calendar.ics") {
        cacheURL = Self.cacheDirectory.appendingPathComponent(cacheName)
        // Hors de Caches, que macOS peut vider : ces cours-là ne se retéléchargent pas.
        historyURL = FeedFile.standard.url.deletingLastPathComponent()
            .appendingPathComponent("history-" + (cacheName as NSString).deletingPathExtension + ".json")
        if let data = try? Data(contentsOf: historyURL), let saved = try? JSONDecoder().decode([Course].self, from: data) {
            archived = saved
        }
        courses = archived
        if let text = try? String(contentsOf: cacheURL, encoding: .utf8) {
            courses = History.merge(archived: archived, fresh: ICSParser.parse(text), now: Date(), calendar: .current)
            lastUpdated = (try? cacheURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        }
    }

    private static let cacheDirectory: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EduBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    func refresh(from url: URL?) async {
        guard let url, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let (text, parsed) = try await Self.fetch(url)
            let now = Date()
            if Freshness.suspiciousEmpty(fresh: parsed, previous: courses, now: now) { throw FetchError.emptyFeed }
            courses = History.merge(archived: archived, fresh: parsed, now: now, calendar: .current)
            archive(History.archivable(courses, now: now, calendar: .current))
            lastUpdated = now
            lastError = nil
            try? text.write(to: cacheURL, atomically: true, encoding: .utf8)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Oublie tout (URL supprimée).
    func clear() {
        courses = []
        lastUpdated = nil
        lastError = nil
        try? FileManager.default.removeItem(at: cacheURL)
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

import EduBarCore
import Foundation
import Observation

enum FetchError: LocalizedError {
    case http(Int)
    case notACalendar

    var errorDescription: String? {
        switch self {
        case let .http(code): "Le serveur a répondu \(code)."
        case .notACalendar: "La réponse n'est pas un calendrier iCal."
        }
    }
}

/// Télécharge le flux, garde un cache disque et les derniers cours valides si le réseau tombe.
@MainActor @Observable
final class CalendarStore {
    private(set) var courses: [Course] = []
    private(set) var lastUpdated: Date?
    private(set) var lastError: String?
    private(set) var isLoading = false

    private let cacheURL: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EduBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("calendar.ics")
    }()

    init() {
        if let text = try? String(contentsOf: cacheURL, encoding: .utf8) {
            courses = ICSParser.parse(text)
            lastUpdated = (try? cacheURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        }
    }

    func refresh(from url: URL?) async {
        guard let url, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let (text, parsed) = try await Self.fetch(url)
            courses = parsed
            lastUpdated = Date()
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

import EduBarCore
import Foundation
import Observation

/// Météo de la ville choisie (Open-Meteo, sans clé), avec un cache disque.
/// Rien n'est demandé tant que la météo n'a pas à s'afficher.
/// Rechargée toute seule au délai choisi dans les réglages, ou seulement à la demande.
@MainActor @Observable
final class WeatherStore {
    private struct Cached: Codable {
        let place: WeatherPlace
        let forecast: Forecast
    }

    private(set) var lastError: String?
    private(set) var isLoading = false
    private var cached: Cached?

    @ObservationIgnored private var lastAttempt: Date?
    private let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("EduBar", isDirectory: true).appendingPathComponent("weather.json")

    init() {
        cached = (try? Data(contentsOf: cacheURL)).flatMap { try? JSONDecoder().decode(Cached.self, from: $0) }
    }

    /// La dernière météo connue de cette ville (jamais celle d'une autre).
    func forecast(for place: WeatherPlace) -> Forecast? {
        cached?.place == place ? cached?.forecast : nil
    }

    /// Recharge selon les réglages (délai choisi, ou jamais tout seul). Après un échec, pas de nouvel
    /// essai avant 5 min. `force` : bouton ↻ du menu.
    func refreshIfDue(_ place: WeatherPlace, settings: WeatherSettings, force: Bool = false) async {
        guard !isLoading else { return }
        let now = Date()
        if !force {
            guard Weather.needsRefresh(forecast(for: place), now: now, settings: settings) else { return }
            if let lastAttempt, now.timeIntervalSince(lastAttempt) < 5 * 60 { return }
        }
        lastAttempt = now
        isLoading = true
        defer { isLoading = false }
        do {
            let data = try await Self.get(Weather.forecastURL(place))
            let fresh = Cached(place: place, forecast: try Weather.decodeForecast(data, fetched: Date()))
            cached = fresh
            lastError = nil
            try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? JSONEncoder().encode(fresh).write(to: cacheURL, options: .atomic)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Oublie la météo en cache (météo désactivée ou ville retirée).
    func clear() {
        cached = nil
        lastError = nil
        lastAttempt = nil
        try? FileManager.default.removeItem(at: cacheURL)
    }

    nonisolated static func search(_ query: String) async throws -> [WeatherPlace] {
        guard let url = Weather.searchURL(query) else { return [] }
        return try Weather.decodePlaces(try await get(url))
    }

    nonisolated private static func get(_ url: URL) async throws -> Data {
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 { throw FetchError.http(http.statusCode) }
        return data
    }
}

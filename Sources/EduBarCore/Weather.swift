import Foundation

/// Ville choisie dans les réglages (géocodage Open-Meteo).
public struct WeatherPlace: Codable, Equatable, Sendable {
    public var name: String
    public var region: String?
    public var country: String?
    public var latitude: Double
    public var longitude: Double

    public init(name: String, region: String? = nil, country: String? = nil, latitude: Double, longitude: Double) {
        self.name = name
        self.region = region
        self.country = country
        self.latitude = latitude
        self.longitude = longitude
    }

    /// « Reims, Grand Est, France ».
    public var label: String {
        [name, region, country].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

/// Météo à la place du prochain cours quand il est loin. Désactivée tant qu'on ne l'allume pas :
/// sans elle, EduBar ne parle jamais à Open-Meteo.
public struct WeatherSettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var place: WeatherPlace?
    /// La météo s'affiche quand le prochain cours est dans `hours` heures ou plus.
    public var hours: Int
    /// Recharger la météo toute seule. Sinon elle n'est chargée qu'une fois, puis au bouton ↻ du menu.
    public var autoRefresh: Bool
    /// Délai entre deux rechargements automatiques.
    public var refreshMinutes: Int

    public static let defaults = WeatherSettings(enabled: false, place: nil, hours: 12)
    /// Délais proposés dans les réglages.
    public static let refreshChoices = [15, 30, 60, 120, 180]

    public init(enabled: Bool, place: WeatherPlace?, hours: Int, autoRefresh: Bool = true, refreshMinutes: Int = 30) {
        self.enabled = enabled
        self.place = place
        self.hours = hours
        self.autoRefresh = autoRefresh
        self.refreshMinutes = refreshMinutes
    }

    /// Les clés absentes (réglages d'une ancienne version) prennent la valeur par défaut.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self.defaults
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        place = try c.decodeIfPresent(WeatherPlace.self, forKey: .place)
        hours = try c.decodeIfPresent(Int.self, forKey: .hours) ?? d.hours
        autoRefresh = try c.decodeIfPresent(Bool.self, forKey: .autoRefresh) ?? d.autoRefresh
        refreshMinutes = try c.decodeIfPresent(Int.self, forKey: .refreshMinutes) ?? d.refreshMinutes
    }
}

public struct Forecast: Codable, Equatable, Sendable {
    public struct Day: Codable, Equatable, Sendable {
        /// « 2026-10-03 », dans le fuseau de la ville.
        public var date: String
        /// Code météo WMO.
        public var code: Int
        public var min: Double
        public var max: Double
        /// Probabilité de pluie (%), si Open-Meteo la donne.
        public var rain: Int?

        public init(date: String, code: Int, min: Double, max: Double, rain: Int?) {
            self.date = date
            self.code = code
            self.min = min
            self.max = max
            self.rain = rain
        }
    }

    public var temperature: Double
    public var apparent: Double
    public var code: Int
    public var isDay: Bool
    /// km/h.
    public var wind: Double
    public var days: [Day]
    public var fetched: Date

    public init(
        temperature: Double, apparent: Double, code: Int, isDay: Bool, wind: Double, days: [Day], fetched: Date
    ) {
        self.temperature = temperature
        self.apparent = apparent
        self.code = code
        self.isDay = isDay
        self.wind = wind
        self.days = days
        self.fetched = fetched
    }
}

public struct WeatherCondition: Equatable, Sendable {
    public let label: String
    public let emoji: String
    /// SF Symbol.
    public let symbol: String
}

/// Météo Open-Meteo : gratuite, sans clé ni compte.
public enum Weather {
    /// Faut-il recharger ? Automatique : passé le délai choisi. Manuel : seulement s'il n'y a rien à afficher.
    public static func needsRefresh(_ forecast: Forecast?, now: Date, settings: WeatherSettings) -> Bool {
        guard let forecast else { return true }
        guard settings.autoRefresh else { return false }
        return now.timeIntervalSince(forecast.fetched) >= TimeInterval(max(1, settings.refreshMinutes)) * 60
    }

    /// Une météo que le rechargement automatique n'arrive plus à renouveler (3 h, ou deux délais)
    /// n'est plus affichée. En manuel, la dernière chargée reste, avec son heure.
    public static func isFresh(_ forecast: Forecast, now: Date, settings: WeatherSettings = .defaults) -> Bool {
        guard settings.autoRefresh else { return true }
        let limit = max(3 * 3600, TimeInterval(settings.refreshMinutes) * 120)
        return now.timeIntervalSince(forecast.fetched) < limit
    }

    /// Vrai hors cours, quand le prochain cours est dans `hours` heures ou plus (ou qu'il n'y en a plus).
    public static func applies(_ status: Status, now: Date, hours: Int) -> Bool {
        let next: Course?
        switch status {
        case .inClass: return false
        case let .onBreak(_, n), let .beforeFirst(n): next = n
        case let .dayOver(n), let .noClassToday(n): next = n
        }
        guard let next else { return true }
        return next.start.timeIntervalSince(now) >= TimeInterval(hours) * 3600
    }

    // MARK: - Open-Meteo

    /// Coordonnées arrondies au centième de degré (≈ 1 km) : la météo n'a pas besoin de mieux.
    public static func forecastURL(_ place: WeatherPlace) -> URL {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.2f", place.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.2f", place.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,weather_code,is_day,wind_speed_10m"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "5"),
        ]
        return c.url!
    }

    /// Recherche d'une ville par son nom ; nil si le champ est vide.
    public static func searchURL(_ query: String) -> URL? {
        let name = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        var c = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        c.queryItems = [
            URLQueryItem(name: "name", value: name),
            // Plus large que la liste affichée : les villes françaises remontent ensuite en tête.
            URLQueryItem(name: "count", value: "20"),
            URLQueryItem(name: "language", value: "fr"),
            URLQueryItem(name: "format", value: "json"),
        ]
        return c.url
    }

    private struct ForecastPayload: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let apparent_temperature: Double
            let weather_code: Int
            let is_day: Int
            let wind_speed_10m: Double
        }

        struct Daily: Decodable {
            let time: [String]
            let weather_code: [Int]
            let temperature_2m_max: [Double]
            let temperature_2m_min: [Double]
            let precipitation_probability_max: [Int?]?
        }

        let current: Current
        let daily: Daily
    }

    public static func decodeForecast(_ data: Data, fetched: Date) throws -> Forecast {
        let p = try JSONDecoder().decode(ForecastPayload.self, from: data)
        let d = p.daily
        let count = min(d.time.count, d.weather_code.count, d.temperature_2m_max.count, d.temperature_2m_min.count)
        let days = (0..<count).map { i in
            Forecast.Day(
                date: d.time[i], code: d.weather_code[i], min: d.temperature_2m_min[i], max: d.temperature_2m_max[i],
                rain: d.precipitation_probability_max.flatMap { $0.indices.contains(i) ? $0[i] : nil }
            )
        }
        return Forecast(
            temperature: p.current.temperature_2m, apparent: p.current.apparent_temperature,
            code: p.current.weather_code, isDay: p.current.is_day != 0, wind: p.current.wind_speed_10m,
            days: days, fetched: fetched
        )
    }

    private struct PlacesPayload: Decodable {
        struct Result: Decodable {
            let name: String
            let latitude: Double
            let longitude: Double
            let country: String?
            let country_code: String?
            let admin1: String?
        }

        let results: [Result]?
    }

    /// Les `limit` premières villes, les françaises d'abord (l'ordre d'Open-Meteo est gardé dans chaque groupe).
    public static func decodePlaces(_ data: Data, limit: Int = 5) throws -> [WeatherPlace] {
        let results = try JSONDecoder().decode(PlacesPayload.self, from: data).results ?? []
        let french = results.filter { $0.country_code == "FR" }
        let others = results.filter { $0.country_code != "FR" }
        return (french + others).prefix(limit).map {
            WeatherPlace(name: $0.name, region: $0.admin1, country: $0.country, latitude: $0.latitude, longitude: $0.longitude)
        }
    }

    // MARK: - Textes

    /// Code météo WMO vers un libellé, un émoji et un SF Symbol.
    public static func condition(_ code: Int, isDay: Bool) -> WeatherCondition {
        func c(_ label: String, _ emoji: String, _ symbol: String) -> WeatherCondition {
            WeatherCondition(label: label, emoji: emoji, symbol: symbol)
        }
        switch code {
        case 0: return isDay ? c("Ciel dégagé", "☀️", "sun.max.fill") : c("Ciel dégagé", "🌙", "moon.stars.fill")
        case 1: return isDay ? c("Plutôt dégagé", "🌤️", "sun.max.fill") : c("Plutôt dégagé", "🌙", "moon.fill")
        case 2: return c("Partiellement nuageux", "⛅", isDay ? "cloud.sun.fill" : "cloud.moon.fill")
        case 3: return c("Couvert", "☁️", "cloud.fill")
        case 45, 48: return c("Brouillard", "🌫️", "cloud.fog.fill")
        case 51, 53, 55, 56, 57: return c("Bruine", "🌦️", "cloud.drizzle.fill")
        case 61, 63, 65: return c("Pluie", "🌧️", "cloud.rain.fill")
        case 66, 67: return c("Pluie verglaçante", "🌧️", "cloud.sleet.fill")
        case 71, 73, 75, 77: return c("Neige", "🌨️", "cloud.snow.fill")
        case 80, 81, 82: return c("Averses", "🌧️", "cloud.heavyrain.fill")
        case 85, 86: return c("Averses de neige", "🌨️", "cloud.snow.fill")
        case 95, 96, 99: return c("Orage", "⛈️", "cloud.bolt.rain.fill")
        default: return c("Météo", "🌡️", "thermometer.medium")
        }
    }

    /// « 23° ».
    public static func degrees(_ value: Double) -> String {
        "\(Int(value.rounded()))°"
    }

    /// « 2026-10-03 » : le jour de `date`, comparable aux jours de la prévision.
    public static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// « Sam. » pour « 2026-10-03 ».
    public static func weekday(_ key: String) -> String? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        guard let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return nil }
        return Display.weekdays[calendar.component(.weekday, from: date) - 1]
    }
}

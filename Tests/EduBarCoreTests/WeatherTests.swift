import Foundation
import Testing
@testable import EduBarCore

@Suite struct WeatherTests {
    static let reims = WeatherPlace(name: "Reims", region: "Grand Est", country: "France", latitude: 49.26526, longitude: 4.02853)

    /// Réponse réelle d'Open-Meteo (03/10/2026), raccourcie à 3 jours.
    static let forecastJSON = Data("""
    {"latitude":49.260002,"longitude":4.02,"utc_offset_seconds":7200,"timezone":"Europe/Paris",
    "current_units":{"time":"iso8601","interval":"seconds","temperature_2m":"°C","weather_code":"wmo code"},
    "current":{"time":"2026-10-03T16:00","interval":900,"temperature_2m":22.9,"apparent_temperature":22.7,
    "weather_code":1,"is_day":1,"wind_speed_10m":4.1},
    "daily":{"time":["2026-10-03","2026-10-04","2026-10-05"],"weather_code":[3,45,80],
    "temperature_2m_max":[23.0,24.8,17.2],"temperature_2m_min":[8.1,12.5,14.0],
    "precipitation_probability_max":[0,null,56]}}
    """.utf8)

    static let placesJSON = Data("""
    {"results":[{"id":2984114,"name":"Reims","latitude":49.26526,"longitude":4.02853,"country_code":"FR",
    "country":"France","admin1":"Grand Est","admin2":"Marne"},
    {"id":2984111,"name":"Reims-la-Brulée","latitude":48.71667,"longitude":4.66667,"country":"France"}],
    "generationtime_ms":0.5}
    """.utf8)

    var forecast: Forecast { try! Weather.decodeForecast(Self.forecastJSON, fetched: at("2026-10-03 16:05")) }

    func bar(_ time: String, courses: [Course] = [c0, c1, c2, c3, c4], templates: BarTemplates = .defaults,
             companyToday: Bool = false, hours: Int = 12) -> String {
        let now = at(time)
        let status = Schedule(courses: courses).status(at: now, calendar: cal)
        let shown = Weather.applies(status, now: now, hours: hours)
        return Display.barText(
            status: status, alert: nil, now: now, calendar: cal, templates: templates, companyToday: companyToday,
            weather: shown ? (forecast, "Reims") : nil
        )
    }

    @Test func decodesTheForecast() throws {
        let f = forecast
        #expect(f.temperature == 22.9)
        #expect(f.apparent == 22.7)
        #expect(f.code == 1)
        #expect(f.isDay)
        #expect(f.wind == 4.1)
        #expect(f.days.count == 3)
        #expect(f.days[0] == Forecast.Day(date: "2026-10-03", code: 3, min: 8.1, max: 23.0, rain: 0))
        #expect(f.days[1].rain == nil)
        #expect(f.days[2].rain == 56)
    }

    @Test func garbageIsNotAForecast() {
        #expect(throws: (any Error).self) { try Weather.decodeForecast(Data("{}".utf8), fetched: Date()) }
    }

    @Test func decodesPlaces() throws {
        let places = try Weather.decodePlaces(Self.placesJSON)
        #expect(places.count == 2)
        #expect(places[0] == Self.reims)
        #expect(places[0].label == "Reims, Grand Est, France")
        #expect(places[1].label == "Reims-la-Brulée, France")
        // Aucune ville : Open-Meteo renvoie un objet sans `results`.
        #expect(try Weather.decodePlaces(Data(#"{"generationtime_ms":0.1}"#.utf8)).isEmpty)
    }

    @Test func urlsCarryOnlyRoundedCoordinatesAndTheQuery() throws {
        let url = Weather.forecastURL(Self.reims).absoluteString
        #expect(url.hasPrefix("https://api.open-meteo.com/v1/forecast?"))
        #expect(url.contains("latitude=49.27"))
        #expect(url.contains("longitude=4.03"))
        #expect(!url.contains("Reims"))
        let search = try #require(Weather.searchURL(" Saint-Étienne "))
        #expect(search.host == "geocoding-api.open-meteo.com")
        #expect(URLComponents(url: search, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "name" }?.value == "Saint-Étienne")
        #expect(Weather.searchURL("  ") == nil)
    }

    @Test func conditionsCoverWMOCodes() {
        #expect(Weather.condition(0, isDay: true).emoji == "☀️")
        #expect(Weather.condition(0, isDay: false).emoji == "🌙")
        #expect(Weather.condition(3, isDay: true).label == "Couvert")
        #expect(Weather.condition(45, isDay: true).label == "Brouillard")
        #expect(Weather.condition(63, isDay: true).emoji == "🌧️")
        #expect(Weather.condition(75, isDay: true).label == "Neige")
        #expect(Weather.condition(95, isDay: true).emoji == "⛈️")
        #expect(Weather.condition(1234, isDay: true).label == "Météo")
    }

    @Test func degreesAreRounded() {
        #expect(Weather.degrees(22.9) == "23°")
        #expect(Weather.degrees(-0.4) == "0°")
        #expect(Weather.degrees(-3.6) == "-4°")
    }

    @Test func appliesOnlyWhenNextCourseIsFarAway() {
        let s = Schedule(courses: [c0, c1, c2, c3, c4])
        func applies(_ time: String, hours: Int = 12) -> Bool {
            Weather.applies(s.status(at: at(time), calendar: cal), now: at(time), hours: hours)
        }
        // En cours, en pause, avant le premier cours : jamais avec 12 h.
        #expect(!applies("2026-09-22 10:00"))
        #expect(!applies("2026-09-22 13:10"))
        #expect(!applies("2026-09-22 08:00"))
        // Journée finie à 17h, reprise le lendemain 9h45 : 16 h 45 plus tard.
        #expect(applies("2026-09-22 17:00"))
        #expect(!applies("2026-09-22 22:00"))
        #expect(applies("2026-09-22 22:00", hours: 6))
        // Jamais pendant un cours, même avec un seuil minuscule.
        #expect(!applies("2026-09-22 16:00", hours: 1))
        // Plus aucun cours à venir.
        #expect(applies("2026-09-23 12:00"))
    }

    @Test func barShowsWeatherInsteadOfNextCourse() {
        #expect(bar("2026-09-22 17:30") == "🌤️ 23°")
        // Trop proche du prochain cours : texte habituel.
        #expect(bar("2026-09-22 22:00") == "Demain 9h45")
        // Plus de cours du tout : la météo plutôt que l'icône seule.
        #expect(bar("2026-09-23 12:00") == "🌤️ 23°")
        // Elle remplace aussi le texte des jours en entreprise.
        #expect(bar("2026-09-21 09:00", companyToday: true) == "🌤️ 23°")
    }

    @Test func examTomorrowBeatsWeather() {
        let exam = course("e", "2026-09-23 09:00", "2026-09-23 11:00", room: "Quai 12 - 501", title: "T1 - Partiel réseaux")
        #expect(bar("2026-09-22 17:30", courses: [c0, exam]) == "📝 Examen demain 9h · 501")
    }

    @Test func weatherTemplateHasItsOwnVariables() {
        var t = BarTemplates.defaults
        t.weather = "{ville} : {temp} {meteo} · {jour}"
        #expect(bar("2026-09-22 17:30", templates: t) == "Reims : 23° 🌤️ · Demain 9h45")
        // Pas de prochain cours : `{jour}` disparaît avec son séparateur.
        #expect(bar("2026-09-23 12:00", templates: t) == "Reims : 23° 🌤️")
    }

    @Test func oldSettingsDecodeWithTheDefaultWeatherTemplate() throws {
        let old = Data(#"{"dayOver":"💤 {jour}"}"#.utf8)
        let t = try JSONDecoder().decode(BarTemplates.self, from: old)
        #expect(t.weather == "{meteo} {temp}")
        #expect(t.dayOver == "💤 {jour}")
    }

    @Test func freshForThreeHours() {
        #expect(Weather.isFresh(forecast, now: at("2026-10-03 18:00")))
        #expect(!Weather.isFresh(forecast, now: at("2026-10-03 19:30")))
    }

    @Test func dayKeysAndWeekdays() {
        #expect(Weather.dayKey(at("2026-10-03 23:30"), calendar: cal) == "2026-10-03")
        #expect(Weather.weekday("2026-10-03") == "Sam.")
        #expect(Weather.weekday("2026-10-05") == "Lun.")
        #expect(Weather.weekday("n'importe quoi") == nil)
    }

    @Test func settingsRoundTrip() throws {
        var s = WeatherSettings.defaults
        #expect(!s.enabled)
        #expect(s.hours == 12)
        s.place = Self.reims
        let back = try JSONDecoder().decode(WeatherSettings.self, from: JSONEncoder().encode(s))
        #expect(back == s)
    }
}

@Suite struct WeekendTests {
    let nextMonday = course("m", "2026-09-28 09:00", "2026-09-28 11:00")

    func bar(_ time: String, templates: BarTemplates = .defaults, enabled: Bool = true,
             isCompanyDay: (Date) -> Bool = { _ in false }) -> String {
        let now = at(time)
        let schedule = Schedule(courses: [c0, c1, c2, c3, c4, nextMonday])
        let status = schedule.status(at: now, calendar: cal)
        return Display.barText(
            status: status, alert: nil, now: now, calendar: cal, templates: templates,
            weekend: enabled && schedule.endsWeek(status, calendar: cal, isCompanyDay: isCompanyDay)
        )
    }

    @Test func lastClassOfTheWeekAnnouncesTheWeekend() {
        // Mercredi, dernier cours de la semaine (le suivant est lundi prochain).
        #expect(bar("2026-09-23 10:00") == "🎉 Week-end dans 1 h 15")
        // Mardi, dernier cours de la journée seulement.
        #expect(bar("2026-09-22 16:00") == "📚 Fin dans 1 h")
        // Mardi matin : une pause suit, texte habituel.
        #expect(bar("2026-09-22 10:00") == "📚 Pause dans 1 h 15")
    }

    @Test func lastBlockCountsAsAWhole() {
        // c2 et c3 s'enchaînent : sans c4, le week-end s'annonce dès c2, avec la fin du bloc.
        let schedule = Schedule(courses: [c0, c1, c2, c3, nextMonday])
        let now = at("2026-09-22 14:30")
        let status = schedule.status(at: now, calendar: cal)
        #expect(schedule.endsWeek(status, calendar: cal))
        #expect(Display.barText(status: status, alert: nil, now: now, calendar: cal, weekend: true) == "🎉 Week-end dans 2 h 30")
    }

    @Test func companyDaysLaterInTheWeekAreNotTheWeekend() {
        let thursday = at("2026-09-24 12:00")
        #expect(bar("2026-09-23 10:00", isCompanyDay: { cal.isDate($0, inSameDayAs: thursday) }) == "📚 Fin dans 1 h 15")
    }

    @Test func canBeTurnedOffOrRewritten() {
        #expect(bar("2026-09-23 10:00", enabled: false) == "📚 Fin dans 1 h 15")
        var t = BarTemplates.defaults
        t.lastOfWeek = "🍻 Libre dans {temps}"
        #expect(bar("2026-09-23 10:00", templates: t) == "🍻 Libre dans 1 h 15")
    }

    @Test func outsideClassNothingEndsTheWeek() {
        let schedule = Schedule(courses: [c4])
        #expect(!schedule.endsWeek(schedule.status(at: at("2026-09-23 12:00"), calendar: cal), calendar: cal))
        #expect(!schedule.endsWeek(schedule.status(at: at("2026-09-23 08:00"), calendar: cal), calendar: cal))
    }
}

@Suite struct WeatherRefreshTests {
    let forecast = Forecast(
        temperature: 20, apparent: 20, code: 0, isDay: true, wind: 0, days: [], fetched: at("2026-10-03 16:00")
    )

    @Test func oldSettingsGetAutoRefreshEvery30Minutes() throws {
        let old = Data(#"{"enabled":true,"hours":6}"#.utf8)
        let s = try JSONDecoder().decode(WeatherSettings.self, from: old)
        #expect(s.enabled)
        #expect(s.hours == 6)
        #expect(s.autoRefresh)
        #expect(s.refreshMinutes == 30)
    }

    @Test func autoRefreshReloadsAfterTheChosenDelay() {
        var s = WeatherSettings.defaults
        s.refreshMinutes = 60
        #expect(!Weather.needsRefresh(forecast, now: at("2026-10-03 16:59"), settings: s))
        #expect(Weather.needsRefresh(forecast, now: at("2026-10-03 17:00"), settings: s))
        #expect(Weather.needsRefresh(nil, now: at("2026-10-03 17:00"), settings: s))
    }

    @Test func manualRefreshOnlyLoadsTheFirstTime() {
        var s = WeatherSettings.defaults
        s.autoRefresh = false
        #expect(!Weather.needsRefresh(forecast, now: at("2026-10-05 16:00"), settings: s))
        #expect(Weather.needsRefresh(nil, now: at("2026-10-05 16:00"), settings: s))
        // Sans rafraîchissement automatique, la dernière météo chargée reste affichée.
        #expect(Weather.isFresh(forecast, now: at("2026-10-05 16:00"), settings: s))
    }

    @Test func staleLimitFollowsTheDelay() {
        var s = WeatherSettings.defaults
        #expect(Weather.isFresh(forecast, now: at("2026-10-03 18:59"), settings: s))
        #expect(!Weather.isFresh(forecast, now: at("2026-10-03 19:00"), settings: s))
        s.refreshMinutes = 180
        #expect(Weather.isFresh(forecast, now: at("2026-10-03 21:00"), settings: s))
        #expect(!Weather.isFresh(forecast, now: at("2026-10-03 22:00"), settings: s))
    }

    @Test func frenchCitiesComeFirst() throws {
        let json = Data("""
        {"results":[{"name":"Sedan","latitude":37.13,"longitude":-96.19,"country_code":"US","country":"États-Unis","admin1":"Kansas"},
        {"name":"Sedan","latitude":49.7,"longitude":4.94,"country_code":"FR","country":"France","admin1":"Grand Est"},
        {"name":"Sedan","latitude":-7.0,"longitude":110.0,"country_code":"ID","country":"Indonésie","admin1":"Java central"},
        {"name":"Sedan","latitude":45.0,"longitude":1.0,"country_code":"FR","country":"France","admin1":"Ailleurs"}]}
        """.utf8)
        let labels = try Weather.decodePlaces(json).map(\.label)
        #expect(labels == [
            "Sedan, Grand Est, France", "Sedan, Ailleurs, France", "Sedan, Kansas, États-Unis", "Sedan, Java central, Indonésie",
        ])
        #expect(try Weather.decodePlaces(json, limit: 2).count == 2)
    }
}

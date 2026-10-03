import AppKit
import EduBarCore
import SwiftUI

/// `EduBar --snapshot <dossier> [--at "yyyy-MM-dd HH:mm"]` : rend le popover et les réglages en PNG
/// (à partir du cache) puis quitte. Sert aux captures du README et à vérifier le rendu.
@MainActor
enum Snapshot {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return }
        let dir = URL(fileURLWithPath: args[i + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let model = AppModel(readKeychainNow: true)
        if let j = args.firstIndex(of: "--at"), j + 1 < args.count {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd HH:mm"
            model.frozenNow = f.date(from: args[j + 1])
        }
        // `--demo` : mêmes horaires, matières et salles fictives (captures publiées).
        let demo = args.contains("--demo")
        if demo { model.snapshotCourses = anonymized(model.schedule.courses) }
        model.tick()
        // Potes factices : tes cours, finis 30 min plus tôt, sans le dernier (ou le premier) de la journée.
        let savedNames = model.friendNames
        let names = demo ? ["Alex", "Sam"] : ["Marvin", "Léa"]
        model.friendNames = names + Array(savedNames.dropFirst(names.count))
        let days = Dictionary(grouping: model.schedule.courses) { model.calendar.startOfDay(for: $0.start) }.values
        let fake = { (keep: (ArraySlice<Course>) -> ArraySlice<Course>) in
            Schedule(courses: days.flatMap { day in
                keep(ArraySlice(day)).map {
                    Course(id: "f-\($0.id)", title: $0.title, start: $0.start, end: $0.end.addingTimeInterval(-1800), room: nil)
                }
            }.sorted { $0.start < $1.start })
        }
        model.snapshotFriends = [
            (names[0], fake { $0.dropLast($0.count > 1 ? 1 : 0) }),
            (names[1], fake { $0.dropFirst($0.count > 1 ? 1 : 0) }),
        ]

        let bar = Text(model.barText.isEmpty ? "(icône seule)" : model.barText).padding(6)
        write(bar, to: dir.appendingPathComponent("bar.png"))
        write(DayView(model: model, openSettings: {}), to: dir.appendingPathComponent("day.png"))
        model.openSettings()
        // Jamais la vraie URL (jetons d'accès) dans une capture.
        model.feedDraft = "webcal://api.edusign.fr/student/account/ical?…"
        model.panel = .templates
        write(SettingsView(model: model), to: dir.appendingPathComponent("settings.png"))
        model.panel = .notifications
        write(SettingsView(model: model), to: dir.appendingPathComponent("notifications.png"))
        model.panel = .alternance
        write(SettingsView(model: model), to: dir.appendingPathComponent("alternance.png"))
        let alternance = model.alternance
        model.alternance.mode = .weekdays
        write(SettingsView(model: model), to: dir.appendingPathComponent("alternance-days.png"))
        model.alternance.mode = .weeks
        model.alternance.schoolAnchor = model.alternance.schoolAnchor ?? model.now
        write(SettingsView(model: model), to: dir.appendingPathComponent("alternance-weeks.png"))
        model.alternance = alternance
        model.panel = .shortcuts
        write(SettingsView(model: model), to: dir.appendingPathComponent("shortcuts.png"))
        model.panel = .friend
        model.friendDraft = "webcal://api.edusign.fr/student/account/ical?…"
        write(SettingsView(model: model), to: dir.appendingPathComponent("friend.png"))
        model.panel = nil
        model.diagnosticCopied = true
        print(model.diagnosticText())
        write(SettingsView(model: model), to: dir.appendingPathComponent("settings-closed.png"))
        write(StatsView(model: model), to: dir.appendingPathComponent("stats.png"))
        model.openWeek()
        write(WeekView(model: model), to: dir.appendingPathComponent("week.png"))
        model.showingWeek = false
        model.step(1)
        write(DayView(model: model, openSettings: {}), to: dir.appendingPathComponent("day-next.png"))
        print("bar: \(model.barText)")
        // Météo factice (jamais la vraie ville dans une capture), sur la journée par défaut.
        model.dayOffset = 0
        let key = { (offset: Int) in
            Weather.dayKey(model.calendar.date(byAdding: .day, value: offset, to: model.now) ?? model.now, calendar: model.calendar)
        }
        let fakeDays = [(3, 8.1, 23.0, 0), (2, 12.5, 24.8, 5), (45, 11.1, 21.3, 10), (80, 14.0, 17.2, 56), (61, 9.4, 15.0, 80)]
        model.snapshotWeather = (Forecast(
            temperature: 22.9, apparent: 22.7, code: 1, isDay: true, wind: 4.1,
            days: fakeDays.enumerated().map { i, d in Forecast.Day(date: key(i), code: d.0, min: d.1, max: d.2, rain: d.3) },
            fetched: model.now
        ), "Paris")
        write(Text(model.barText).padding(6), to: dir.appendingPathComponent("bar-weather.png"))
        write(DayView(model: model, openSettings: {}), to: dir.appendingPathComponent("day-weather.png"))
        print("bar (météo): \(model.barText)")
        model.snapshotWeather = nil
        model.openSettings()
        model.feedDraft = "webcal://api.edusign.fr/student/account/ical?…"
        model.panel = .weather
        let weather = model.weather
        var shown = WeatherSettings(
            enabled: true, place: WeatherPlace(name: "Paris", region: "Île-de-France", country: "France", latitude: 48.85, longitude: 2.35),
            hours: 12
        )
        shown.campus = WeatherPlace(name: "Lyon", region: "Auvergne-Rhône-Alpes", country: "France", latitude: 45.75, longitude: 4.85)
        shown.rainAlert = true
        model.weather = shown
        write(SettingsView(model: model), to: dir.appendingPathComponent("weather.png"))
        // Chaque volet seul, pour illustrer sa fonctionnalité dans le README.
        let panels: [(SettingsPanel, String)] = [
            (.weather, "weather"), (.notifications, "notifications"), (.alternance, "alternance"),
            (.shortcuts, "shortcuts"), (.friend, "friend"), (.templates, "templates"),
        ]
        for (panel, name) in panels {
            model.panel = panel
            if panel == .alternance { model.alternance.mode = .weekdays }
            write(SettingsView(model: model, panelOnly: true), to: dir.appendingPathComponent("panel-\(name).png"))
            if panel == .alternance { model.alternance = alternance }
        }
        model.weather = weather
        model.friendNames = savedNames
        writeBars(to: dir, weather: Forecast(
            temperature: 22.9, apparent: 22.7, code: 1, isDay: true, wind: 4.1, days: [], fetched: model.now
        ))
        exit(0)
    }

    /// Textes de la barre dans chaque situation, sur un emploi du temps inventé (mardi 22/09/2026).
    private static func writeBars(to dir: URL, weather: Forecast) {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "fr_FR")
        let at = { (day: Int, h: Int, m: Int) in
            cal.date(from: DateComponents(year: 2026, month: 9, day: day, hour: h, minute: m))!
        }
        let course = { (id: String, day: Int, start: (Int, Int), end: (Int, Int), room: String, title: String) in
            Course(id: id, title: title, start: at(day, start.0, start.1), end: at(day, end.0, end.1), room: room)
        }
        let tuesday = [
            course("a", 22, (9, 45), (11, 15), "506", "Réseaux"), course("b", 22, (11, 30), (13, 0), "506", "Réseaux"),
            course("c", 22, (14, 0), (15, 30), "501", "Systèmes Linux"), course("d", 22, (15, 45), (17, 15), "501", "Systèmes Linux"),
        ]
        let wednesday = course("e", 23, (9, 45), (11, 15), "501", "Anglais technique")
        let exam = course("x", 23, (9, 0), (11, 0), "501", "Partiel réseaux")
        let monday = course("m", 28, (9, 0), (11, 0), "501", "Réseaux")

        func bar(_ courses: [Course], _ now: Date, company: Bool = false, weather: Forecast? = nil, weekend: Bool = false) -> String {
            let status = Schedule(courses: courses).status(at: now, calendar: cal)
            return Display.barText(
                status: status, alert: RoomChange.alert(for: status, at: now), now: now, calendar: cal,
                companyToday: company, weather: weather.map { ($0, "Paris") }, weekend: weekend
            )
        }
        let week = tuesday + [wednesday]
        let sets: [(String, [String])] = [
            ("glance", [bar(week, at(22, 10, 52)), bar(week, at(22, 11, 22)), bar(week, at(22, 16, 30)), bar(week, at(22, 18, 0))]),
            ("lunch", [bar(week, at(22, 12, 40)), bar(week, at(22, 13, 10))]),
            ("room", [bar(week, at(22, 12, 46))]),
            ("weekend", [bar(tuesday, at(22, 16, 0), weekend: true)]),
            ("exam", [bar(tuesday + [exam], at(22, 18, 0))]),
            ("company", [bar(tuesday + [monday], at(24, 10, 0), company: true)]),
            ("weather", [bar(week, at(22, 18, 0), weather: weather)]),
            ("stale", [bar(week, at(22, 18, 0)) + " ⚠︎"]),
        ]
        for (name, texts) in sets {
            print("bar-\(name): \(texts)")
            let view = VStack(alignment: .trailing, spacing: 6) {
                ForEach(texts, id: \.self) { text in
                    Text(text)
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
            }
            .padding(8)
            write(view, to: dir.appendingPathComponent("bar-\(name).png"))
        }
    }

    private static let demoSubjects = [
        "Réseaux et protocoles", "Algorithmique", "Systèmes Linux", "Anglais technique", "Bases de données",
        "Cybersécurité", "Développement web", "Gestion de projet", "Mathématiques", "Cloud et virtualisation",
    ]

    /// Chaque matière et chaque salle reçoit un nom fictif stable ; horaires et examens sont gardés.
    private static func anonymized(_ courses: [Course]) -> [Course] {
        let subjects = Array(Set(courses.map(\.subjectKey))).sorted()
        let rooms = Array(Set(courses.compactMap(\.room))).sorted()
        return courses.map { c in
            let i = subjects.firstIndex(of: c.subjectKey) ?? 0
            let title = demoSubjects[i % demoSubjects.count] + (c.isExam ? " · examen" : "")
            let room = c.room.flatMap { rooms.firstIndex(of: $0) }.map { "Salle \(101 + 100 * ($0 % 4) + $0 / 4)" }
            return Course(id: "demo-\(c.id)", title: title, start: c.start, end: c.end, room: room)
        }
    }

    private static func write(_ view: some View, to url: URL) {
        // Vue AppKit hors écran plutôt qu'ImageRenderer, qui ne dessine pas les contrôles (boutons, champs).
        for (appearance, suffix) in [(NSAppearance.Name.aqua, ""), (.darkAqua, "-dark")] {
            let host = NSHostingView(rootView: view
                .fixedSize()
                .background(appearance == .darkAqua ? Color(white: 0.16) : Color(white: 0.96)))
            host.appearance = NSAppearance(named: appearance)
            let size = host.fittingSize
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false
            )
            window.appearance = host.appearance
            window.contentView = host
            host.frame = NSRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
            host.cacheDisplay(in: host.bounds, to: rep)
            guard let png = rep.representation(using: .png, properties: [:]) else { continue }
            let name = url.deletingPathExtension().lastPathComponent + suffix + ".png"
            try? png.write(to: url.deletingLastPathComponent().appendingPathComponent(name))
        }
    }
}

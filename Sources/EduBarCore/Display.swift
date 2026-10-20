import Foundation

/// Textes affichés (français ou anglais selon `L10n.current`).
public enum Display {
    /// Arrondi à la minute supérieure : « 23 min », « 1 h », « 1 h 05 ».
    public static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int((seconds / 60).rounded(.up)))
        guard minutes >= 60 else { return "\(minutes) min" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) h" : "\(h) h " + String(format: "%02d", m)
    }

    /// « 8h45 », « 14h » ; en anglais « 8:45 AM », « 2 PM ».
    public static func time(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let h = c.hour ?? 0, m = c.minute ?? 0
        if L10n.current == .en {
            let h12 = h % 12 == 0 ? 12 : h % 12
            let suffix = h < 12 ? "AM" : "PM"
            return m == 0 ? "\(h12) \(suffix)" : "\(h12):" + String(format: "%02d", m) + " \(suffix)"
        }
        return m == 0 ? "\(h)h" : "\(h)h" + String(format: "%02d", m)
    }

    /// « Quai 12 - 501 » devient « 501 ».
    public static func shortRoom(_ room: String) -> String {
        guard let r = room.range(of: " - ", options: .backwards) else { return room }
        let tail = room[r.upperBound...].trimmingCharacters(in: .whitespaces)
        return tail.isEmpty ? room : tail
    }

    static var weekdays: [String] {
        L10n.current == .fr
            ? ["Dim.", "Lun.", "Mar.", "Mer.", "Jeu.", "Ven.", "Sam."]
            : ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    }

    /// « 14h » (aujourd'hui), « Demain 8h45 », « Lun. 8h45 » (< 7 jours), « Lun. 05/10 8h45 ».
    /// En anglais : « Tomorrow 8:45 AM », « Mon 8:45 AM », « Mon 10/05 8:45 AM » (mois/jour).
    public static func dayLabel(_ date: Date, now: Date, calendar: Calendar) -> String {
        let t = time(date, calendar: calendar)
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)
        ).day ?? 0
        switch days {
        case ...0: return t
        case 1: return L10n.tr("Demain \(t)", "Tomorrow \(t)")
        default:
            let wd = weekdays[calendar.component(.weekday, from: date) - 1]
            guard days >= 7 else { return "\(wd) \(t)" }
            let d = calendar.dateComponents([.day, .month], from: date)
            let date = L10n.current == .fr
                ? String(format: "%02d/%02d", d.day ?? 0, d.month ?? 0)
                : String(format: "%02d/%02d", d.month ?? 0, d.day ?? 0)
            return "\(wd) " + date + " \(t)"
        }
    }

    /// Texte de la barre des menus. Chaîne vide : afficher seulement l'icône.
    /// `companyToday` : journée en entreprise (alternance).
    /// `weekend` : dernière suite de cours de la semaine (voir `Schedule.endsWeek`).
    /// `weather` : météo à afficher à la place du prochain cours (il est loin), avec le nom de la ville.
    public static func barText(
        status: Status, alert: RoomAlert?, now: Date, calendar: Calendar, templates: BarTemplates = .defaults,
        companyToday: Bool = false, weather: (forecast: Forecast, city: String)? = nil, weekend: Bool = false
    ) -> String {
        func until(_ date: Date) -> String { duration(date.timeIntervalSince(now)) }
        if let alert {
            return BarTemplates.render(
                templates.pick(\.roomChange), temps: until(alert.from.end), salle: shortRoom(alert.room)
            )
        }
        func exam(_ next: Course, jour: String) -> String {
            BarTemplates.render(
                templates.pick(\.examSoon), temps: until(next.start), salle: next.room.map(shortRoom), jour: jour
            )
        }
        switch status {
        case let .beforeFirst(next), let .onBreak(_, next):
            if next.isExam { return exam(next, jour: L10n.tr("dans \(until(next.start))", "in \(until(next.start))")) }
        case let .dayOver(next?), let .noClassToday(next?):
            if next.isExam, let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
               calendar.isDate(next.start, inSameDayAs: tomorrow) {
                return exam(next, jour: L10n.tr("demain", "tomorrow") + " \(time(next.start, calendar: calendar))")
            }
            if weather == nil, companyToday, case .noClassToday = status {
                return BarTemplates.render(
                    templates.pick(\.company), salle: next.room.map(shortRoom),
                    jour: dayLabel(next.start, now: now, calendar: calendar)
                )
            }
        default: break
        }
        if let weather {
            let next: Course?
            switch status {
            case let .inClass(_, n, _, _), let .dayOver(n), let .noClassToday(n): next = n
            case let .onBreak(_, n), let .beforeFirst(n): next = n
            }
            let f = weather.forecast
            return Template.render(templates.pick(\.weather), [
                "meteo": Weather.condition(f.code, isDay: f.isDay).emoji, "temp": Weather.degrees(f.temperature),
                "ville": weather.city, "jour": next.map { dayLabel($0.start, now: now, calendar: calendar) },
            ])
        }
        switch status {
        case let .inClass(_, _, blockEnd, breakUntil):
            let lunch = breakUntil.map { isLunch(from: blockEnd, to: $0, calendar: calendar) } ?? false
            let t = lunch ? templates.pick(\.beforeLunch)
                : breakUntil != nil ? templates.pick(\.beforeBreak)
                : templates.pick(weekend ? \.lastOfWeek : \.lastClass)
            return BarTemplates.render(t, temps: until(blockEnd), salle: nil)
        case let .onBreak(previous, next):
            let lunch = isLunch(from: previous.end, to: next.start, calendar: calendar)
            let t = templates.pick(lunch ? \.onLunch : \.onBreak)
            return BarTemplates.render(t, temps: until(next.start), salle: next.room.map(shortRoom))
        case let .beforeFirst(next):
            return BarTemplates.render(
                templates.pick(\.beforeFirst), temps: until(next.start), salle: next.room.map(shortRoom)
            )
        case let .dayOver(next), let .noClassToday(next):
            guard let next else { return "" }
            return BarTemplates.render(
                templates.pick(\.dayOver), salle: next.room.map(shortRoom),
                jour: dayLabel(next.start, now: now, calendar: calendar)
            )
        }
    }

    /// Pause déjeuner : au moins 1 h, commencée entre 11h et 14h.
    public static func isLunch(from start: Date, to end: Date, calendar: Calendar) -> Bool {
        end.timeIntervalSince(start) >= 60 * 60 && (11..<14).contains(calendar.component(.hour, from: start))
    }
}

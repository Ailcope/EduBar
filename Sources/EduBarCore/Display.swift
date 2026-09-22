import Foundation

/// Textes affichés (français).
public enum Display {
    /// Arrondi à la minute supérieure : « 23 min », « 1 h », « 1 h 05 ».
    public static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int((seconds / 60).rounded(.up)))
        guard minutes >= 60 else { return "\(minutes) min" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) h" : "\(h) h " + String(format: "%02d", m)
    }

    /// « 8h45 », « 14h ».
    public static func time(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let h = c.hour ?? 0, m = c.minute ?? 0
        return m == 0 ? "\(h)h" : "\(h)h" + String(format: "%02d", m)
    }

    /// « Quai 12 - 501 » devient « 501 ».
    public static func shortRoom(_ room: String) -> String {
        guard let r = room.range(of: " - ", options: .backwards) else { return room }
        let tail = room[r.upperBound...].trimmingCharacters(in: .whitespaces)
        return tail.isEmpty ? room : tail
    }

    static let weekdays = ["Dim.", "Lun.", "Mar.", "Mer.", "Jeu.", "Ven.", "Sam."]

    /// « 14h » (aujourd'hui), « Demain 8h45 », « Lun. 8h45 » (< 7 jours), « Lun. 05/10 8h45 ».
    public static func dayLabel(_ date: Date, now: Date, calendar: Calendar) -> String {
        let t = time(date, calendar: calendar)
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)
        ).day ?? 0
        switch days {
        case ...0: return t
        case 1: return "Demain \(t)"
        default:
            let wd = weekdays[calendar.component(.weekday, from: date) - 1]
            guard days >= 7 else { return "\(wd) \(t)" }
            let d = calendar.dateComponents([.day, .month], from: date)
            return "\(wd) " + String(format: "%02d/%02d", d.day ?? 0, d.month ?? 0) + " \(t)"
        }
    }

    /// Texte de la barre des menus. Chaîne vide : afficher seulement l'icône.
    public static func barText(status: Status, alert: RoomAlert?, now: Date, calendar: Calendar) -> String {
        if let alert {
            return "⚠️ Salle \(shortRoom(alert.room)) · fin dans \(duration(alert.from.end.timeIntervalSince(now)))"
        }
        switch status {
        case let .inClass(_, _, blockEnd, breakUntil):
            let what = breakUntil.map { isLunch(from: blockEnd, to: $0, calendar: calendar) ? "Déjeuner" : "Pause" } ?? "Fin"
            return "📚 \(what) dans \(duration(blockEnd.timeIntervalSince(now)))"
        case let .onBreak(previous, next):
            let icon = isLunch(from: previous.end, to: next.start, calendar: calendar) ? "🍽️" : "☕"
            return "\(icon) Cours dans \(duration(next.start.timeIntervalSince(now)))" + roomSuffix(next)
        case let .beforeFirst(next):
            return "Cours dans \(duration(next.start.timeIntervalSince(now)))" + roomSuffix(next)
        case let .dayOver(next), let .noClassToday(next):
            return next.map { dayLabel($0.start, now: now, calendar: calendar) } ?? ""
        }
    }

    /// Pause déjeuner : au moins 1 h, commencée entre 11h et 14h.
    public static func isLunch(from start: Date, to end: Date, calendar: Calendar) -> Bool {
        end.timeIntervalSince(start) >= 60 * 60 && (11..<14).contains(calendar.component(.hour, from: start))
    }

    static func roomSuffix(_ c: Course) -> String {
        c.room.map { " · \(shortRoom($0))" } ?? ""
    }
}

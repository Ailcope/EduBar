import Foundation

/// Heures faites d'un mois, par matière.
public struct MonthHours: Equatable, Sendable {
    /// Premier jour du mois.
    public let month: Date
    public let subjects: [(title: String, hours: TimeInterval)]
    public var total: TimeInterval { subjects.reduce(0) { $0 + $1.hours } }

    public static func == (a: MonthHours, b: MonthHours) -> Bool {
        a.month == b.month && a.subjects.map(\.title) == b.subjects.map(\.title)
            && a.subjects.map(\.hours) == b.subjects.map(\.hours)
    }
}

/// Relevé d'heures à l'école (alternance : entreprise, OPCO). Seulement les heures faites.
public enum Report {
    /// Mois du plus ancien au plus récent ; matières les plus chargées d'abord.
    public static func monthly(_ courses: [Course], now: Date, calendar: Calendar) -> [MonthHours] {
        var months: [Date: [String: (title: String, hours: TimeInterval)]] = [:]
        for c in courses where c.start < now {
            guard let month = calendar.dateInterval(of: .month, for: c.start)?.start else { continue }
            let hours = max(0, min(c.end, now).timeIntervalSince(c.start))
            months[month, default: [:]][c.subjectKey, default: (c.displayTitle, 0)].hours += hours
        }
        return months.keys.sorted().map { month in
            let subjects = months[month]!.values
                .sorted { ($0.hours, $1.title) > ($1.hours, $0.title) }
                .map { (title: $0.title, hours: $0.hours) }
            return MonthHours(month: month, subjects: subjects)
        }
    }

    /// Tableau séparé par des tabulations : collé dans Excel ou Numbers, il remplit les colonnes.
    public static func table(_ months: [MonthHours], calendar: Calendar) -> String {
        var lines = ["Mois\tMatière\tHeures"]
        for m in months {
            let name = monthName(m.month, calendar: calendar)
            lines += m.subjects.map { "\(name)\t\($0.title)\t\(decimal($0.hours))" }
            lines.append("\(name)\tTotal\t\(decimal(m.total))")
        }
        return lines.joined(separator: "\n")
    }

    /// « septembre 2026 ».
    public static func monthName(_ date: Date, calendar: Calendar) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "LLLL yyyy"
        return f.string(from: date)
    }

    /// Heures décimales à la française, au centième : « 1,5 », « 12,25 ».
    static func decimal(_ seconds: TimeInterval) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: (seconds / 36).rounded() / 100)) ?? "0"
    }
}

import Foundation

/// Jours fériés en France métropolitaine.
public enum Holidays {
    /// Nom du jour férié, ou nil.
    public static func name(of day: Date, calendar: Calendar) -> String? {
        let c = calendar.dateComponents([.year, .month, .day], from: day)
        guard let y = c.year, let m = c.month, let d = c.day else { return nil }
        if let fixed = fixed[m * 100 + d] { return fixed }
        guard let easter = easter(y, calendar: calendar) else { return nil }
        let offset = calendar.dateComponents([.day], from: easter, to: calendar.startOfDay(for: day)).day
        switch offset {
        case 1: return "Lundi de Pâques"
        case 39: return "Ascension"
        case 50: return "Lundi de Pentecôte"
        default: return nil
        }
    }

    /// Jours fériés de lundi à vendredi dans l'intervalle, dans l'ordre.
    public static func weekdays(in interval: DateInterval, calendar: Calendar) -> [(day: Date, name: String)] {
        var result: [(Date, String)] = []
        var day = calendar.startOfDay(for: interval.start)
        while day < interval.end {
            if !calendar.isDateInWeekend(day), let n = name(of: day, calendar: calendar) { result.append((day, n)) }
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return result
    }

    static let fixed: [Int: String] = [
        101: "Jour de l'an", 501: "Fête du travail", 508: "Victoire 1945", 714: "Fête nationale",
        815: "Assomption", 1101: "Toussaint", 1111: "Armistice", 1225: "Noël",
    ]

    /// Dimanche de Pâques (algorithme de Meeus, calendrier grégorien), à minuit.
    static func easter(_ y: Int, calendar: Calendar) -> Date? {
        let a = y % 19, b = y / 100, c = y % 100, d = b / 4, e = b % 4
        let f = (b + 8) / 25, g = (b - f + 1) / 3, h = (19 * a + b - d - g + 15) % 30
        let i = c / 4, k = c % 4, l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31, day = (h + l - 7 * m + 114) % 31 + 1
        return calendar.date(from: DateComponents(year: y, month: month, day: day))
    }
}

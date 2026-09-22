import Foundation

/// Des vacances : au moins une semaine sans cours entre deux cours du flux.
public struct Vacation: Equatable, Sendable {
    /// Premier jour libre (minuit).
    public let start: Date
    /// Jour de la reprise (minuit).
    public let end: Date
}

public enum Vacations {
    /// Les prochaines vacances (ou celles en cours) : `minDays` jours d'affilée ou plus sans cours,
    /// week-ends compris, entre deux jours de cours. `isCompanyDay` : un jour en entreprise coupe la période.
    /// Après le dernier cours du flux, rien : le flux s'arrête, ce ne sont pas forcément des vacances.
    public static func next(
        from now: Date, schedule: Schedule, calendar: Calendar, minDays: Int = 7,
        isCompanyDay: (Date) -> Bool = { _ in false }
    ) -> Vacation? {
        let today = calendar.startOfDay(for: now)
        var days: [Date] = []
        for c in schedule.courses {
            let d = calendar.startOfDay(for: c.start)
            if days.last != d { days.append(d) }
        }
        for (a, b) in zip(days, days.dropFirst()) where b > today {
            var runStart: Date?
            var day = calendar.date(byAdding: .day, value: 1, to: a)!
            while day <= b {
                let free = day < b && !isCompanyDay(day)
                if free {
                    if runStart == nil { runStart = day }
                } else if let s = runStart {
                    runStart = nil
                    let length = calendar.dateComponents([.day], from: s, to: day).day ?? 0
                    if length >= minDays, day > today { return Vacation(start: s, end: day) }
                }
                day = calendar.date(byAdding: .day, value: 1, to: day)!
            }
        }
        return nil
    }

    /// « Vacances dans 12 jours », « Vacances demain », « Vacances · reprise lun. 02/11 ».
    public static func label(_ v: Vacation, now: Date, calendar: Calendar) -> String {
        let today = calendar.startOfDay(for: now)
        if v.start <= today {
            let wd = Display.weekdays[calendar.component(.weekday, from: v.end) - 1].lowercased()
            let d = calendar.dateComponents([.day, .month], from: v.end)
            return "Vacances · reprise \(wd) " + String(format: "%02d/%02d", d.day ?? 0, d.month ?? 0)
        }
        let n = calendar.dateComponents([.day], from: today, to: v.start).day ?? 0
        return n == 1 ? "Vacances demain" : "Vacances dans \(n) jours"
    }
}

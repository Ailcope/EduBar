import Foundation

/// Mise en page de la vue semaine : jours affichés et plage horaire.
public struct WeekGrid: Equatable, Sendable {
    /// Début de chaque jour affiché : lundi à vendredi, plus samedi ou dimanche s'ils ont des cours.
    public let days: [Date]
    /// Première et dernière heure pleine de la grille (8 et 18 au minimum).
    public let firstHour: Int
    public let lastHour: Int

    public init(week day: Date, schedule: Schedule, calendar: Calendar) {
        let start = calendar.dateInterval(of: .weekOfYear, for: day)?.start ?? calendar.startOfDay(for: day)
        let all = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        days = all.filter { !calendar.isDateInWeekend($0) || !schedule.courses(on: $0, calendar: calendar).isEmpty }
        let courses = days.flatMap { schedule.courses(on: $0, calendar: calendar) }
        let starts = courses.map { calendar.component(.hour, from: $0.start) }
        let ends = courses.map { c -> Int in
            let h = calendar.dateComponents([.hour, .minute], from: c.end)
            return (h.hour ?? 0) + ((h.minute ?? 0) > 0 ? 1 : 0)
        }
        firstHour = min(8, starts.min() ?? 8)
        lastHour = max(18, ends.max() ?? 18)
    }

    /// Position verticale d'une heure, de 0 (haut de la grille) à 1 (bas).
    public func position(_ date: Date, calendar: Calendar) -> Double {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let hours = Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
        return min(1, max(0, (hours - Double(firstHour)) / Double(lastHour - firstHour)))
    }
}

import Foundation

/// Heures d'une matière sur tout le flux.
public struct SubjectHours: Equatable, Sendable {
    public let title: String
    /// Déjà passées (cours terminés ou la partie écoulée du cours en cours).
    public let done: TimeInterval
    public let total: TimeInterval
    public let exams: Int

    /// Même clé que `Course.subjectKey`.
    public var key: String { title.lowercased().trimmingCharacters(in: .whitespaces) }
}

public enum Stats {
    /// Durée des cours dans l'intervalle, chaque cours rogné à ses bornes.
    public static func hours(_ courses: [Course], in interval: DateInterval) -> TimeInterval {
        courses.reduce(0) { sum, c in
            let s = max(c.start, interval.start), e = min(c.end, interval.end)
            return sum + max(0, e.timeIntervalSince(s))
        }
    }

    /// Semaine qui contient `day` : heures prévues et déjà faites à `now`.
    public static func week(
        of day: Date, now: Date, schedule: Schedule, calendar: Calendar
    ) -> (done: TimeInterval, total: TimeInterval) {
        guard let w = calendar.dateInterval(of: .weekOfYear, for: day) else { return (0, 0) }
        let total = hours(schedule.courses, in: w)
        let done = now <= w.start ? 0 : hours(schedule.courses, in: DateInterval(start: w.start, end: min(now, w.end)))
        return (done, total)
    }

    /// Par matière (titre sans « T1 - », sans tenir compte de la casse), la plus chargée d'abord.
    public static func bySubject(_ courses: [Course], now: Date) -> [SubjectHours] {
        var order: [String] = []
        var groups: [String: [Course]] = [:]
        for c in courses {
            let key = c.subjectKey
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(c)
        }
        return order.map { key in
            let list = groups[key]!
            let total = list.reduce(0) { $0 + max(0, $1.end.timeIntervalSince($1.start)) }
            let done = list.reduce(0) { $0 + max(0, min($1.end, now).timeIntervalSince($1.start)) }
            return SubjectHours(title: list[0].displayTitle, done: done, total: total, exams: list.filter(\.isExam).count)
        }
        .sorted { ($0.total, $1.title) > ($1.total, $0.title) }
    }
}

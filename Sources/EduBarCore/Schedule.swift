import Foundation

/// Où on en est dans la journée.
public enum Status: Equatable, Sendable {
    /// En cours. `next` : cours suivant du même jour. `blockEnd` : fin des cours enchaînés sans pause.
    /// `breakFollows` : un autre cours suit plus tard dans la journée (donc `blockEnd` est une pause).
    case inClass(current: Course, next: Course?, blockEnd: Date, breakFollows: Bool)
    /// Entre deux cours du même jour.
    case onBreak(previous: Course, next: Course)
    /// Aujourd'hui, avant le premier cours.
    case beforeFirst(next: Course)
    /// Plus de cours aujourd'hui. `next` : prochain cours, n'importe quel jour.
    case dayOver(next: Course?)
    /// Aucun cours aujourd'hui. `next` : prochain cours, n'importe quel jour.
    case noClassToday(next: Course?)
}

public struct Schedule: Sendable {
    public let courses: [Course]

    public init(courses: [Course]) {
        self.courses = courses.sorted { ($0.start, $0.id) < ($1.start, $1.id) }
    }

    public func courses(on day: Date, calendar: Calendar) -> [Course] {
        courses.filter { calendar.isDate($0.start, inSameDayAs: day) }
    }

    public func status(at now: Date, calendar: Calendar) -> Status {
        let today = courses(on: now, calendar: calendar)
        let upcoming = courses.first { $0.start > now }

        // Si deux cours se touchent, l'instant de jonction appartient au suivant.
        if let current = today.last(where: { $0.start <= now && now < $0.end }) {
            let later = today.filter { $0.start >= current.end }
            var blockEnd = current.end
            for c in later where c.start <= blockEnd { blockEnd = max(blockEnd, c.end) }
            return .inClass(
                current: current,
                next: later.first,
                blockEnd: blockEnd,
                breakFollows: later.contains { $0.start > blockEnd }
            )
        }

        guard !today.isEmpty else { return .noClassToday(next: upcoming) }
        guard let next = today.first(where: { $0.start > now }) else { return .dayOver(next: upcoming) }
        guard let previous = today.last(where: { $0.end <= now }) else { return .beforeFirst(next: next) }
        return .onBreak(previous: previous, next: next)
    }
}

import Foundation

/// La journée d'un pote comparée à la tienne.
public struct SharedDay: Equatable, Sendable {
    /// Début de son premier cours et fin de son dernier ce jour-là (nil : pas cours).
    public let friendStart: Date?
    public let friendEnd: Date?
    /// Moments où vous êtes tous les deux à l'école et hors cours.
    public let breaks: [DateInterval]
}

public enum Together {
    /// `minimum` : les trous plus courts ne comptent pas.
    public static func day(
        _ day: Date, mine: Schedule, friend: Schedule, calendar: Calendar, minimum: TimeInterval = 15 * 60
    ) -> SharedDay {
        let theirs = friend.courses(on: day, calendar: calendar)
        let a = gaps(mine.courses(on: day, calendar: calendar))
        let b = gaps(theirs)
        var breaks: [DateInterval] = []
        for x in a {
            for y in b {
                let s = max(x.start, y.start), e = min(x.end, y.end)
                if e.timeIntervalSince(s) >= minimum { breaks.append(DateInterval(start: s, end: e)) }
            }
        }
        return SharedDay(
            friendStart: theirs.map(\.start).min(), friendEnd: theirs.map(\.end).max(),
            breaks: breaks.sorted { $0.start < $1.start }
        )
    }

    /// Trous entre les cours d'une journée (cours qui se chevauchent fusionnés).
    static func gaps(_ courses: [Course]) -> [DateInterval] {
        var result: [DateInterval] = []
        var end: Date?
        for c in courses.sorted(by: { $0.start < $1.start }) {
            if let e = end, c.start > e { result.append(DateInterval(start: e, end: c.start)) }
            end = max(end ?? c.end, c.end)
        }
        return result
    }
}

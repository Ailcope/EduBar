import EduBarCore
import Foundation
import Testing

@Suite struct HistoryTests {
    let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris")!
        return c
    }()

    func at(_ day: Int, _ hour: Int, month: Int = 9) -> Date {
        cal.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    func course(_ id: String, _ day: Int, _ hour: Int, month: Int = 9) -> Course {
        Course(id: id, title: "Cours \(id)", start: at(day, hour, month: month), end: at(day, hour + 1, month: month), room: nil)
    }

    @Test func keepsYesterdayDroppedByTheFeed() {
        let now = at(24, 10)
        let archived = [course("a", 23, 9), course("b", 23, 14)]
        let fresh = [course("c", 24, 9), course("d", 25, 9)]
        let merged = History.merge(archived: archived, fresh: fresh, now: now, calendar: cal)
        #expect(merged.map(\.id) == ["a", "b", "c", "d"])
    }

    @Test func feedWinsFromTodayOn() {
        let now = at(24, 10)
        // Cours d'aujourd'hui ou futur retiré du flux (annulé) : l'archive ne le fait pas revenir.
        let archived = [course("x", 24, 14), course("y", 25, 9)]
        let merged = History.merge(archived: archived, fresh: [course("c", 24, 9)], now: now, calendar: cal)
        #expect(merged.map(\.id) == ["c"])
    }

    @Test func feedVersionReplacesArchivedCopy() {
        let now = at(24, 10)
        let old = Course(id: "a", title: "Ancien", start: at(23, 9), end: at(23, 10), room: "501")
        let new = Course(id: "a", title: "Nouveau", start: at(23, 9), end: at(23, 10), room: "502")
        let merged = History.merge(archived: [old], fresh: [new], now: now, calendar: cal)
        #expect(merged == [new])
    }

    @Test func forgetsBeyondRetention() {
        let now = at(24, 10)
        let ancient = Course(id: "z", title: "Z", start: now.addingTimeInterval(-History.retention - 3600),
                             end: now.addingTimeInterval(-History.retention), room: nil)
        let merged = History.merge(archived: [ancient, course("a", 23, 9)], fresh: [], now: now, calendar: cal)
        #expect(merged.map(\.id) == ["a"])
    }

    @Test func archivesUpToTonight() {
        let now = at(24, 10)
        let all = [course("a", 23, 9), course("b", 24, 8), course("c", 25, 9)]
        #expect(History.archivable(all, now: now, calendar: cal).map(\.id) == ["a", "b"])
    }

    /// Edusign retire la journée à minuit : archivée la veille au soir, elle survit au flux du lendemain.
    @Test func survivesMidnightDrop() {
        let evening = [course("b", 24, 8), course("c", 25, 9)]
        let archived = History.archivable(History.merge(archived: [], fresh: evening, now: at(24, 20), calendar: cal), now: at(24, 20), calendar: cal)
        let next = History.merge(archived: archived, fresh: [course("c", 25, 9)], now: at(25, 0), calendar: cal)
        #expect(next.map(\.id) == ["b", "c"])
    }

    @Test func roundTripsThroughJSON() throws {
        let c = Course(id: "a", title: "T1 - Réseaux", start: at(23, 9), end: at(23, 10), room: "501")
        let data = try JSONEncoder().encode([c])
        #expect(try JSONDecoder().decode([Course].self, from: data) == [c])
    }
}

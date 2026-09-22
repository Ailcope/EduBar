import Foundation
import Testing
@testable import EduBarCore

struct RoomChangeTests {
    func alert(_ schedule: Schedule, _ time: String) -> RoomAlert? {
        let now = at(time)
        return RoomChange.alert(for: schedule.status(at: now, calendar: cal), at: now)
    }

    @Test func alertsWhenRoomChangesWithin15Minutes() {
        #expect(alert(day, "2026-09-22 12:50") == RoomAlert(from: c1, to: c2, room: "Quai 12 - 501"))
        #expect(alert(day, "2026-09-22 12:45") != nil)
    }

    @Test func noAlertOutsideWindow() {
        #expect(alert(day, "2026-09-22 12:40") == nil)
    }

    @Test func noAlertSameRoom() {
        #expect(alert(day, "2026-09-22 11:05") == nil)
        #expect(alert(day, "2026-09-22 15:20") == nil)
    }

    @Test func noAlertWhenNextRoomUnknown() {
        let a = course("a", "2026-09-22 09:00", "2026-09-22 10:00", room: "Quai 12 - 506")
        let b = course("b", "2026-09-22 10:15", "2026-09-22 11:00")
        #expect(alert(Schedule(courses: [a, b]), "2026-09-22 09:55") == nil)
    }

    @Test func alertWhenCurrentRoomUnknown() {
        let a = course("a", "2026-09-22 09:00", "2026-09-22 10:00")
        let b = course("b", "2026-09-22 10:15", "2026-09-22 11:00", room: "Quai 12 - 501")
        #expect(alert(Schedule(courses: [a, b]), "2026-09-22 09:55") == RoomAlert(from: a, to: b, room: "Quai 12 - 501"))
    }

    @Test func noAlertOnBreakOrLastCourse() {
        #expect(alert(day, "2026-09-22 13:30") == nil)
        #expect(alert(day, "2026-09-22 16:50") == nil)
    }

    @Test func roomComparisonIgnoresCaseAndSpaces() {
        let a = course("a", "2026-09-22 09:00", "2026-09-22 10:00", room: "Quai 12 - 506")
        let b = course("b", "2026-09-22 10:15", "2026-09-22 11:00", room: " quai 12 - 506 ")
        #expect(alert(Schedule(courses: [a, b]), "2026-09-22 09:55") == nil)
    }
}

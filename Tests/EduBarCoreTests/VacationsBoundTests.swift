import Foundation
import Testing
@testable import EduBarCore

@Suite struct VacationsBoundTests {
    @Test func farFutureCourseIsFast() {
        let courses = [
            course("a", "2026-10-15 09:00", "2026-10-15 12:00"),
            course("z", "9999-06-01 09:00", "9999-06-01 12:00"),
        ]
        let start = Date()
        let v = Vacations.next(from: at("2026-10-16 10:00"), schedule: Schedule(courses: courses), calendar: cal)
        #expect(Date().timeIntervalSince(start) < 0.05)
        // La période commence le lendemain du dernier cours proche.
        #expect(v?.start == at("2026-10-16 00:00"))
    }
}

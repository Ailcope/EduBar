import Foundation
import Testing
@testable import EduBarCore

let day = Schedule(courses: [c3, c1, c4, c0, c2])

struct ScheduleTests {
    @Test func inClassWithBreakAfter() {
        #expect(day.status(at: at("2026-09-22 10:00"), calendar: cal)
            == .inClass(current: c0, next: c1, blockEnd: c0.end, breakFollows: true))
    }

    @Test func contiguousBlockSkipsZeroMinuteBreak() {
        #expect(day.status(at: at("2026-09-22 14:30"), calendar: cal)
            == .inClass(current: c2, next: c3, blockEnd: c3.end, breakFollows: false))
    }

    @Test func boundaryBelongsToNextCourse() {
        #expect(day.status(at: at("2026-09-22 15:30"), calendar: cal)
            == .inClass(current: c3, next: nil, blockEnd: c3.end, breakFollows: false))
    }

    @Test func onBreak() {
        #expect(day.status(at: at("2026-09-22 11:20"), calendar: cal) == .onBreak(previous: c0, next: c1))
        #expect(day.status(at: at("2026-09-22 13:00"), calendar: cal) == .onBreak(previous: c1, next: c2))
    }

    @Test func beforeFirst() {
        #expect(day.status(at: at("2026-09-22 08:00"), calendar: cal) == .beforeFirst(next: c0))
    }

    @Test func dayOver() {
        #expect(day.status(at: at("2026-09-22 18:00"), calendar: cal) == .dayOver(next: c4))
        #expect(day.status(at: at("2026-09-23 12:00"), calendar: cal) == .dayOver(next: nil))
    }

    @Test func noClassToday() {
        #expect(day.status(at: at("2026-09-21 10:00"), calendar: cal) == .noClassToday(next: c0))
        #expect(day.status(at: at("2026-09-26 10:00"), calendar: cal) == .noClassToday(next: nil))
        #expect(Schedule(courses: []).status(at: at("2026-09-22 10:00"), calendar: cal) == .noClassToday(next: nil))
    }

    @Test func coursesOnDaySorted() {
        #expect(day.courses(on: at("2026-09-22 00:00"), calendar: cal) == [c0, c1, c2, c3])
        #expect(day.courses(on: at("2026-09-24 00:00"), calendar: cal).isEmpty)
    }
}

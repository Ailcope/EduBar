import Foundation
import Testing
@testable import EduBarCore

struct ICSParserTests {
    let courses = ICSParser.parse(fixture("sample"))

    @Test func parsesTimedEventsSortedByStart() {
        #expect(courses.map(\.id) == ["evt-1@example", "evt-2@example", "evt-3@example", "evt-4@example"])
        let first = courses[0]
        #expect(first.title == "T1 - langage c avancé")
        #expect(first.start == at("2026-09-22 09:45"))
        #expect(first.end == at("2026-09-22 11:15"))
        #expect(first.room == "Quai 12 - 506")
        #expect(first.shortTitle == "langage c avancé")
    }

    @Test func unfoldsAndUnescapes() {
        #expect(courses[1].title == "T1 - sécurité, réseaux et vulnérabilités informatiques")
    }

    @Test func missingOrBlankLocationIsNil() {
        #expect(courses[2].room == nil)
        #expect(courses[3].room == nil)
    }

    @Test func tzidIsHonoured() {
        #expect(courses[2].start == at("2026-09-22 13:45"))
        #expect(courses[2].end == at("2026-09-22 15:15"))
    }

    @Test func allDayEventsSkipped() {
        #expect(!courses.contains { $0.title == "Férié" })
    }

    @Test func garbageGivesNoCourses() {
        #expect(ICSParser.parse("<html>nope</html>").isEmpty)
    }

    @Test func shortTitleKeepsTitlesWithoutPrefix() {
        #expect(course("x", "2026-09-22 09:00", "2026-09-22 10:00", title: "Réunion").shortTitle == "Réunion")
    }
}

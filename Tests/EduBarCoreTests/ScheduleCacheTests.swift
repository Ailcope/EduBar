import Foundation
import Testing
@testable import EduBarCore

@Suite struct ScheduleCacheTests {
    @Test func reusesWhileCoursesAreUnchanged() {
        let cache = ScheduleCache()
        let courses = [course("a", "2026-10-15 09:00", "2026-10-15 12:00")]
        #expect(cache.schedule(for: courses).courses == cache.schedule(for: courses).courses)
    }

    @Test func invalidatesOnAnyChange() {
        let cache = ScheduleCache()
        let a = course("a", "2026-10-15 09:00", "2026-10-15 12:00")
        let b = course("b", "2026-10-14 09:00", "2026-10-14 12:00")
        #expect(cache.schedule(for: [a]).courses.map(\.id) == ["a"])
        // Ajout
        #expect(cache.schedule(for: [a, b]).courses.map(\.id) == ["b", "a"])
        // Retrait (filtre d'évènements)
        #expect(cache.schedule(for: [b]).courses.map(\.id) == ["b"])
        // Même id, salle changée
        let moved = course("b", "2026-10-14 09:00", "2026-10-14 12:00", room: "501")
        #expect(cache.schedule(for: [moved]).courses.first?.room == "501")
        // Vide (mode démo vers rien)
        #expect(cache.schedule(for: []).courses.isEmpty)
    }
}

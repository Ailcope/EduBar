import Foundation
import Testing
@testable import EduBarCore

@Suite struct VacationsBoundTests {
    /// Un évènement égaré en 9999 : ni vacances jusqu'en 9999, ni boucle sur des millions de jours.
    @Test func farFutureCourseIsIgnoredAndFast() {
        let courses = [
            course("a", "2026-10-15 09:00", "2026-10-15 12:00"),
            course("z", "9999-06-01 09:00", "9999-06-01 12:00"),
        ]
        var visited = 0
        let v = Vacations.next(
            from: at("2026-10-16 10:00"), schedule: Schedule(courses: courses), calendar: cal,
            isCompanyDay: { _ in visited += 1; return false }
        )
        #expect(v == nil)
        #expect(visited == 0)
    }

    /// Les vraies vacances avant l'évènement égaré sont toujours trouvées.
    @Test func realVacationBeforeStrayEventIsKept() {
        let courses = [
            course("a", "2026-10-15 09:00", "2026-10-15 12:00"),
            course("b", "2026-11-02 09:00", "2026-11-02 12:00"),
            course("z", "9999-06-01 09:00", "9999-06-01 12:00"),
        ]
        let v = Vacations.next(from: at("2026-10-16 10:00"), schedule: Schedule(courses: courses), calendar: cal)
        #expect(v == Vacation(start: at("2026-10-16 00:00"), end: at("2026-11-02 00:00")))
    }

    /// Un jour en entreprise coupe toujours la période, même avec un évènement égaré dans le flux.
    @Test func companyDaysStillCutRunsWithStrayEvent() {
        let courses = [
            course("a", "2026-10-15 09:00", "2026-10-15 12:00"),
            course("b", "2026-11-02 09:00", "2026-11-02 12:00"),
            course("z", "9999-06-01 09:00", "9999-06-01 12:00"),
        ]
        // En entreprise du mercredi au vendredi : jamais 7 jours libres d'affilée.
        let v = Vacations.next(
            from: at("2026-10-16 10:00"), schedule: Schedule(courses: courses), calendar: cal,
            isCompanyDay: { (4...6).contains(cal.component(.weekday, from: $0)) }
        )
        #expect(v == nil)
    }
}

import Foundation
import Testing
@testable import EduBarCore

@Suite struct ExamTests {
    @Test func detectsExamWords() {
        for t in ["T1 - Examen langage C", "partiel réseaux", "DS de maths", "Contrôle continu", "Soutenance projet",
                  "QCM git", "Évaluation finale", "rattrapage", "Épreuve écrite"] {
            #expect(course("x", "2026-09-22 09:00", "2026-09-22 10:00", title: t).isExam, "\(t)")
        }
    }

    @Test func ignoresOrdinaryTitles() {
        for t in ["T1 - langage c avancé", "gestion de projets", "bloc électif m2 développement android", "Design system"] {
            #expect(!course("x", "2026-09-22 09:00", "2026-09-22 10:00", title: t).isExam, "\(t)")
        }
    }

    @Test func displayTitleCapitalizes() {
        #expect(c0.displayTitle == "Cours c0")
    }
}

@Suite struct BlockTests {
    @Test func groupsBackToBackCourses() {
        let b = Schedule(courses: [c0, c1, c2, c3, c4]).blocks(on: at("2026-09-22 08:00"), calendar: cal)
        #expect(b.map { [$0.first.id, $0.last.id] } == [["c0", "c0"], ["c1", "c1"], ["c2", "c3"]])
        #expect(b[2].end == at("2026-09-22 17:00"))
    }
}

@Suite struct ScheduleDiffTests {
    let now = at("2026-09-21 20:00")
    let old = [c0, c1, c2, c3, c4]

    func diff(_ new: [Course]) -> [ScheduleChange] { ScheduleDiff.changes(from: old, to: new, now: now) }

    @Test func noChangeGivesNothing() {
        #expect(diff(old).isEmpty)
        #expect(ScheduleDiff.changes(from: [], to: old, now: now).isEmpty)
        #expect(ScheduleDiff.changes(from: old, to: [], now: now).isEmpty)
    }

    @Test func cancelledAndAdded() {
        let extra = course("c9", "2026-09-24 09:00", "2026-09-24 10:30", room: "Quai 12 - 402", title: "T1 - réseaux")
        #expect(diff([c0, c1, c3, c4, extra]) == [.cancelled(c2), .added(extra)])
    }

    @Test func movedAndRoomChanged() {
        let moved = course("c1", "2026-09-23 14:00", "2026-09-23 15:30", room: "Quai 12 - 506")
        let room = course("c2", "2026-09-22 14:00", "2026-09-22 15:30", room: "Quai 12 - 402")
        #expect(diff([c0, moved, room, c3, c4]) == [.roomChanged(from: c2, to: room), .moved(from: c1, to: moved)])
    }

    @Test func regeneratedUIDWithSameTitleIsAMove() {
        let again = course("new-id", "2026-09-22 16:00", "2026-09-22 17:30", room: "Quai 12 - 506", title: c1.title)
        #expect(diff([c0, again, c2, c3, c4]) == [.moved(from: c1, to: again)])
    }

    @Test func ignoresPastAndFarCourses() {
        let later = at("2026-09-22 12:00")
        #expect(ScheduleDiff.changes(from: old, to: [c1, c2, c3, c4], now: later).isEmpty)
        let far = course("f", "2026-11-02 09:00", "2026-11-02 10:00")
        #expect(ScheduleDiff.changes(from: old + [far], to: old, now: now).isEmpty)
    }

    @Test func notificationTexts() {
        let n = ScheduleDiff.notifications([.cancelled(c2)], now: at("2026-09-22 08:00"), calendar: cal)
        #expect(n.map(\.title) == ["❌ Cours annulé · aujourd'hui 14h"])
        #expect(n[0].body == "Cours c2 (14h-15h30) n'est plus au planning.")
        let room = course("c4", "2026-09-23 09:45", "2026-09-23 11:15", room: "Quai 12 - 501")
        let r = ScheduleDiff.notifications([.roomChanged(from: c4, to: room)], now: at("2026-09-22 08:00"), calendar: cal)
        #expect(r[0].title == "📍 Salle changée · 501")
        #expect(r[0].body == "Cours c4, Demain 9h45 : salle non indiquée → 501")
    }

    @Test func manyChangesAreSummed() {
        let changes = old.map(ScheduleChange.cancelled)
        let n = ScheduleDiff.notifications(changes, now: now, calendar: cal)
        #expect(n.count == 1)
        #expect(n[0].body.hasPrefix("5 changements"))
    }
}

@Suite struct AlternanceTests {
    let schedule = Schedule(courses: [c0, c1, c2, c3, c4])
    // Mar. 22/09 et mer. 23/09 ont des cours ; jeu. 24 et ven. 25 non ; sam. 26.
    func company(_ a: Alternance, _ day: String) -> Bool {
        a.isCompanyDay(at("\(day) 10:00"), schedule: schedule, calendar: cal)
    }

    @Test func offNeverAndCoursesAlwaysSchool() {
        #expect(!company(.defaults, "2026-09-24"))
        var a = Alternance.defaults
        a.mode = .weekdays
        a.companyWeekdays = [3]
        #expect(!company(a, "2026-09-22"))
    }

    @Test func autoMarksWeekdaysWithoutCourses() {
        var a = Alternance.defaults
        a.mode = .auto
        #expect(company(a, "2026-09-24"))
        #expect(!company(a, "2026-09-23"))
        #expect(!company(a, "2026-09-26"))
    }

    @Test func fixedWeekdays() {
        var a = Alternance.defaults
        a.mode = .weekdays
        a.companyWeekdays = [5]
        #expect(company(a, "2026-09-24"))
        #expect(!company(a, "2026-09-25"))
    }

    @Test func alternatingWeeks() {
        var a = Alternance.defaults
        a.mode = .weeks
        a.schoolWeeks = 1
        a.companyWeeks = 2
        a.schoolAnchor = at("2026-09-23 12:00")
        #expect(!company(a, "2026-09-24"))
        #expect(company(a, "2026-09-29"))
        #expect(company(a, "2026-10-09"))
        #expect(!company(a, "2026-10-13"))
        #expect(company(a, "2026-09-15"))
        a.schoolAnchor = nil
        #expect(!company(a, "2026-09-29"))
    }

    @Test func decodesPartialSettings() throws {
        let a = try JSONDecoder().decode(Alternance.self, from: Data(#"{"mode":"auto"}"#.utf8))
        #expect(a.mode == .auto)
        #expect(a.companyWeekdays == Alternance.defaults.companyWeekdays)
    }
}

@Suite struct StatsTests {
    let schedule = Schedule(courses: [c0, c1, c2, c3, c4])

    @Test func weekHours() {
        let w = Stats.week(of: at("2026-09-22 12:00"), now: at("2026-09-22 12:00"), schedule: schedule, calendar: cal)
        #expect(w.total == 7.5 * 3600)
        #expect(w.done == 2 * 3600)
        let next = Stats.week(of: at("2026-09-29 12:00"), now: at("2026-09-22 12:00"), schedule: schedule, calendar: cal)
        #expect(next.total == 0 && next.done == 0)
    }

    @Test func perSubject() {
        let a = course("a", "2026-09-21 09:00", "2026-09-21 11:00", title: "T1 - réseaux")
        let b = course("b", "2026-09-28 09:00", "2026-09-28 10:00", title: "T2 - Réseaux")
        let e = course("e", "2026-09-29 09:00", "2026-09-29 12:00", title: "T1 - partiel C")
        let s = Stats.bySubject([a, b, e], now: at("2026-09-22 12:00"))
        #expect(s.map(\.title) == ["Partiel C", "Réseaux"])
        #expect(s[1].total == 3 * 3600 && s[1].done == 2 * 3600)
        #expect(s[0].exams == 1)
    }
}

@Suite struct ShortcutTests {
    let schedule = Schedule(courses: [c0, c1, c2, c3, c4])

    @Test func runsAtBlockStartAndEnd() {
        let s = ShortcutSettings(atStart: "Concentration", atEnd: " Fin ")
        #expect(s.due(schedule: schedule, at: at("2026-09-22 14:00"), calendar: cal).map(\.name) == ["Concentration"])
        #expect(s.due(schedule: schedule, at: at("2026-09-22 15:30"), calendar: cal).isEmpty)
        #expect(s.due(schedule: schedule, at: at("2026-09-22 17:01"), calendar: cal).map(\.name) == ["Fin"])
        #expect(s.due(schedule: schedule, at: at("2026-09-22 17:03"), calendar: cal).isEmpty)
        #expect(ShortcutSettings.defaults.due(schedule: schedule, at: at("2026-09-22 14:00"), calendar: cal).isEmpty)
    }
}

@Suite struct ExamAndCompanyBarTests {
    func bar(_ courses: [Course], _ now: String, company: Bool = false) -> String {
        let s = Schedule(courses: courses)
        let d = at(now)
        return Display.barText(status: s.status(at: d, calendar: cal), alert: nil, now: d, calendar: cal, companyToday: company)
    }

    let exam = course("x", "2026-09-23 09:00", "2026-09-23 12:00", room: "Quai 12 - 501", title: "T1 - partiel réseaux")

    @Test func examTomorrowAndToday() {
        #expect(bar([c0, exam], "2026-09-22 18:00") == "📝 Examen demain 9h · 501")
        #expect(bar([exam], "2026-09-23 08:35") == "📝 Examen dans 25 min · 501")
        #expect(bar([exam], "2026-09-21 18:00") != "📝 Examen demain 9h · 501")
    }

    @Test func companyDay() {
        #expect(bar([c4], "2026-09-22 10:00", company: true) == "🏢 Entreprise · école Demain 9h45")
        #expect(bar([c4], "2026-09-22 10:00") == "Demain 9h45")
    }
}

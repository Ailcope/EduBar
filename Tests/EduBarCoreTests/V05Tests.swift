import Foundation
import Testing
@testable import EduBarCore

@Suite struct VacationTests {
    // Ven. 16/10, puis reprise lun. 02/11 (Toussaint) ; semaines normales autour.
    let courses = [
        course("a", "2026-10-15 09:00", "2026-10-15 12:00"),
        course("b", "2026-10-16 09:00", "2026-10-16 12:00"),
        course("c", "2026-10-19 09:00", "2026-10-19 12:00"),
        course("d", "2026-11-02 09:00", "2026-11-02 12:00"),
    ]

    func next(_ now: String, company: @escaping (Date) -> Bool = { _ in false }) -> Vacation? {
        Vacations.next(from: at(now), schedule: Schedule(courses: courses), calendar: cal, isCompanyDay: company)
    }

    @Test func findsTheWeekOffNotWeekends() {
        let v = next("2026-10-01 10:00")
        #expect(v == Vacation(start: at("2026-10-20 00:00"), end: at("2026-11-02 00:00")))
        #expect(Vacations.label(v!, now: at("2026-10-01 10:00"), calendar: cal) == "Vacances dans 19 jours")
        #expect(Vacations.label(v!, now: at("2026-10-19 18:00"), calendar: cal) == "Vacances demain")
    }

    @Test func duringVacationGivesReturnDay() {
        let v = next("2026-10-25 10:00")
        #expect(v?.end == at("2026-11-02 00:00"))
        #expect(Vacations.label(v!, now: at("2026-10-25 10:00"), calendar: cal) == "Vacances · reprise lun. 02/11")
    }

    @Test func nothingAfterReturnOrAfterFeedEnd() {
        #expect(next("2026-11-02 08:00") == nil)
        #expect(next("2026-12-01 08:00") == nil)
    }

    @Test func companyDaysAreNotVacation() {
        // Semaine d'entreprise du 26 au 30/10 : il reste deux morceaux de moins de 7 jours.
        let company: (Date) -> Bool = { d in d >= at("2026-10-26 00:00") && d < at("2026-10-31 00:00") }
        #expect(next("2026-10-01 10:00", company: company) == nil)
    }
}

@Suite struct SubjectColorTests {
    @Test func stableAndDistinct() {
        let keys = ["langage c avancé", "réseaux", "anglais", "gestion de projets", "maths", "git", "linux", "design"]
        let a = SubjectColors.assign(keys, count: 11)
        #expect(a == SubjectColors.assign(keys.reversed(), count: 11))
        #expect(Set(a.values).count == keys.count)
        #expect(a.values.allSatisfy { (0..<11).contains($0) })
        #expect(SubjectColors.fnv1a("réseaux") == SubjectColors.fnv1a("réseaux"))
    }

    @Test func moreSubjectsThanColorsStillWorks() {
        let a = SubjectColors.assign((0..<30).map { "m\($0)" }, count: 5)
        #expect(a.count == 30)
        #expect(a.values.allSatisfy { (0..<5).contains($0) })
    }

    @Test func keysMatchStats() {
        let c = course("x", "2026-09-22 09:00", "2026-09-22 10:00", title: "T1 - langage C")
        let s = Stats.bySubject([c], now: at("2026-09-22 12:00"))
        #expect(s[0].key == c.subjectKey)
    }
}

@Suite struct TogetherTests {
    // Moi : c0 9h45-11h15, c1 11h30-13h, c2+c3 14h-17h.
    let mine = Schedule(courses: [c0, c1, c2, c3, c4])

    @Test func sharedBreaksAndEnd() {
        let friend = Schedule(courses: [
            course("f0", "2026-09-22 09:00", "2026-09-22 12:30"),
            course("f1", "2026-09-22 14:30", "2026-09-22 15:30"),
        ])
        let d = Together.day(at("2026-09-22 08:00"), mine: mine, friend: friend, calendar: cal)
        #expect(d.friendStart == at("2026-09-22 09:00"))
        #expect(d.friendEnd == at("2026-09-22 15:30"))
        // Moi libre 11h15-11h30 et 13h-14h ; lui 12h30-14h30 : commun 13h-14h seulement.
        #expect(d.breaks == [DateInterval(start: at("2026-09-22 13:00"), end: at("2026-09-22 14:00"))])
    }

    @Test func shortOverlapsIgnoredAndNoClass() {
        let friend = Schedule(courses: [
            course("f0", "2026-09-22 09:00", "2026-09-22 13:50"),
            course("f1", "2026-09-22 14:00", "2026-09-22 15:00"),
        ])
        #expect(Together.day(at("2026-09-22 08:00"), mine: mine, friend: friend, calendar: cal).breaks.isEmpty)
        let off = Together.day(at("2026-09-24 08:00"), mine: mine, friend: friend, calendar: cal)
        #expect(off.friendEnd == nil && off.breaks.isEmpty)
    }

    @Test func gapsMergeOverlaps() {
        let g = Together.gaps([
            course("a", "2026-09-22 09:00", "2026-09-22 11:00"),
            course("b", "2026-09-22 10:00", "2026-09-22 12:00"),
            course("c", "2026-09-22 13:00", "2026-09-22 14:00"),
        ])
        #expect(g == [DateInterval(start: at("2026-09-22 12:00"), end: at("2026-09-22 13:00"))])
    }
}

@Suite struct DiagnosticTests {
    @Test func neverLeaksURLs() {
        let text = Diagnostic.render([
            ("Version", "0.5.0"),
            ("Erreur", "échec pour webcal://example.invalid/ical?sc=abc123&st=def456 ici"),
            ("Autre", "https://example.invalid/x token=zzz"),
            ("Params", "?sc=abc123&st=def456"),
        ])
        #expect(text.hasPrefix("EduBar · diagnostic\nVersion : 0.5.0"))
        for secret in ["example.invalid", "abc123", "def456", "zzz"] { #expect(!text.contains(secret)) }
        #expect(text.contains("[URL masquée] ici"))
    }
}

@Suite struct HolidayTests {
    @Test func fixedAndEasterBased() {
        #expect(Holidays.name(of: at("2026-11-11 10:00"), calendar: cal) == "Armistice")
        #expect(Holidays.name(of: at("2026-11-01 00:00"), calendar: cal) == "Toussaint")
        // Pâques 2026 : 5 avril ; 2027 : 28 mars.
        #expect(Holidays.name(of: at("2026-04-06 09:00"), calendar: cal) == "Lundi de Pâques")
        #expect(Holidays.name(of: at("2026-05-14 09:00"), calendar: cal) == "Ascension")
        #expect(Holidays.name(of: at("2026-05-25 09:00"), calendar: cal) == "Lundi de Pentecôte")
        #expect(Holidays.name(of: at("2027-03-29 09:00"), calendar: cal) == "Lundi de Pâques")
        #expect(Holidays.name(of: at("2026-09-22 09:00"), calendar: cal) == nil)
    }

    @Test func weekdaysOnlyInInterval() {
        let nov = DateInterval(start: at("2026-11-01 00:00"), end: at("2026-11-16 00:00"))
        // 01/11 est un dimanche : seul le mercredi 11/11 reste.
        #expect(Holidays.weekdays(in: nov, calendar: cal).map(\.name) == ["Armistice"])
    }

    @Test func holidayIsNotACompanyDay() {
        var a = Alternance.defaults
        a.mode = .auto
        #expect(!a.isCompanyDay(at("2026-11-11 10:00"), schedule: Schedule(courses: []), calendar: cal))
        #expect(a.isCompanyDay(at("2026-11-12 10:00"), schedule: Schedule(courses: []), calendar: cal))
    }
}

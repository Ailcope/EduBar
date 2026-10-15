import Foundation
import Testing
@testable import EduBarCore

func jsonFixture(_ name: String) -> Data {
    let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!
    return try! Data(contentsOf: url)
}

struct MyGESTests {
    // MARK: Jeton

    @Test func tokenParsesFragmentWithoutDecoding() {
        let t = KordisToken.parse(
            location: "comreseaugesskolae://oauth2redirect#access_token=abc+def&token_type=bearer&expires_in=3600&scope=read&uid=123")
        #expect(t == KordisToken(accessToken: "abc+def", tokenType: "bearer", expiresIn: 3600, uid: "123"))
    }

    @Test func tokenWithoutAccessTokenIsNil() {
        #expect(KordisToken.parse(location: "x://y#token_type=bearer&uid=1") == nil)
    }

    @Test func tokenWithoutFragmentIsNil() {
        #expect(KordisToken.parse(location: "x://y?access_token=abc") == nil)
    }

    // MARK: Agenda

    @Test func agendaEnvelopeMapsCourses() throws {
        let events = try GESAgenda.events(from: jsonFixture("kordis-agenda"))
        #expect(events.count == 3)
        let courses = GESAgenda.courses(from: events)
        #expect(courses.map(\.id) == ["ges-4821", "ges-4822", "ges-4823"])
        #expect(courses[0].title == "T1 - Sécurité des réseaux")
        #expect(courses[0].room == "Quai 12 - 506 · Quai 12 - 507")
        #expect(courses[0].teacher == "Prénom NOM")
        #expect(courses[0].modality == "Présentiel")
        #expect(courses[0].start == Date(timeIntervalSince1970: 1790581500))
    }

    @Test func agendaNoRoomAndTeacherFallsBackToDiscipline() throws {
        let courses = GESAgenda.courses(from: try GESAgenda.events(from: jsonFixture("kordis-agenda")))
        #expect(courses[1].room == nil)
        #expect(courses[1].teacher == "Autre NOM")
        #expect(courses[1].modality == "Distanciel")
    }

    @Test func agendaStringDatesAreDecoded() throws {
        let courses = GESAgenda.courses(from: try GESAgenda.events(from: jsonFixture("kordis-agenda")))
        #expect(courses[2].start == Date(timeIntervalSince1970: 1790665200))
        #expect(courses[2].end == Date(timeIntervalSince1970: 1790670600))
        #expect(courses[2].modality == nil)
    }

    @Test func agendaBareArrayAndFallbacks() throws {
        let json = #"[{"name":"  ","start_date":60000,"end_date":120000,"discipline":{"name":"Maths"}},{"name":"A","start_date":1000,"end_date":2000}]"#
        let courses = GESAgenda.courses(from: try GESAgenda.events(from: Data(json.utf8)))
        #expect(courses.map(\.title) == ["A", "Maths"])
        #expect(courses[0].id == "1000-A")
    }

    @Test func agendaIgnoresEventsWithoutValidDates() throws {
        let json = #"[{"name":"sans dates"},{"name":"inverse","start_date":2000,"end_date":1000},{"name":"ok","start_date":1000,"end_date":2000}]"#
        let courses = GESAgenda.courses(from: try GESAgenda.events(from: Data(json.utf8)))
        #expect(courses.map(\.title) == ["ok"])
    }

    @Test func agendaSortedByStartThenId() throws {
        let json = #"[{"reservation_id":2,"name":"b","start_date":5000,"end_date":6000},{"reservation_id":1,"name":"a","start_date":5000,"end_date":6000},{"reservation_id":3,"name":"c","start_date":1000,"end_date":2000}]"#
        let courses = GESAgenda.courses(from: try GESAgenda.events(from: Data(json.utf8)))
        #expect(courses.map(\.id) == ["ges-3", "ges-1", "ges-2"])
    }

    // MARK: Notes

    @Test func gradesAreDecodedFromRealShape() throws {
        let book = try GESGrades.gradeBook(from: jsonFixture("kordis-grades"))
        #expect(book.subjects.count == 4)
        let a = book.subjects[0], b = book.subjects[1], c = book.subjects[2], d = book.subjects[3]
        #expect(a.grades == [18] && a.exam == 17 && a.average == 17.5 && a.ccAverage == 18)
        #expect(a.coef == 2 && a.ects == 2 && a.trimester == 120 && a.year == 2026)
        #expect(a.trimesterName == "Semestre 1" && a.letterMark == "A" && a.rcID == 357696)
        #expect(a.absences == 0 && a.lates == 0)
        #expect(b.grades.isEmpty && b.exam == nil && b.average == nil && b.ccAverage == nil)
        #expect(b.coef == nil && b.letterMark == nil && b.absences == 2 && b.lates == 1)
        #expect(c.grades == [12.5, 14, 9.5] && c.exam == 13 && c.coef == 3 && c.letterMark == "C")
        #expect(d.coef == nil && d.letterMark == nil && d.trimester == 121)
    }

    @Test func gradesTeacherIsConcatenated() throws {
        let book = try GESGrades.gradeBook(from: jsonFixture("kordis-grades"))
        #expect(book.subjects[0].teacher == "M. Prénom NOM")
        #expect(book.subjects[1].teacher == "Mme Autre NOM")
        #expect(book.subjects[3].teacher == nil)
    }

    @Test func gradesLenientValuesStillWork() throws {
        let json = #"[{"course":"X","grades":[12.5,"9,5",{"grade":15}],"exam":"13.5","average":"","ccaverage":0,"coef":"2","trimester":"3"}]"#
        let s = try GESGrades.gradeBook(from: Data(json.utf8)).subjects[0]
        #expect(s.grades == [12.5, 9.5, 15] && s.exam == 13.5 && s.average == nil && s.ccAverage == nil)
        #expect(s.coef == 2 && s.trimester == 3)
    }

    @Test func gradesShortCourseAndBareArray() throws {
        let book = try GESGrades.gradeBook(from: Data(#"[{"course":"T2 - Droit","grades":[10]}]"#.utf8))
        #expect(book.subjects[0].shortCourse == "Droit")
        #expect(book.subjects[0].id == "0#0#T2 - Droit")
    }

    @Test func subjectIDIncludesYear() {
        let a = GradeBook.Subject(course: "Maths", trimester: 120, year: 2025)
        let b = GradeBook.Subject(course: "Maths", trimester: 120, year: 2026)
        #expect(a.id == "2025#120#Maths" && a.id != b.id)
    }

    @Test func subjectDecodesOldArchiveAndRecomputesID() throws {
        let old = #"{"id":"Maths#1","course":"Maths","grades":[10],"trimester":1,"year":2026}"#
        let s = try JSONDecoder().decode(GradeBook.Subject.self, from: Data(old.utf8))
        #expect(s.id == "2026#1#Maths" && s.trimesterName == nil && s.rcID == nil && s.absences == nil)
    }

    @Test func subjectRoundTrips() throws {
        let s = GradeBook.Subject(course: "M", grades: [1], trimester: 120, year: 2026, trimesterName: "Semestre 1",
                                  letterMark: "B", absences: 1, lates: 2, rcID: 9)
        #expect(try JSONDecoder().decode(GradeBook.Subject.self, from: JSONEncoder().encode(s)) == s)
    }

    // MARK: Périodes

    @Test func periodsSortedAndUnique() throws {
        let book = GradeBook(subjects: [
            .init(course: "a", trimester: 110, year: 2025, trimesterName: "Semestre 2"),
            .init(course: "b", trimester: 120, year: 2026, trimesterName: "Semestre 1"),
            .init(course: "c", trimester: 121, year: 2026, trimesterName: "Semestre 2"),
            .init(course: "d", trimester: 121, year: 2026, trimesterName: "Semestre 2"),
            .init(course: "e", trimester: 5),
        ])
        #expect(book.periods.map(\.id) == ["2026#121", "2026#120", "2025#110"])
    }

    @Test func periodTitles() {
        let p = GradeBook.Period(year: 2026, trimester: 120, name: "Semestre 1")
        #expect(p.id == "2026#120")
        #expect(p.title == "2026-2027 · Semestre 1")
        #expect(p.shortTitle == "S1 2026-27")
        #expect(GradeBook.Period(year: 2099, trimester: 1, name: "Trimestre libre").shortTitle == "Trimestre libre")
        #expect(GradeBook.Period(year: 2099, trimester: 1, name: "Semestre 2").shortTitle == "S2 2099-00")
    }

    @Test func subjectsInPeriodSortedByShortCourse() throws {
        let book = try GESGrades.gradeBook(from: jsonFixture("kordis-grades"))
        let s2 = GradeBook.Period(year: 2026, trimester: 121, name: "Semestre 2")
        #expect(book.subjects(in: s2).map(\.shortCourse) == ["anglais", "Langage C avancé"])
        let s1 = GradeBook.Period(year: 2026, trimester: 120, name: "Semestre 1")
        #expect(book.subjects(in: s1).count == 2)
        #expect(book.periods.map(\.shortTitle) == ["S2 2026-27", "S1 2026-27"])
    }

    @Test func weightedAverageByHand() {
        let p = GradeBook.Period(year: 2026, trimester: 1, name: "Semestre 1")
        let book = GradeBook(subjects: [
            .init(course: "a", average: 12, coef: 3, trimester: 1, year: 2026),
            .init(course: "b", average: 16, coef: 1, trimester: 1, year: 2026),
            .init(course: "c", average: nil, coef: 5, trimester: 1, year: 2026),
            .init(course: "d", average: 20, coef: 0, trimester: 1, year: 2026),
            .init(course: "e", average: 20, coef: nil, trimester: 1, year: 2026),
            .init(course: "f", average: 0, coef: 2, trimester: 2, year: 2026),
        ])
        // (12 x 3 + 16 x 1) / 4 = 13
        #expect(book.weightedAverage(in: p) == 13)
        #expect(book.weightedAverage(in: .init(year: 2026, trimester: 9, name: "x")) == nil)
    }

    @Test func weightedAverageFromFixture() throws {
        let book = try GESGrades.gradeBook(from: jsonFixture("kordis-grades"))
        #expect(book.weightedAverage(in: .init(year: 2026, trimester: 120, name: "Semestre 1")) == 17.5)
        #expect(book.weightedAverage(in: .init(year: 2026, trimester: 121, name: "Semestre 2")) == 12)
    }

    @Test func maxCCCount() throws {
        let book = try GESGrades.gradeBook(from: jsonFixture("kordis-grades"))
        #expect(book.maxCCCount(in: .init(year: 2026, trimester: 121, name: "")) == 3)
        #expect(book.maxCCCount(in: .init(year: 2026, trimester: 120, name: "")) == 1)
        #expect(book.maxCCCount(in: .init(year: 1999, trimester: 1, name: "")) == 0)
    }

    @Test func mergingOtherWins() {
        let a = GradeBook(subjects: [
            .init(course: "x", grades: [1], trimester: 1, year: 2025), .init(course: "y", grades: [2], trimester: 1, year: 2025),
        ])
        let b = GradeBook(subjects: [
            .init(course: "y", grades: [9], trimester: 1, year: 2025), .init(course: "z", grades: [3], trimester: 1, year: 2026),
        ])
        let m = a.merging(b)
        #expect(m.subjects.map(\.course) == ["x", "y", "z"])
        #expect(m.subjects[1].grades == [9])
        #expect(m.periods.count == 2)
    }

    // MARK: Période courante

    private func course(_ id: String, _ start: Double, _ end: Double, period: Int?) -> Course {
        Course(id: id, title: id, start: Date(timeIntervalSince1970: start), end: Date(timeIntervalSince1970: end),
               room: nil, periodID: period)
    }

    private var twoYearBook: GradeBook {
        GradeBook(subjects: [
            .init(course: "a", trimester: 110, year: 2025, trimesterName: "Semestre 2"),
            .init(course: "b", trimester: 120, year: 2026, trimesterName: "Semestre 1"),
            .init(course: "c", trimester: 121, year: 2026, trimesterName: "Semestre 2"),
        ])
    }

    @Test func pickerUsesRunningCourse() {
        let courses = [course("passé", 0, 100, period: 110), course("en cours", 500, 700, period: 120),
                       course("futur", 900, 1000, period: 121)]
        let p = PeriodPicker.current(book: twoYearBook, courses: courses, now: Date(timeIntervalSince1970: 600))
        #expect(p?.id == "2026#120")
    }

    @Test func pickerFallsBackToNextThenLast() {
        let courses = [course("passé", 0, 100, period: 110), course("futur", 900, 1000, period: 120)]
        #expect(PeriodPicker.current(book: twoYearBook, courses: courses, now: Date(timeIntervalSince1970: 300))?.id == "2026#120")
        #expect(PeriodPicker.current(book: twoYearBook, courses: courses, now: Date(timeIntervalSince1970: 5000))?.id == "2026#120")
        let past = [course("passé", 0, 100, period: 110)]
        #expect(PeriodPicker.current(book: twoYearBook, courses: past, now: Date(timeIntervalSince1970: 5000))?.id == "2025#110")
    }

    @Test func pickerNoCourseGivesMostRecent() {
        #expect(PeriodPicker.current(book: twoYearBook, courses: [], now: Date())?.id == "2026#121")
        #expect(PeriodPicker.current(book: GradeBook(subjects: []), courses: [], now: Date()) == nil)
    }

    @Test func pickerUnknownPeriodIDFallsBack() {
        let courses = [course("inconnu", 500, 700, period: 999), course("sans", 500, 700, period: nil)]
        #expect(PeriodPicker.current(book: twoYearBook, courses: courses, now: Date(timeIntervalSince1970: 600))?.id == "2026#121")
    }

    @Test func diffCarriesPeriod() {
        let old = GradeBook(subjects: [.init(course: "A", grades: [10], trimester: 120, year: 2026, trimesterName: "Semestre 1")])
        let new = GradeBook(subjects: [.init(course: "A", grades: [10, 14], trimester: 120, year: 2026, trimesterName: "Semestre 1")])
        let d = GradeDiff.newGrades(old: old, new: new)
        #expect(d.count == 1 && d[0].label == "CC2" && d[0].period == GradeBook.Period(year: 2026, trimester: 120, name: "Semestre 1"))
    }

    @Test func diffTreatsSameCourseOtherYearAsNewSubject() {
        let old = GradeBook(subjects: [.init(course: "A", grades: [10], trimester: 120, year: 2025)])
        let new = GradeBook(subjects: [.init(course: "A", grades: [10], trimester: 120, year: 2026)])
        #expect(GradeDiff.newGrades(old: old, new: new).map(\.label) == ["CC1"])
    }

    // MARK: Agenda : périodes

    @Test func agendaFillsPeriodID() throws {
        let events = try GESAgenda.events(from: jsonFixture("kordis-agenda"))
        #expect(events[0].discipline?.trimesterID == 120 && events[0].discipline?.year == 2026)
        #expect(events[0].discipline?.trimester == "Semestre 1")
        let courses = GESAgenda.courses(from: events)
        #expect(courses.map(\.periodID) == [120, 120, nil])
    }

    @Test func courseDecodesWithoutPeriodID() throws {
        let c = try JSONDecoder().decode(Course.self, from: Data(#"{"id":"a","title":"t","start":0,"end":60}"#.utf8))
        #expect(c.periodID == nil)
        let withID = Course(id: "a", title: "t", start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 60),
                            room: nil, periodID: 120)
        #expect(try JSONDecoder().decode(Course.self, from: JSONEncoder().encode(withID)).periodID == 120)
    }

    // MARK: Différences

    private func subject(_ course: String, grades: [Double] = [], exam: Double? = nil, average: Double? = nil)
        -> GradeBook.Subject
    {
        GradeBook.Subject(course: course, grades: grades, exam: exam, average: average, trimester: 1)
    }

    @Test func diffFirstLoadIsEmpty() {
        let new = GradeBook(subjects: [subject("T1 - A", grades: [10], exam: 12)])
        #expect(GradeDiff.newGrades(old: nil, new: new).isEmpty)
    }

    @Test func diffDetectsNewCC() {
        let old = GradeBook(subjects: [subject("T1 - A", grades: [10])])
        let new = GradeBook(subjects: [subject("T1 - A", grades: [10, 14])])
        #expect(GradeDiff.newGrades(old: old, new: new) == [NewGrade(course: "T1 - A", label: "CC2", value: 14)])
    }

    @Test func diffDetectsExamAndAverage() {
        let old = GradeBook(subjects: [subject("T1 - A", grades: [10])])
        let new = GradeBook(subjects: [subject("T1 - A", grades: [10], exam: 13, average: 12)])
        #expect(GradeDiff.newGrades(old: old, new: new).map(\.label) == ["Examen", "Moyenne"])
    }

    @Test func diffNewSubjectHasAllGradesButNoAverage() {
        let old = GradeBook(subjects: [subject("T1 - A")])
        let new = GradeBook(subjects: [subject("T1 - A"), subject("T1 - B", grades: [8, 9], exam: 11, average: 10)])
        let diff = GradeDiff.newGrades(old: old, new: new)
        #expect(diff.map(\.label) == ["CC1", "CC2", "Examen"])
    }

    @Test func diffNothingChangedNoNotification() {
        let book = GradeBook(subjects: [subject("T1 - A", grades: [10], exam: 12, average: 11)])
        #expect(GradeDiff.newGrades(old: book, new: book).isEmpty)
        #expect(GradeDiff.notifications([]).isEmpty)
    }

    @Test func notificationFormat() {
        let n = GradeDiff.notifications([NewGrade(course: "T1 - Droit", label: "CC1", value: 12.5)])
        #expect(n == [PendingNotification(id: "grade-T1 - Droit-CC1-12.5", title: "Nouvelle note : Droit", body: "CC1 : 12.5/20")])
    }

    @Test func notificationsGroupedBeyondFour() {
        let grades = (1...3).map { NewGrade(course: "T1 - A", label: "CC\($0)", value: 10) }
            + [NewGrade(course: "T1 - B", label: "CC1", value: 11), NewGrade(course: "T1 - B", label: "Examen", value: 12)]
        let n = GradeDiff.notifications(grades)
        #expect(n.count == 1)
        #expect(n[0].title == "5 nouvelles notes")
        #expect(n[0].body == "A, B")
    }

    // MARK: Course

    @Test func courseDecodesOldArchiveWithoutNewKeys() throws {
        let old = #"{"id":"a","title":"t","start":0,"end":60,"room":null}"#
        let c = try JSONDecoder().decode(Course.self, from: Data(old.utf8))
        #expect(c.id == "a" && c.teacher == nil && c.modality == nil)
    }

    @Test func courseRoundTripsTeacherAndModality() throws {
        let c = Course(id: "a", title: "t", start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 60),
                       room: nil, teacher: "X", modality: "Distanciel")
        #expect(try JSONDecoder().decode(Course.self, from: JSONEncoder().encode(c)) == c)
    }
}

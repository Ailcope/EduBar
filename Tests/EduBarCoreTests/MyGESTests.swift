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

    @Test func gradesAreDecodedLeniently() throws {
        let book = try GESGrades.gradeBook(from: jsonFixture("kordis-grades"))
        #expect(book.subjects.count == 3)
        let a = book.subjects[0], b = book.subjects[1], c = book.subjects[2]
        #expect(a.grades.isEmpty && a.exam == nil && a.average == nil && a.ccAverage == nil)
        #expect(b.grades == [12.5, 14, 9.5])
        #expect(b.exam == 0)
        #expect(b.ccAverage == 12)
        #expect(c.grades == [15, 11.5, 8])
        #expect(c.exam == 13.5)
        #expect(c.average == nil)
        #expect(c.ccAverage == nil)
        #expect(c.coef == 2)
        #expect(c.trimester == 1)
    }

    @Test func gradesTeacherIsConcatenated() throws {
        let book = try GESGrades.gradeBook(from: jsonFixture("kordis-grades"))
        #expect(book.subjects[0].teacher == "M. Prénom NOM")
        #expect(book.subjects[1].teacher == nil)
        #expect(book.subjects[2].teacher == "Mme Prénom NOM")
    }

    @Test func gradesShortCourseAndBareArray() throws {
        let book = try GESGrades.gradeBook(from: Data(#"[{"course":"T2 - Droit","grades":[10]}]"#.utf8))
        #expect(book.subjects[0].shortCourse == "Droit")
        #expect(book.subjects[0].id == "T2 - Droit#")
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

import Foundation
import Testing
@testable import EduBarCore

@Suite struct MyGESCredentialsTests {
    let dir = FileManager.default.temporaryDirectory.appending(path: "edubar-creds-\(UUID().uuidString)")

    @Test func roundTrip() throws {
        let file = FeedFile(directory: dir, name: "myges-credentials")
        #expect(MyGESCredentialsFile.read(file) == nil)
        try MyGESCredentialsFile.write(MyGESCredentials(login: " jdupont ", password: " p@ss #wo rd "), to: file)
        let back = MyGESCredentialsFile.read(file)
        #expect(back == MyGESCredentials(login: "jdupont", password: " p@ss #wo rd "))
        let attrs = try FileManager.default.attributesOfItem(atPath: file.url.path)
        #expect((attrs[.posixPermissions] as? Int) == 0o600)
        MyGESCredentialsFile.remove(from: file)
        #expect(MyGESCredentialsFile.read(file) == nil)
        try? FileManager.default.removeItem(at: dir)
    }

    @Test func rejectsNewlines() {
        let file = FeedFile(directory: dir, name: "myges-credentials")
        #expect(throws: (any Error).self) { try MyGESCredentialsFile.write(MyGESCredentials(login: "a", password: "b\nc"), to: file) }
        #expect(throws: (any Error).self) { try MyGESCredentialsFile.write(MyGESCredentials(login: "", password: "b"), to: file) }
        try? FileManager.default.removeItem(at: dir)
    }

    @Test func malformedFileReadsAsNil() throws {
        let file = FeedFile(directory: dir, name: "x")
        try file.write("seulement-une-ligne")
        #expect(MyGESCredentialsFile.read(file) == nil)
        try? FileManager.default.removeItem(at: dir)
    }

    @Test func standardSitsNextToFeedURL() {
        #expect(MyGESCredentialsFile.standard.url.deletingLastPathComponent() == FeedFile.standard.url.deletingLastPathComponent())
        #expect(MyGESCredentialsFile.standard.url.lastPathComponent == "myges-credentials")
    }
}

@Suite struct KordisAPITests {
    var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris")!
        return c
    }

    @Test func urls() {
        #expect(KordisAPI.authorizeURL.absoluteString == "https://authentication.kordis.fr/oauth/authorize?response_type=token&client_id=skolae-app")
        let u = KordisAPI.agendaURL(from: Date(timeIntervalSince1970: 1_760_000_000.4), to: Date(timeIntervalSince1970: 1_760_600_000))
        #expect(u.absoluteString == "https://api.kordis.fr/me/agenda?start=1760000000400&end=1760600000000")
        #expect(KordisAPI.yearsURL.absoluteString == "https://api.kordis.fr/me/years")
        #expect(KordisAPI.gradesURL(year: 2025).absoluteString == "https://api.kordis.fr/me/2025/grades")
    }

    @Test func basic() {
        #expect(KordisAPI.basicAuthorization(MyGESCredentials(login: "ab", password: "cd")) == "Basic YWI6Y2Q=")
    }

    @Test func rangeStartsMondayMinusSevenDays() {
        // Jeudi 15/10/2026 : lundi 12/10, moins 7 jours = 05/10, plus 8 semaines = 30/11.
        let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 10))!
        let r = KordisAPI.agendaRange(now: now, calendar: cal)
        #expect(r.from == cal.date(from: DateComponents(year: 2026, month: 10, day: 5)))
        #expect(r.to == cal.date(from: DateComponents(year: 2026, month: 11, day: 30)))
    }

    @Test func rangeOnSundayUsesThatWeeksMonday() {
        let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 10))!
        #expect(KordisAPI.agendaRange(now: now, calendar: cal).from == cal.date(from: DateComponents(year: 2026, month: 10, day: 5)))
    }

    @Test func schoolYear() {
        #expect(KordisAPI.currentSchoolYear(now: cal.date(from: DateComponents(year: 2026, month: 10, day: 1))!, calendar: cal) == 2026)
        #expect(KordisAPI.currentSchoolYear(now: cal.date(from: DateComponents(year: 2026, month: 3, day: 1))!, calendar: cal) == 2025)
    }

    @Test func yearsTolerantDecoding() {
        #expect(KordisAPI.years(from: Data(#"{"result":[2024,2025]}"#.utf8)) == [2024, 2025])
        #expect(KordisAPI.years(from: Data(#"{"result":["2024"," 2025 "]}"#.utf8)) == [2024, 2025])
        #expect(KordisAPI.years(from: Data(#"{"result":[{"year":2025},{"id":"2026"},{"name":"2027"},{"x":1}]}"#.utf8)) == [2025, 2026, 2027])
        #expect(KordisAPI.years(from: Data(#"{"result":[]}"#.utf8)).isEmpty)
        #expect(KordisAPI.years(from: Data("nope".utf8)).isEmpty)
    }
}

import Foundation
import Testing
@testable import EduBarCore

@Suite struct UsageTests {
    private var paris: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris")!
        return c
    }

    private func date(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

    @Test func acceptsV4UUID() {
        #expect(Usage.isValidID("3f2b8c1e-9a4d-4e7b-8c3a-1d2e3f4a5b6c"))
        #expect(Usage.isValidID(UUID().uuidString.lowercased()))
    }

    @Test func rejectsInvalidUUID() {
        #expect(!Usage.isValidID(""))
        #expect(!Usage.isValidID("3F2B8C1E-9A4D-4E7B-8C3A-1D2E3F4A5B6C"))
        #expect(!Usage.isValidID("3f2b8c1e-9a4d-1e7b-8c3a-1d2e3f4a5b6c"))
        #expect(!Usage.isValidID("3f2b8c1e-9a4d-4e7b-cc3a-1d2e3f4a5b6c"))
        #expect(!Usage.isValidID("3f2b8c1e9a4d4e7b8c3a1d2e3f4a5b6c"))
        #expect(!Usage.isValidID("3f2b8c1e-9a4d-4e7b-8c3a-1d2e3f4a5b6g"))
    }

    @Test func dueWhenNeverSentOrOtherDay() {
        let now = date("2026-10-09T10:00:00Z")
        #expect(Usage.isDue(lastSentDay: nil, now: now, calendar: paris))
        #expect(Usage.isDue(lastSentDay: "2026-10-08", now: now, calendar: paris))
        #expect(!Usage.isDue(lastSentDay: "2026-10-09", now: now, calendar: paris))
    }

    @Test func dayIsLocalNotUTC() {
        // 22:30 UTC = 00:30 le lendemain à Paris (heure d'été).
        let now = date("2026-10-08T22:30:00Z")
        #expect(Usage.dayKey(now, calendar: paris) == "2026-10-09")
        #expect(!Usage.isDue(lastSentDay: "2026-10-09", now: now, calendar: paris))
    }

    @Test func registerRequestShape() {
        let r = Usage.registerRequest()
        #expect(r.url?.absoluteString == "https://edu.mathys.cc/v1/installation")
        #expect(r.httpMethod == "POST")
        #expect(r.httpBody == nil)
        #expect(r.timeoutInterval == 15)
    }

    @Test func signalRequestShape() throws {
        let id = "3f2b8c1e-9a4d-4e7b-8c3a-1d2e3f4a5b6c"
        let r = Usage.signalRequest(id: id, version: "0.7.0")
        #expect(r.url?.absoluteString == "https://edu.mathys.cc/v1/signal")
        #expect(r.httpMethod == "POST")
        #expect(r.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try JSONSerialization.jsonObject(with: #require(r.httpBody)) as? [String: String]
        #expect(body == ["id": id, "version": "0.7.0"])
    }

    @Test func parsesRegistration() {
        let id = "3f2b8c1e-9a4d-4e7b-8c3a-1d2e3f4a5b6c"
        #expect(Usage.parseRegistration(status: 201, body: Data(#"{"id":"\#(id)"}"#.utf8)) == id)
        #expect(Usage.parseRegistration(status: 200, body: Data(#"{"id":"\#(id)"}"#.utf8)) == nil)
        #expect(Usage.parseRegistration(status: 201, body: Data(#"{"id":"nope"}"#.utf8)) == nil)
        #expect(Usage.parseRegistration(status: 201, body: Data("x".utf8)) == nil)
    }

    @Test func interpretsStatuses() {
        #expect(Usage.outcome(status: 204) == .sent)
        #expect(Usage.outcome(status: 404) == .unknownID)
        #expect(Usage.outcome(status: 400) == .retryLater)
        #expect(Usage.outcome(status: 429) == .retryLater)
        #expect(Usage.outcome(status: 500) == .retryLater)
        #expect(Usage.outcome(status: 0) == .retryLater)
    }
}

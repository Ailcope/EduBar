import Foundation
import Testing
@testable import EduBarCore

struct FeedURLTests {
    @Test func webcalBecomesHTTPS() {
        #expect(FeedURL.normalize("webcal://api.example.fr/ical?sc=a&st=b")?.absoluteString
            == "https://api.example.fr/ical?sc=a&st=b")
        #expect(FeedURL.normalize("WEBCAL://api.example.fr/ical")?.absoluteString == "https://api.example.fr/ical")
    }

    @Test func keepsHTTPSAndTrims() {
        #expect(FeedURL.normalize("  https://h.example/x \n")?.absoluteString == "https://h.example/x")
    }

    @Test func rejectsOtherInput() {
        #expect(FeedURL.normalize("http://h.example/x") == nil)
        #expect(FeedURL.normalize("ftp://h.example/x") == nil)
        #expect(FeedURL.normalize("pas une url") == nil)
        #expect(FeedURL.normalize("https:///x") == nil)
        #expect(FeedURL.normalize("") == nil)
    }

    @Test func redactsQuery() {
        #expect(FeedURL.redacted(URL(string: "https://h.example/p?sc=secret")!) == "https://h.example/p?…")
        #expect(FeedURL.redacted(URL(string: "https://h.example/p")!) == "https://h.example/p")
    }
}

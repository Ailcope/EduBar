import Foundation
import Testing
@testable import EduBarCore

@Suite struct VersionTests {
    @Test func parsesTagsWithOrWithoutV() {
        #expect(Version("v1.2.3")?.parts == [1, 2, 3])
        #expect(Version("0.1")?.parts == [0, 1])
        #expect(Version(" 2.0.0 ")?.parts == [2, 0, 0])
    }

    @Test func rejectsGarbage() {
        #expect(Version("") == nil)
        #expect(Version("latest") == nil)
        #expect(Version("1.x") == nil)
        #expect(Version("__VERSION__") == nil)
    }

    @Test func comparesNumericallyNotLexically() {
        #expect(Version("0.10.0")! > Version("0.9.9")!)
        #expect(Version("1.0.0")! > Version("0.99")!)
        #expect(Version("0.1.1")! > Version("0.1.0")!)
    }

    @Test func missingPartsCountAsZero() {
        #expect(Version("1.0") == Version("1.0.0"))
        #expect(!(Version("1.0")! < Version("1.0.0")!))
    }
}

@Suite struct UpdateTests {
    let json = """
    {"tag_name":"v0.2.0","html_url":"https://github.com/Ailcope/EduBar/releases/tag/v0.2.0",
     "draft":false,"prerelease":false,
     "assets":[{"name":"EduBar-0.2.0.zip","browser_download_url":"https://x/EduBar-0.2.0.zip"},
               {"name":"EduBar-0.2.0.dmg","browser_download_url":"https://x/EduBar-0.2.0.dmg"}]}
    """

    @Test func decodesLatestRelease() throws {
        let r = try Update.decode(Data(json.utf8))
        #expect(r.version == Version("0.2.0"))
        #expect(r.page.absoluteString == "https://github.com/Ailcope/EduBar/releases/tag/v0.2.0")
        #expect(r.dmg?.absoluteString == "https://x/EduBar-0.2.0.dmg")
    }

    @Test func availableOnlyWhenNewer() throws {
        let r = try Update.decode(Data(json.utf8))
        #expect(Update.available(r, current: "0.1.0") == r)
        #expect(Update.available(r, current: "0.2.0") == nil)
        #expect(Update.available(r, current: "0.3.0") == nil)
    }

    @Test func unknownCurrentVersionNeverOffersUpdate() throws {
        let r = try Update.decode(Data(json.utf8))
        #expect(Update.available(r, current: nil) == nil)
        #expect(Update.available(r, current: "__VERSION__") == nil)
    }

    @Test func badPayloadThrows() {
        #expect(throws: (any Error).self) { try Update.decode(Data("{}".utf8)) }
        #expect(throws: (any Error).self) { try Update.decode(Data(#"{"tag_name":"nightly","html_url":"https://x"}"#.utf8)) }
    }
}

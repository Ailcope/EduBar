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

    @Test func decodesZipAndItsDigest() throws {
        let hex = String(repeating: "ab", count: 32)
        let data = Data("""
        {"tag_name":"v0.4.0","html_url":"https://x/tag",
         "assets":[{"name":"EduBar-0.4.0.zip","browser_download_url":"https://x/EduBar-0.4.0.zip","digest":"sha256:\(hex.uppercased())"}]}
        """.utf8)
        let r = try Update.decode(data)
        #expect(r.zip?.absoluteString == "https://x/EduBar-0.4.0.zip")
        #expect(r.zipSHA256 == hex)
        #expect(r.dmg == nil)
    }

    @Test func missingOrOddDigestGivesNoChecksum() throws {
        let r = try Update.decode(Data(json.utf8))
        #expect(r.zip?.absoluteString == "https://x/EduBar-0.2.0.zip")
        #expect(r.zipSHA256 == nil)
        #expect(Update.sha256Hex("md5:abcd") == nil)
        #expect(Update.sha256Hex("sha256:xyz") == nil)
    }

    @Test func hashesFiles() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "edubar-hash-\(UUID().uuidString)")
        try Data("abc".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(try Update.sha256(of: file) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test func readsBundleInfo() throws {
        let app = FileManager.default.temporaryDirectory.appending(path: "edubar-\(UUID().uuidString)/EduBar.app")
        let contents = app.appending(path: "Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }
        let plist: [String: Any] = ["CFBundleIdentifier": "dev.ailcope.edubar", "CFBundleShortVersionString": "0.4.0"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appending(path: "Info.plist"))
        let info = Update.bundleInfo(at: app)
        #expect(info?.id == "dev.ailcope.edubar")
        #expect(info?.version == Version("0.4.0"))
        #expect(Update.bundleInfo(at: app.deletingLastPathComponent()) == nil)
    }
}

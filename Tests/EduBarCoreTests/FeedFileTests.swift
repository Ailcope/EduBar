import Foundation
import Testing
@testable import EduBarCore

@Suite struct FeedFileTests {
    let dir = FileManager.default.temporaryDirectory.appending(path: "edubar-test-\(UUID().uuidString)")

    @Test func roundTripPrivateFile() throws {
        let file = FeedFile(directory: dir)
        #expect(file.read() == nil)
        try file.write("webcal://example.test/ical?sc=a&st=b")
        #expect(file.read() == "webcal://example.test/ical?sc=a&st=b")
        let attrs = try FileManager.default.attributesOfItem(atPath: file.url.path)
        #expect((attrs[.posixPermissions] as? Int) == 0o600)
        let dirAttrs = try FileManager.default.attributesOfItem(atPath: dir.path)
        #expect((dirAttrs[.posixPermissions] as? Int) == 0o700)
        try? FileManager.default.removeItem(at: dir)
    }

    @Test func overwriteAndRemove() throws {
        let file = FeedFile(directory: dir)
        try file.write("a")
        try file.write("  b\n")
        #expect(file.read() == "b")
        file.remove()
        #expect(file.read() == nil)
        try? FileManager.default.removeItem(at: dir)
    }

    @Test func blankFileReadsAsNil() throws {
        let file = FeedFile(directory: dir)
        try file.write(" \n")
        #expect(file.read() == nil)
        try? FileManager.default.removeItem(at: dir)
    }
}

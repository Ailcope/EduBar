import Foundation
import Testing
@testable import EduBarCore

@Suite struct SkipIdenticalWriteTests {
    let dir = FileManager.default.temporaryDirectory.appending(path: "edubar-skip-\(UUID().uuidString)")

    @Test func contenuIdentiqueNeReecritPasMaisRafraichitLaDate() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "a.json")
        try Data("abc".utf8).write(to: url)
        let old = Date(timeIntervalSinceNow: -3600)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: url.path)
        var writes = 0
        try SkipIdenticalWrite.perform(Data("abc".utf8), at: url) { writes += 1 }
        #expect(writes == 0)
        let mtime = try #require(try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        #expect(mtime.timeIntervalSinceNow > -60)
    }

    @Test func contenuDifferentOuAbsentEcrit() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "b.json")
        var writes = 0
        try SkipIdenticalWrite.perform(Data("x".utf8), at: url) { writes += 1 }
        #expect(writes == 1)
        try Data("x".utf8).write(to: url)
        try SkipIdenticalWrite.perform(Data("y".utf8), at: url) { writes += 1 }
        #expect(writes == 2)
    }
}

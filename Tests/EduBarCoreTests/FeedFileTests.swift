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

@Suite struct FeedFileAtomicTests {
    let dir = FileManager.default.temporaryDirectory.appending(path: "edubar-atomic-\(UUID().uuidString)")

    private func inode(_ url: URL) throws -> UInt64 {
        (try FileManager.default.attributesOfItem(atPath: url.path)[.systemFileNumber] as? UInt64) ?? 0
    }

    @Test func rewriteReplacesInodeKeepsPermissionsAndLeavesNoTemp() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = FeedFile(directory: dir, name: "myges-credentials")
        try file.writeExact("  secret  ")
        let first = try inode(file.url)
        try file.writeExact("  autre ")
        #expect(try inode(file.url) != first)
        #expect(try String(contentsOf: file.url, encoding: .utf8) == "  autre ")
        let attrs = try FileManager.default.attributesOfItem(atPath: file.url.path)
        #expect((attrs[.posixPermissions] as? Int) == 0o600)
        let dirAttrs = try FileManager.default.attributesOfItem(atPath: dir.path)
        #expect((dirAttrs[.posixPermissions] as? Int) == 0o700)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["myges-credentials"])
    }

    private func excluded(_ url: URL) throws -> Bool {
        try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup ?? false
    }

    @Test func sensitiveFilesAreExcludedFromBackupAfterEachWrite() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        for name in ["myges-credentials", "feed-url", "friend-url", "friend-url-2", "friend-url-3"] {
            let file = FeedFile(directory: dir, name: name)
            try file.write("a")
            #expect(try excluded(file.url), "\(name)")
            try file.write("b")
            #expect(try excluded(file.url), "\(name) après réécriture")
        }
    }

    /// Fichier écrit par une ancienne version (sans exclusion) : la lecture suffit à le protéger.
    @Test func readingAnOldSensitiveFileExcludesIt() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "edubar-old-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let creds = FeedFile(directory: dir, name: "myges-credentials")
        try Data("moi\nsecret".utf8).write(to: creds.url)
        #expect(try !excluded(creds.url))
        #expect(MyGESCredentialsFile.read(creds) == MyGESCredentials(login: "moi", password: "secret"))
        #expect(try excluded(creds.url))

        let feed = FeedFile(directory: dir, name: "feed-url")
        try Data("https://exemple.test/a.ics".utf8).write(to: feed.url)
        #expect(feed.read() == "https://exemple.test/a.ics")
        #expect(try excluded(feed.url))

        let grades = FeedFile(directory: dir, name: "grades.json")
        try Data("[]".utf8).write(to: grades.url)
        _ = grades.read()
        #expect(try !excluded(grades.url))
    }

    @Test func gradesAndHistoryStayInBackups() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        for name in ["grades.json", "history-calendar.json"] {
            let file = FeedFile(directory: dir, name: name)
            try file.writeExact("{}")
            #expect(try !excluded(file.url), "\(name)")
        }
    }

    @Test func failedWriteLeavesOriginalAndNoTemp() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = FeedFile(directory: dir)
        try file.write("avant")
        // Une cible qui est un dossier non vide fait échouer le rename : pas de fichier temporaire orphelin.
        let blocked = FeedFile(directory: dir, name: "bloque")
        try FileManager.default.createDirectory(at: blocked.url, withIntermediateDirectories: false)
        try Data("x".utf8).write(to: blocked.url.appending(path: "f"))
        #expect(throws: (any Error).self) { try blocked.writeExact("y") }
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        #expect(names == ["bloque", "feed-url"])
        #expect(file.read() == "avant")
    }
}

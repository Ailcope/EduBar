import EduBarCore
import Foundation
import Observation

/// Notes myGES : dernier relevé, cache disque privé (0600, comme l'URL du flux), diff entre deux chargements.
@MainActor @Observable
final class GradesStore {
    private(set) var book: GradeBook?
    private(set) var lastUpdated: Date?
    private(set) var lastError: String?
    private(set) var isLoading = false
    /// Notes apparues au dernier chargement.
    private(set) var newGrades: [NewGrade] = []

    private let file: FeedFile

    init(file: FeedFile = FeedFile(directory: FeedFile.standard.url.deletingLastPathComponent(), name: "grades.json")) {
        self.file = file
        if let raw = try? Data(contentsOf: file.url), let saved = try? JSONDecoder().decode(GradeBook.self, from: raw) {
            book = saved
            lastUpdated = (try? file.url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        }
    }

    /// Recharge les notes et renvoie les nouvelles (vide au tout premier chargement).
    @discardableResult
    func refresh(using fetch: () async throws -> GradeBook) async -> [NewGrade] {
        guard !isLoading else { return [] }
        isLoading = true
        defer { isLoading = false }
        do {
            let fresh = try await fetch()
            let added = GradeDiff.newGrades(old: book, new: fresh)
            book = fresh
            newGrades = added
            lastUpdated = Date()
            lastError = nil
            if let data = try? JSONEncoder().encode(fresh) { try? file.writeExact(String(decoding: data, as: UTF8.self)) }
            return added
        } catch {
            lastError = error.localizedDescription
            return []
        }
    }

    func clear() {
        book = nil
        lastUpdated = nil
        lastError = nil
        newGrades = []
        file.remove()
    }
}

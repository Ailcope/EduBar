import Foundation

/// Un cours du calendrier.
public struct Course: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    /// Salle, ou `nil` si le flux ne la donne pas.
    public let room: String?

    public init(id: String, title: String, start: Date, end: Date, room: String?) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.room = room
    }

    /// Titre sans le préfixe de période Edusign (« T1 - »).
    public var shortTitle: String {
        guard let range = title.range(of: #"^T\d+\s*-\s*"#, options: .regularExpression) else { return title }
        return String(title[range.upperBound...])
    }

    /// Titre court avec une majuscule (Edusign écrit tout en minuscules).
    public var displayTitle: String {
        let t = shortTitle
        return t.prefix(1).uppercased() + t.dropFirst()
    }

    /// Examen, partiel, DS, contrôle… d'après le titre.
    public var isExam: Bool {
        title.range(of: Self.examPattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static let examPattern =
        #"\b(examens?|exams?|partiels?|ds|contr[oô]les?|[ée]valuations?|soutenances?|qcm|rattrapages?|[ée]preuves?)\b"#
}

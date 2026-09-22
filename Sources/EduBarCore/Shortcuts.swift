import Foundation

/// Raccourcis (app Raccourcis de macOS) à lancer au début et à la fin de chaque suite de cours.
public struct ShortcutSettings: Codable, Equatable, Sendable {
    /// Nom du raccourci, vide : aucun.
    public var atStart: String
    public var atEnd: String

    public static let defaults = ShortcutSettings(atStart: "", atEnd: "")

    public init(atStart: String, atEnd: String) {
        self.atStart = atStart
        self.atEnd = atEnd
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        atStart = try c.decodeIfPresent(String.self, forKey: .atStart) ?? ""
        atEnd = try c.decodeIfPresent(String.self, forKey: .atEnd) ?? ""
    }

    public struct Run: Equatable, Sendable {
        /// Identique pour un même événement : sert à ne lancer qu'une fois.
        public let id: String
        public let name: String
    }

    /// Raccourcis à lancer maintenant : dans les deux minutes qui suivent l'événement.
    public func due(schedule: Schedule, at now: Date, calendar: Calendar) -> [Run] {
        var runs: [Run] = []
        for b in schedule.blocks(on: now, calendar: calendar) {
            for (name, at, tag) in [(atStart, b.start, "start"), (atEnd, b.end, "end")] {
                let name = name.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty, at <= now, now < at.addingTimeInterval(120) else { continue }
                runs.append(Run(id: "shortcut-\(tag)-\(Int(at.timeIntervalSince1970))", name: name))
            }
        }
        return runs
    }
}

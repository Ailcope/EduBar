import Foundation

/// Il faudra changer de salle après le cours en cours.
public struct RoomAlert: Equatable, Sendable {
    public let from: Course
    public let to: Course
    public let room: String

    public init(from: Course, to: Course, room: String) {
        self.from = from
        self.to = to
        self.room = room
    }
}

public enum RoomChange {
    /// Alerte si le cours actuel finit dans `lead` secondes ou moins et que le cours suivant du jour
    /// a lieu dans une autre salle (connue). Salle actuelle inconnue : on prévient quand même.
    public static func alert(for status: Status, at now: Date, lead: TimeInterval = 15 * 60) -> RoomAlert? {
        guard case let .inClass(current, next?, _, _) = status,
              current.end.timeIntervalSince(now) <= lead,
              let room = next.room, !normalized(room).isEmpty,
              normalized(room) != current.room.map(normalized)
        else { return nil }
        return RoomAlert(from: current, to: next, room: room)
    }

    static func normalized(_ room: String) -> String {
        room.trimmingCharacters(in: .whitespaces).lowercased()
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

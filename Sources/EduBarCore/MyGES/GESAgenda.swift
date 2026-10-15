import Foundation

public struct GESRoom: Decodable, Sendable, Equatable {
    public let name: String?
    public let campus: String?
    public let floor: String?

    public init(from decoder: any Decoder) throws {
        let c = try? decoder.container(keyedBy: AnyKey.self)
        name = c?.string("name")
        campus = c?.string("campus")
        floor = c?.string("floor")
    }
}

public struct GESDiscipline: Decodable, Sendable, Equatable {
    public let name: String?
    public let teacher: String?
    public let trimester: String?
    /// Identifiant numérique du semestre (`trimester_id`).
    public let trimesterID: Int?
    public let year: Int?

    public init(from decoder: any Decoder) throws {
        let c = try? decoder.container(keyedBy: AnyKey.self)
        name = c?.string("name")
        teacher = c?.string("teacher")
        trimester = c?.string("trimester")
        trimesterID = c?.number("trimester_id").map { Int($0) }
        year = c?.number("year").map { Int($0) }
    }
}

/// Un événement de l'agenda Kordis. Décodage tolérant : tout champ absent ou illisible vaut `nil`.
public struct GESEvent: Decodable, Sendable {
    public let reservationId: Int?
    public let name: String?
    public let type: String?
    public let modality: String?
    public let startDate: Date?
    public let endDate: Date?
    public let teacher: String?
    public let rooms: [GESRoom]
    public let discipline: GESDiscipline?

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        reservationId = c.number("reservation_id").map { Int($0) }
        name = c.string("name")
        type = c.string("type")
        modality = c.string("modality")
        startDate = c.number("start_date").map { Date(timeIntervalSince1970: $0 / 1000) }
        endDate = c.number("end_date").map { Date(timeIntervalSince1970: $0 / 1000) }
        teacher = c.string("teacher")
        rooms = AnyKey(stringValue: "rooms").flatMap { (try? c.decodeIfPresent([GESRoom].self, forKey: $0)) ?? nil } ?? []
        discipline = AnyKey(stringValue: "discipline").flatMap { (try? c.decodeIfPresent(GESDiscipline.self, forKey: $0)) ?? nil }
    }
}

public enum GESAgenda {
    private struct Envelope: Decodable { let result: [GESEvent]? }

    /// Accepte l'enveloppe `{"result": [...]}` ou un tableau nu.
    public static func events(from data: Data) throws -> [GESEvent] {
        let decoder = JSONDecoder()
        if let env = try? decoder.decode(Envelope.self, from: data), let list = env.result { return list }
        return try decoder.decode([GESEvent].self, from: data)
    }

    /// Cours exploitables, triés par (début, id). Les événements sans dates valides sont ignorés.
    public static func courses(from events: [GESEvent]) -> [Course] {
        func clean(_ s: String?) -> String? {
            let t = s?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (t?.isEmpty ?? true) ? nil : t
        }
        let courses: [Course] = events.compactMap { e in
            guard let start = e.startDate, let end = e.endDate, end > start else { return nil }
            let name = clean(e.name)
            let id = e.reservationId.map { "ges-\($0)" }
                ?? "\(Int(start.timeIntervalSince1970 * 1000))-\(name ?? "")"
            let rooms = e.rooms.compactMap { clean($0.name) }
            return Course(
                id: id, title: name ?? clean(e.discipline?.name) ?? "Cours", start: start, end: end,
                room: rooms.isEmpty ? nil : rooms.joined(separator: " · "),
                teacher: clean(e.teacher) ?? clean(e.discipline?.teacher), modality: clean(e.modality),
                periodID: e.discipline?.trimesterID
            )
        }
        return courses.sorted { ($0.start, $0.id) < ($1.start, $1.id) }
    }
}

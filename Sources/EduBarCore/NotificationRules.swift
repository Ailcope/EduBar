import Foundation

/// Une notification : activée ou non, combien de minutes avant l'événement, titre et texte.
/// Variables : `{cours}`, `{heure}`, `{temps}`, `{salle}`, `{pause}`. Un texte vide reprend le défaut.
public struct NotificationRule: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var minutes: Int
    public var title: String
    public var body: String

    public init(enabled: Bool, minutes: Int, title: String, body: String) {
        self.enabled = enabled
        self.minutes = minutes
        self.title = title
        self.body = body
    }
}

public enum NotificationKind: String, CaseIterable, Sendable {
    /// Fin d'une suite de cours (pause, déjeuner ou fin de journée ensuite).
    case classEnd
    /// Début d'un cours après une pause, ou du premier de la journée.
    case classStart
    /// Fin d'un cours quand le suivant a lieu dans une autre salle.
    case roomChange

    public var path: WritableKeyPath<NotificationRules, NotificationRule> {
        switch self {
        case .classEnd: \.classEnd
        case .classStart: \.classStart
        case .roomChange: \.roomChange
        }
    }
}

public struct PendingNotification: Equatable, Sendable {
    /// Identique pour un même événement : sert à ne notifier qu'une fois.
    public let id: String
    public let title: String
    public let body: String
}

public struct NotificationRules: Codable, Equatable, Sendable {
    public var classEnd: NotificationRule
    public var classStart: NotificationRule
    public var roomChange: NotificationRule

    public static let defaults = NotificationRules(
        classEnd: NotificationRule(
            enabled: true, minutes: 5,
            title: "Fin du cours dans {temps}",
            body: "{cours} se termine à {heure}. Ensuite : {pause}."
        ),
        classStart: NotificationRule(
            enabled: true, minutes: 5,
            title: "Cours dans {temps} · {salle}",
            body: "{cours} à {heure} · {salle}"
        ),
        roomChange: NotificationRule(
            enabled: true, minutes: 15,
            title: "⚠️ Changement de salle : {salle}",
            body: "Après ce cours, {cours} à {heure} en {salle}."
        )
    )

    public init(classEnd: NotificationRule, classStart: NotificationRule, roomChange: NotificationRule) {
        self.classEnd = classEnd
        self.classStart = classStart
        self.roomChange = roomChange
    }

    /// Les règles absentes (réglages d'une ancienne version) prennent la valeur par défaut.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self.defaults
        classEnd = try c.decodeIfPresent(NotificationRule.self, forKey: .classEnd) ?? d.classEnd
        classStart = try c.decodeIfPresent(NotificationRule.self, forKey: .classStart) ?? d.classStart
        roomChange = try c.decodeIfPresent(NotificationRule.self, forKey: .roomChange) ?? d.roomChange
    }

    /// Notifications à envoyer maintenant : entre `minutes` avant l'événement et une minute après.
    public func due(schedule: Schedule, at now: Date, calendar: Calendar) -> [PendingNotification] {
        let today = schedule.courses(on: now, calendar: calendar)

        // Suites de cours enchaînés sans pause.
        var blocks: [(first: Course, last: Course)] = []
        for c in today {
            if let b = blocks.last, c.start <= b.last.end {
                if c.end >= b.last.end { blocks[blocks.count - 1].last = c }
            } else {
                blocks.append((c, c))
            }
        }

        var events: [(kind: NotificationKind, course: Course, at: Date, values: KeyValuePairs<String, String?>)] = []
        for (i, b) in blocks.enumerated() {
            let next = i + 1 < blocks.count ? blocks[i + 1].first : nil
            let pause = next.map {
                Display.isLunch(from: b.last.end, to: $0.start, calendar: calendar)
                    ? "déjeuner" : "pause de " + Display.duration($0.start.timeIntervalSince(b.last.end))
            } ?? "fin de journée"
            events.append((.classEnd, b.last, b.last.end, [
                "cours": b.last.shortTitle, "heure": Display.time(b.last.end, calendar: calendar),
                "temps": Display.duration(b.last.end.timeIntervalSince(now)),
                "salle": b.last.room.map(Display.shortRoom), "pause": pause,
            ]))
            events.append((.classStart, b.first, b.first.start, [
                "cours": b.first.shortTitle, "heure": Display.time(b.first.start, calendar: calendar),
                "temps": Display.duration(b.first.start.timeIntervalSince(now)),
                "salle": b.first.room.map(Display.shortRoom), "pause": nil,
            ]))
        }
        for c in today {
            guard let n = today.first(where: { $0.start >= c.end }),
                  let room = n.room, !RoomChange.normalized(room).isEmpty,
                  RoomChange.normalized(room) != c.room.map(RoomChange.normalized)
            else { continue }
            events.append((.roomChange, c, c.end, [
                "cours": n.shortTitle, "heure": Display.time(n.start, calendar: calendar),
                "temps": Display.duration(c.end.timeIntervalSince(now)),
                "salle": Display.shortRoom(room), "pause": nil,
            ]))
        }

        return events.compactMap { e in
            let rule = self[keyPath: e.kind.path]
            let lead = TimeInterval(max(0, rule.minutes) * 60)
            guard rule.enabled, e.at.addingTimeInterval(-lead) <= now, now < e.at.addingTimeInterval(60)
            else { return nil }
            return render(e.kind, e.values, id: "\(e.kind.rawValue)-\(e.course.id)-\(Int(e.at.timeIntervalSince1970))")
        }
    }

    /// Exemple rempli avec des valeurs fictives (bouton « Tester »).
    public func sample(_ kind: NotificationKind) -> PendingNotification {
        let rule = self[keyPath: kind.path]
        return render(kind, [
            "cours": "Langage C avancé", "heure": "14h", "temps": Display.duration(Double(rule.minutes) * 60),
            "salle": "501", "pause": kind == .classEnd ? "déjeuner" : nil,
        ], id: "test-\(kind.rawValue)-\(Date().timeIntervalSince1970)")
    }

    private func render(_ kind: NotificationKind, _ values: KeyValuePairs<String, String?>, id: String) -> PendingNotification {
        let rule = self[keyPath: kind.path], d = Self.defaults[keyPath: kind.path]
        return PendingNotification(
            id: id,
            title: Template.render(Template.pick(rule.title, or: d.title), values),
            body: Template.render(Template.pick(rule.body, or: d.body), values)
        )
    }
}

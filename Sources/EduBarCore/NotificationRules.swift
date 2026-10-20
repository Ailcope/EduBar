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
    /// Page ouverte quand on clique sur la notification.
    public let url: URL?

    public init(id: String, title: String, body: String, url: URL? = nil) {
        self.id = id
        self.title = title
        self.body = body
        self.url = url
    }
}

public struct NotificationRules: Codable, Equatable, Sendable {
    public var classEnd: NotificationRule
    public var classStart: NotificationRule
    public var roomChange: NotificationRule

    /// Règles par défaut, dans la langue courante.
    public static var defaults: NotificationRules { defaults(for: L10n.current) }

    public static func defaults(for lang: Lang) -> NotificationRules {
        switch lang {
        case .fr:
            NotificationRules(
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
        case .en:
            NotificationRules(
                classEnd: NotificationRule(
                    enabled: true, minutes: 5,
                    title: "Class ends in {temps}",
                    body: "{cours} ends at {heure}. Next: {pause}."
                ),
                classStart: NotificationRule(
                    enabled: true, minutes: 5,
                    title: "Class in {temps} · {salle}",
                    body: "{cours} at {heure} · {salle}"
                ),
                roomChange: NotificationRule(
                    enabled: true, minutes: 15,
                    title: "⚠️ Room change: {salle}",
                    body: "After this class, {cours} at {heure} in {salle}."
                )
            )
        }
    }

    /// Les textes encore au défaut de l'autre langue passent à celui de `lang`
    /// (un texte personnalisé, l'activation et les minutes ne sont jamais touchés).
    public func localized(to lang: Lang) -> NotificationRules {
        let other = Self.defaults(for: lang == .fr ? .en : .fr), target = Self.defaults(for: lang)
        var copy = self
        for kind in NotificationKind.allCases {
            let p = kind.path
            if copy[keyPath: p].title == other[keyPath: p].title { copy[keyPath: p].title = target[keyPath: p].title }
            if copy[keyPath: p].body == other[keyPath: p].body { copy[keyPath: p].body = target[keyPath: p].body }
        }
        return copy
    }

    /// Réglages d'origine (au texte près, dans l'une ou l'autre langue).
    public var isDefault: Bool { localized(to: L10n.current) == Self.defaults }

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
        let blocks = schedule.blocks(on: now, calendar: calendar)

        var events: [(kind: NotificationKind, course: Course, at: Date, values: KeyValuePairs<String, String?>)] = []
        for (i, b) in blocks.enumerated() {
            let next = i + 1 < blocks.count ? blocks[i + 1].first : nil
            let pause = next.map {
                Display.isLunch(from: b.last.end, to: $0.start, calendar: calendar)
                    ? L10n.tr("déjeuner", "lunch")
                    : L10n.tr("pause de ", "a break of ") + Display.duration($0.start.timeIntervalSince(b.last.end))
            } ?? L10n.tr("fin de journée", "end of day")
            events.append((.classEnd, b.last, b.last.end, [
                "cours": b.last.displayTitle, "heure": Display.time(b.last.end, calendar: calendar),
                "temps": Display.duration(b.last.end.timeIntervalSince(now)),
                "salle": b.last.room.map(Display.shortRoom), "pause": pause,
            ]))
            events.append((.classStart, b.first, b.first.start, [
                "cours": b.first.displayTitle, "heure": Display.time(b.first.start, calendar: calendar),
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
                "cours": n.displayTitle, "heure": Display.time(n.start, calendar: calendar),
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

    /// Exemple rempli avec des valeurs fictives, l'événement tombant dans `minutes` (bouton « Tester »).
    public func sample(_ kind: NotificationKind, now: Date = Date(), calendar: Calendar = .current) -> PendingNotification {
        let rule = self[keyPath: kind.path]
        let lead = Double(max(0, rule.minutes)) * 60
        return render(kind, [
            "cours": L10n.tr("Langage C avancé", "Advanced C Programming"), "heure": Display.time(now.addingTimeInterval(lead), calendar: calendar),
            "temps": Display.duration(lead),
            "salle": "501", "pause": kind == .classEnd ? L10n.tr("déjeuner", "lunch") : nil,
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

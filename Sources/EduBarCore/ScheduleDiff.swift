import Foundation

/// Un changement entre deux versions du flux.
public enum ScheduleChange: Equatable, Sendable {
    case added(Course)
    case cancelled(Course)
    case moved(from: Course, to: Course)
    case roomChanged(from: Course, to: Course)
}

public enum ScheduleDiff {
    /// Changements touchant les cours à venir dans `horizon` (ancienne ou nouvelle date).
    /// Flux vide d'un côté : rien (premier chargement, ou flux en panne plutôt qu'année annulée).
    public static func changes(
        from old: [Course], to new: [Course], now: Date, horizon: TimeInterval = 14 * 86_400
    ) -> [ScheduleChange] {
        guard !old.isEmpty, !new.isEmpty else { return [] }
        let limit = now.addingTimeInterval(horizon)
        func relevant(_ c: Course) -> Bool { c.start > now && c.start <= limit }

        let newByID = Dictionary(new.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let oldIDs = Set(old.map(\.id))
        var removed = old.filter { newByID[$0.id] == nil }
        var added = new.filter { !oldIDs.contains($0.id) }
        var changes: [ScheduleChange] = []

        for o in old {
            guard let n = newByID[o.id], relevant(o) || relevant(n) else { continue }
            if o.start != n.start || o.end != n.end {
                changes.append(.moved(from: o, to: n))
            } else if RoomChange.normalized(o.room ?? "") != RoomChange.normalized(n.room ?? "") {
                changes.append(.roomChanged(from: o, to: n))
            }
        }
        // UID régénéré : un cours disparu et un cours apparu avec le même titre, c'est un déplacement.
        for o in removed {
            let key = o.shortTitle.lowercased()
            let candidates = added.enumerated().filter { $0.element.shortTitle.lowercased() == key }
            guard let best = candidates.min(by: {
                abs($0.element.start.timeIntervalSince(o.start)) < abs($1.element.start.timeIntervalSince(o.start))
            }) else { continue }
            added.remove(at: best.offset)
            removed.removeAll { $0.id == o.id }
            let n = best.element
            guard relevant(o) || relevant(n) else { continue }
            if o.start != n.start || o.end != n.end {
                changes.append(.moved(from: o, to: n))
            } else if RoomChange.normalized(o.room ?? "") != RoomChange.normalized(n.room ?? "") {
                changes.append(.roomChanged(from: o, to: n))
            }
        }
        changes += removed.filter(relevant).map(ScheduleChange.cancelled)
        changes += added.filter(relevant).map(ScheduleChange.added)
        return changes.sorted { date($0) < date($1) }
    }

    private static func date(_ c: ScheduleChange) -> Date {
        switch c {
        case let .added(x), let .cancelled(x): x.start
        case let .moved(_, x), let .roomChanged(_, x): x.start
        }
    }

    /// Une notification par changement ; au-delà de `limit`, une seule qui résume.
    public static func notifications(
        _ changes: [ScheduleChange], now: Date, calendar: Calendar, limit: Int = 4
    ) -> [PendingNotification] {
        guard !changes.isEmpty else { return [] }
        let stamp = Int(now.timeIntervalSince1970)
        guard changes.count <= limit else {
            return [PendingNotification(
                id: "changes-\(stamp)",
                title: "🗓️ Emploi du temps modifié",
                body: "\(changes.count) changements dans les deux prochaines semaines. Ouvre EduBar pour voir le planning."
            )]
        }
        func when(_ d: Date) -> String {
            calendar.isDate(d, inSameDayAs: now)
                ? "aujourd'hui \(Display.time(d, calendar: calendar))"
                : Display.dayLabel(d, now: now, calendar: calendar)
        }
        func span(_ c: Course) -> String {
            "\(Display.time(c.start, calendar: calendar))-\(Display.time(c.end, calendar: calendar))"
        }
        func room(_ c: Course) -> String { c.room.map(Display.shortRoom) ?? "salle non indiquée" }

        return changes.map { change in
            switch change {
            case let .cancelled(c):
                PendingNotification(
                    id: "cancelled-\(c.id)-\(Int(c.start.timeIntervalSince1970))",
                    title: "❌ Cours annulé · \(when(c.start))",
                    body: "\(c.displayTitle) (\(span(c))) n'est plus au planning."
                )
            case let .added(c):
                PendingNotification(
                    id: "added-\(c.id)-\(Int(c.start.timeIntervalSince1970))",
                    title: "🆕 Nouveau cours · \(when(c.start))",
                    body: "\(c.displayTitle) (\(span(c))) · \(room(c))"
                )
            case let .moved(o, n):
                PendingNotification(
                    id: "moved-\(n.id)-\(Int(n.start.timeIntervalSince1970))",
                    title: "🔁 Cours déplacé · \(when(n.start))",
                    body: "\(n.displayTitle) : \(when(o.start)) → \(when(n.start)) (\(span(n))) · \(room(n))"
                )
            case let .roomChanged(o, n):
                PendingNotification(
                    id: "room-\(n.id)-\(RoomChange.normalized(n.room ?? ""))",
                    title: "📍 Salle changée · \(room(n))",
                    body: "\(n.displayTitle), \(when(n.start)) : \(room(o)) → \(room(n))"
                )
            }
        }
    }
}

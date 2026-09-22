import Foundation

/// Lecteur iCalendar (RFC 5545) réduit à ce dont EduBar a besoin : les `VEVENT` horodatés.
public enum ICSParser {
    public static func parse(_ text: String) -> [Course] {
        var courses: [Course] = []
        var defaultZone = TimeZone.current
        var event: [String: Property]?

        for line in unfold(text) {
            guard let prop = Property(line: line) else { continue }
            switch (prop.name, prop.value) {
            case ("BEGIN", "VEVENT"):
                event = [:]
            case ("END", "VEVENT"):
                if let e = event, let c = course(from: e, defaultZone: defaultZone) { courses.append(c) }
                event = nil
            case ("X-WR-TIMEZONE", _) where event == nil:
                if let tz = TimeZone(identifier: prop.value) { defaultZone = tz }
            default:
                if event != nil, event?[prop.name] == nil { event?[prop.name] = prop }
            }
        }
        return courses.sorted { ($0.start, $0.id) < ($1.start, $1.id) }
    }

    // MARK: - Lignes

    /// Recolle les lignes pliées (continuation = ligne qui commence par un espace ou une tabulation).
    static func unfold(_ text: String) -> [String] {
        var lines: [String] = []
        for raw in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            if let first = raw.first, first == " " || first == "\t", !lines.isEmpty {
                lines[lines.count - 1] += raw.dropFirst()
            } else if !raw.isEmpty {
                lines.append(String(raw))
            }
        }
        return lines
    }

    struct Property {
        let name: String
        let params: [String: String]
        let value: String

        init?(line: String) {
            // Le premier « : » hors guillemets sépare nom+paramètres et valeur.
            var inQuotes = false
            var colon: String.Index?
            for i in line.indices {
                let ch = line[i]
                if ch == "\"" { inQuotes.toggle() } else if ch == ":" && !inQuotes { colon = i; break }
            }
            guard let colon else { return nil }
            let head = line[..<colon].split(separator: ";")
            guard let name = head.first else { return nil }
            var params: [String: String] = [:]
            for p in head.dropFirst() {
                let kv = p.split(separator: "=", maxSplits: 1)
                if kv.count == 2 { params[kv[0].uppercased()] = kv[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
            }
            self.name = name.uppercased()
            self.params = params
            self.value = String(line[line.index(after: colon)...])
        }
    }

    // MARK: - Événements

    static func course(from e: [String: Property], defaultZone: TimeZone) -> Course? {
        guard let s = e["DTSTART"], let start = date(s, defaultZone: defaultZone),
              let en = e["DTEND"], let end = date(en, defaultZone: defaultZone), end > start
        else { return nil }
        let title = e["SUMMARY"].map { unescape($0.value) } ?? ""
        let room = e["LOCATION"].map { unescape($0.value).trimmingCharacters(in: .whitespaces) }
        return Course(
            id: e["UID"]?.value ?? "\(start.timeIntervalSince1970)-\(title)",
            title: title,
            start: start,
            end: end,
            room: room?.isEmpty == false ? room : nil
        )
    }

    /// `20260922T074500Z` (UTC), `20260922T094500` + TZID ou fuseau par défaut. Les dates seules renvoient `nil`.
    static func date(_ p: Property, defaultZone: TimeZone) -> Date? {
        if p.params["VALUE"] == "DATE" { return nil }
        var v = p.value
        let utc = v.hasSuffix("Z")
        if utc { v.removeLast() }
        guard v.count == 15 else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd'T'HHmmss"
        f.timeZone = utc ? TimeZone(identifier: "UTC") : p.params["TZID"].flatMap(TimeZone.init(identifier:)) ?? defaultZone
        return f.date(from: v)
    }

    static func unescape(_ s: String) -> String {
        var out = ""
        var escaping = false
        for ch in s {
            if escaping {
                out.append(ch == "n" || ch == "N" ? "\n" : ch)
                escaping = false
            } else if ch == "\\" {
                escaping = true
            } else {
                out.append(ch)
            }
        }
        return out
    }
}

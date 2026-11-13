import Foundation

/// Lecteur iCalendar (RFC 5545) réduit à ce dont EduBar a besoin : les `VEVENT` horodatés.
public enum ICSParser {
    public static func parse(_ text: String) -> [Course] {
        var courses: [Course] = []
        var defaultZone = TimeZone.current
        var event: [String: Property]?
        var formatters = FormatterCache()

        for line in unfold(text) {
            guard let prop = Property(line: line) else { continue }
            switch (prop.name, prop.value) {
            case ("BEGIN", "VEVENT"):
                event = [:]
            case ("END", "VEVENT"):
                if let e = event, let c = course(from: e, defaultZone: defaultZone, formatters: &formatters) { courses.append(c) }
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

    static func course(from e: [String: Property], defaultZone: TimeZone, formatters: inout FormatterCache) -> Course? {
        guard let s = e["DTSTART"], let start = date(s, defaultZone: defaultZone, formatters: &formatters),
              let en = e["DTEND"], let end = date(en, defaultZone: defaultZone, formatters: &formatters), end > start
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
    static func date(_ p: Property, defaultZone: TimeZone, formatters: inout FormatterCache) -> Date? {
        if p.params["VALUE"] == "DATE" { return nil }
        var v = p.value
        let utc = v.hasSuffix("Z")
        if utc { v.removeLast() }
        guard v.count == 15 else { return nil }
        let zone = utc ? TimeZone(identifier: "UTC") : p.params["TZID"].flatMap(TimeZone.init(identifier:)) ?? defaultZone
        return formatters.formatter(for: zone).date(from: v)
    }

    /// Cache de `DateFormatter` par fuseau, local à un appel de `parse` (aucun état global partagé).
    /// Le format est unique (`yyyyMMdd'T'HHmmss`), la clé est donc le seul fuseau.
    struct FormatterCache {
        private var byZone: [TimeZone: DateFormatter] = [:]

        mutating func formatter(for zone: TimeZone?) -> DateFormatter {
            // `nil` (UTC introuvable) : comme avant, le formateur garde le fuseau courant du système.
            let key = zone ?? TimeZone.current
            if let f = byZone[key] { return f }
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyyMMdd'T'HHmmss"
            if let zone { f.timeZone = zone }
            byZone[key] = f
            return f
        }
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

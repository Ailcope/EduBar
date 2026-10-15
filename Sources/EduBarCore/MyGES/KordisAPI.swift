import Foundation

/// URLs et en-têtes de l'API Kordis (myGES). Pur : aucun réseau ici.
public enum KordisAPI {
    public static let authorizeURL = URL(string: "https://authentication.kordis.fr/oauth/authorize?response_type=token&client_id=skolae-app")!
    private static let base = "https://api.kordis.fr"

    /// Un pare-feu côté Kordis refuse les requêtes sans User-Agent de navigateur.
    public static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36"

    /// Bornes en millisecondes depuis l'époque, entières.
    public static func agendaURL(from: Date, to: Date) -> URL {
        let start = Int((from.timeIntervalSince1970 * 1000).rounded())
        let end = Int((to.timeIntervalSince1970 * 1000).rounded())
        return URL(string: "\(base)/me/agenda?start=\(start)&end=\(end)")!
    }

    public static var yearsURL: URL { URL(string: "\(base)/me/years")! }

    public static func gradesURL(year: Int) -> URL { URL(string: "\(base)/me/\(year)/grades")! }

    public static func basicAuthorization(_ creds: MyGESCredentials) -> String {
        "Basic " + Data("\(creds.login):\(creds.password)".utf8).base64EncodedString()
    }

    /// Lundi de la semaine courante moins 7 jours (00:00), jusqu'à 8 semaines plus tard.
    public static func agendaRange(now: Date, calendar: Calendar) -> (from: Date, to: Date) {
        var cal = calendar
        cal.firstWeekday = 2
        let monday = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? cal.startOfDay(for: now)
        let from = cal.date(byAdding: .day, value: -7, to: monday) ?? monday
        let to = cal.date(byAdding: .weekOfYear, value: 8, to: from) ?? from
        return (from, to)
    }

    /// Année scolaire courante : année civile à partir d'août, sinon la précédente.
    public static func currentSchoolYear(now: Date, calendar: Calendar) -> Int {
        let c = calendar.dateComponents([.year, .month], from: now)
        let year = c.year ?? 2000
        return (c.month ?? 1) >= 8 ? year : year - 1
    }

    /// Lit `result` de `/me/years` : entiers, chaînes numériques, ou objets avec `year`/`id`/`name`.
    public static func years(from data: Data) -> [Int] {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return [] }
        let list: [Any]
        if let dict = root as? [String: Any], let result = dict["result"] as? [Any] { list = result }
        else if let arr = root as? [Any] { list = arr }
        else { return [] }
        func number(_ v: Any?) -> Int? {
            if let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return n.intValue }
            if let s = v as? String { return Int(s.trimmingCharacters(in: .whitespaces)) }
            return nil
        }
        return list.compactMap { item -> Int? in
            if let n = number(item) { return n }
            guard let obj = item as? [String: Any] else { return nil }
            for key in ["year", "id", "name"] { if let n = number(obj[key]) { return n } }
            return nil
        }
    }
}

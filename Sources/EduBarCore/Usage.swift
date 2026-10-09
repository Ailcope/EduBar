import Foundation

/// Signal anonyme quotidien d'utilisation : un identifiant tiré au hasard par le serveur et la version.
/// Toute la logique est ici, sans réseau ni trousseau, pour être testée.
public enum Usage {
    public static let base = URL(string: "https://edu.mathys.cc")!

    /// UUID v4 en minuscules : 8-4-4-4-12 chiffres hexadécimaux, version 4, variante 8, 9, a ou b.
    public static func isValidID(_ s: String) -> Bool {
        let c = Array(s.utf8)
        guard c.count == 36 else { return false }
        for (i, o) in c.enumerated() {
            switch i {
            case 8, 13, 18, 23:
                guard o == UInt8(ascii: "-") else { return false }
            case 14:
                guard o == UInt8(ascii: "4") else { return false }
            case 19:
                guard [UInt8(ascii: "8"), UInt8(ascii: "9"), UInt8(ascii: "a"), UInt8(ascii: "b")].contains(o) else { return false }
            default:
                let digit = (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(o)
                let letter = (UInt8(ascii: "a")...UInt8(ascii: "f")).contains(o)
                guard digit || letter else { return false }
            }
        }
        return true
    }

    /// Jour calendaire local (`yyyy-MM-dd`), gardé pour savoir si le signal du jour est parti.
    public static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Un seul signal réussi par jour calendaire local.
    public static func isDue(lastSentDay: String?, now: Date, calendar: Calendar) -> Bool {
        lastSentDay != dayKey(now, calendar: calendar)
    }

    /// Demande d'un identifiant (corps vide).
    public static func registerRequest() -> URLRequest {
        var r = URLRequest(url: base.appendingPathComponent("v1/installation"), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        r.httpMethod = "POST"
        return r
    }

    public static func signalRequest(id: String, version: String) -> URLRequest {
        var r = URLRequest(url: base.appendingPathComponent("v1/signal"), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONEncoder().encode(SignalBody(id: id, version: version))
        return r
    }

    private struct SignalBody: Codable { let id: String; let version: String }

    /// Identifiant de la réponse 201 de `/v1/installation`, s'il est valide.
    public static func parseRegistration(status: Int, body: Data) -> String? {
        struct Body: Decodable { let id: String }
        guard status == 201, let b = try? JSONDecoder().decode(Body.self, from: body), isValidID(b.id) else { return nil }
        return b.id
    }

    public enum Outcome: Equatable, Sendable {
        /// 204 : noter le jour.
        case sent
        /// 404 : identifiant inconnu du serveur, à oublier.
        case unknownID
        /// Autre : réessayer plus tard.
        case retryLater
    }

    public static func outcome(status: Int) -> Outcome {
        switch status {
        case 204: .sent
        case 404: .unknownID
        default: .retryLater
        }
    }
}

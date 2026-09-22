import Foundation

/// Le calendrier affiché est-il encore celui d'Edusign ? Sans ça, un flux qui ne répond plus
/// laisse voir un vieux planning sans prévenir.
public enum Freshness {
    /// Au-delà, le calendrier est signalé comme figé (le flux est rechargé toutes les 15 min).
    public static let staleAfter: TimeInterval = 24 * 3600

    /// « 26 h », « 3 jours » depuis le dernier chargement réussi ; nil s'il est récent ou inconnu.
    public static func staleSince(_ lastUpdated: Date?, now: Date) -> String? {
        guard let lastUpdated else { return nil }
        let age = now.timeIntervalSince(lastUpdated)
        guard age > staleAfter else { return nil }
        let hours = Int(age / 3600)
        return hours < 48 ? "\(hours) h" : "\(hours / 24) jours"
    }

    /// Flux valide mais vide alors qu'on connaissait des cours à venir : panne côté Edusign plutôt
    /// qu'une fin d'année. On garde les anciens cours au lieu de tout effacer.
    public static func suspiciousEmpty(fresh: [Course], previous: [Course], now: Date) -> Bool {
        fresh.isEmpty && previous.contains { $0.end > now }
    }
}

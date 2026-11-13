import Foundation

/// Mémorise qu'un jeu d'identifiants a été refusé (401/403) pour ne plus retenter la connexion
/// automatique avec les mêmes à chaque rafraîchissement. Un autre jeu d'identifiants, `reset()`
/// (relance à la main) ou le délai `retryAfter` débloquent.
/// Les erreurs 429, 5xx et réseau ne passent pas par ici : elles sont temporaires.
public struct RefusalGate: Sendable {
    /// Un refus peut être passager (pare-feu, maintenance) : une nouvelle tentative après ce délai,
    /// soit 4 essais par jour au lieu d'un toutes les 15 minutes.
    public static let retryAfter: TimeInterval = 6 * 3600

    private var refused: MyGESCredentials?
    private var refusedAt: Date?

    public init() {}

    /// Faux tant que ces identifiants sont ceux qui viennent d'être refusés, pendant `retryAfter`.
    public func allows(_ creds: MyGESCredentials, now: Date = Date()) -> Bool {
        guard refused == creds, let refusedAt else { return true }
        let elapsed = now.timeIntervalSince(refusedAt)
        // Horloge reculée : on retente plutôt que de rester bloqué.
        return elapsed >= Self.retryAfter || elapsed < 0
    }

    public mutating func recordRefusal(of creds: MyGESCredentials, at now: Date = Date()) {
        refused = creds
        refusedAt = now
    }

    /// Relance à la main ou connexion réussie : on retente.
    public mutating func reset() {
        refused = nil
        refusedAt = nil
    }
}

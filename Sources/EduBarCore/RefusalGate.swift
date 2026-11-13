import Foundation

/// Mémorise qu'un jeu d'identifiants a été refusé (401/403) pour ne plus retenter la connexion
/// automatique avec les mêmes. Un autre jeu d'identifiants, ou `reset()` (relance à la main), débloque.
/// Les erreurs 429, 5xx et réseau ne passent pas par ici : elles sont temporaires.
public struct RefusalGate: Sendable {
    private var refused: MyGESCredentials?

    public init() {}

    /// Faux tant que ces identifiants sont ceux qui viennent d'être refusés.
    public func allows(_ creds: MyGESCredentials) -> Bool { refused != creds }

    public mutating func recordRefusal(of creds: MyGESCredentials) { refused = creds }

    /// Relance à la main ou connexion réussie : on retente.
    public mutating func reset() { refused = nil }
}

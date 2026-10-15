import Foundation

/// Jeton OAuth2 (flux implicite) renvoyé par Kordis dans le fragment de l'URL de redirection.
public struct KordisToken: Sendable, Equatable {
    public let accessToken: String
    public let tokenType: String
    public let expiresIn: TimeInterval?
    public let uid: String?

    public init(accessToken: String, tokenType: String, expiresIn: TimeInterval?, uid: String?) {
        self.accessToken = accessToken
        self.tokenType = tokenType
        self.expiresIn = expiresIn
        self.uid = uid
    }

    /// Lit le fragment (ce qui suit le premier `#`) d'une URL `Location`.
    /// Aucun décodage des pourcentages ni des `+` : le jeton est repris tel quel.
    public static func parse(location: String) -> KordisToken? {
        guard let hash = location.firstIndex(of: "#") else { return nil }
        var values: [String: String] = [:]
        for pair in location[location.index(after: hash)...].split(separator: "&") {
            guard let eq = pair.firstIndex(of: "=") else { continue }
            values[String(pair[..<eq])] = String(pair[pair.index(after: eq)...])
        }
        guard let token = values["access_token"], !token.isEmpty else { return nil }
        return KordisToken(
            accessToken: token,
            tokenType: values["token_type"] ?? "bearer",
            expiresIn: values["expires_in"].flatMap(TimeInterval.init),
            uid: values["uid"]
        )
    }
}

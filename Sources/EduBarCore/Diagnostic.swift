import Foundation

/// Texte à coller dans un message quand quelque chose ne marche pas.
/// Jamais d'URL : celle du flux contient les jetons d'accès au calendrier.
public enum Diagnostic {
    public static func render(_ lines: [(String, String)]) -> String {
        (["EduBar · diagnostic"] + lines.map { "\($0.0) : \(redact($0.1))" }).joined(separator: "\n")
    }

    /// Masque toute URL et tout paramètre qui ressemble à un jeton.
    public static func redact(_ s: String) -> String {
        var out = s.replacingOccurrences(
            of: #"(?i)\b(webcal|https?)://\S+"#, with: "[URL masquée]", options: .regularExpression
        )
        out = out.replacingOccurrences(
            of: #"(?i)\b(sc|st|token|key)=[^&\s]+"#, with: "$1=[masqué]", options: .regularExpression
        )
        return out
    }
}

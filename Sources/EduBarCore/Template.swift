import Foundation

/// Modèles de texte à variables `{nom}`.
public enum Template {
    /// Remplit les variables. Valeur `nil` : la variable disparaît avec le séparateur qui l'entoure
    /// (`Cours dans 8 min · {salle}` devient `Cours dans 8 min`).
    public static func render(_ template: String, _ values: KeyValuePairs<String, String?>) -> String {
        var s = template
        for (name, value) in values {
            if let value {
                s = s.replacingOccurrences(of: "{\(name)}", with: value)
            } else {
                s = s.replacingOccurrences(of: #"\s*[·\-–|,:]\s*\{"# + name + #"\}"#, with: "", options: .regularExpression)
                s = s.replacingOccurrences(of: #"\{"# + name + #"\}\s*[·\-–|,:]?\s*"#, with: "", options: .regularExpression)
            }
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// Le modèle, ou `fallback` s'il est vide.
    static func pick(_ template: String, or fallback: String) -> String {
        template.trimmingCharacters(in: .whitespaces).isEmpty ? fallback : template
    }
}

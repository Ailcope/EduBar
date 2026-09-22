import Foundation

/// Textes de la barre des menus, personnalisables. Variables : `{temps}`, `{salle}`, `{jour}`.
/// Un modèle vide reprend le texte par défaut.
public struct BarTemplates: Codable, Equatable, Sendable {
    /// 15 min avant la fin d'un cours, quand le suivant change de salle.
    public var roomChange: String
    /// En cours, une pause courte suit.
    public var beforeBreak: String
    /// En cours, la pause déjeuner suit.
    public var beforeLunch: String
    /// En cours, plus rien après aujourd'hui.
    public var lastClass: String
    /// En pause courte.
    public var onBreak: String
    /// Pendant la pause déjeuner.
    public var onLunch: String
    /// Avant le premier cours de la journée.
    public var beforeFirst: String
    /// Journée finie ou sans cours (`{jour}` : « Demain 9h45 »).
    public var dayOver: String

    public static let defaults = BarTemplates(
        roomChange: "⚠️ Salle {salle} · fin dans {temps}",
        beforeBreak: "📚 Pause dans {temps}",
        beforeLunch: "🍽️ Déjeuner dans {temps}",
        lastClass: "📚 Fin dans {temps}",
        onBreak: "☕ Cours dans {temps} · {salle}",
        onLunch: "📚 Cours dans {temps} · {salle}",
        beforeFirst: "Cours dans {temps} · {salle}",
        dayOver: "{jour}"
    )

    public init(
        roomChange: String, beforeBreak: String, beforeLunch: String, lastClass: String,
        onBreak: String, onLunch: String, beforeFirst: String, dayOver: String
    ) {
        self.roomChange = roomChange
        self.beforeBreak = beforeBreak
        self.beforeLunch = beforeLunch
        self.lastClass = lastClass
        self.onBreak = onBreak
        self.onLunch = onLunch
        self.beforeFirst = beforeFirst
        self.dayOver = dayOver
    }

    /// Les clés absentes (réglages d'une ancienne version) prennent la valeur par défaut.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self.defaults
        roomChange = try c.decodeIfPresent(String.self, forKey: .roomChange) ?? d.roomChange
        beforeBreak = try c.decodeIfPresent(String.self, forKey: .beforeBreak) ?? d.beforeBreak
        beforeLunch = try c.decodeIfPresent(String.self, forKey: .beforeLunch) ?? d.beforeLunch
        lastClass = try c.decodeIfPresent(String.self, forKey: .lastClass) ?? d.lastClass
        onBreak = try c.decodeIfPresent(String.self, forKey: .onBreak) ?? d.onBreak
        onLunch = try c.decodeIfPresent(String.self, forKey: .onLunch) ?? d.onLunch
        beforeFirst = try c.decodeIfPresent(String.self, forKey: .beforeFirst) ?? d.beforeFirst
        dayOver = try c.decodeIfPresent(String.self, forKey: .dayOver) ?? d.dayOver
    }

    /// Le modèle, ou celui par défaut s'il est vide.
    func pick(_ path: KeyPath<BarTemplates, String>) -> String {
        Template.pick(self[keyPath: path], or: Self.defaults[keyPath: path])
    }

    /// Remplit les variables. Salle inconnue : `{salle}` disparaît avec le séparateur qui l'entoure.
    public static func render(_ template: String, temps: String = "", salle: String?, jour: String = "") -> String {
        Template.render(template, ["temps": temps, "jour": jour, "salle": salle])
    }
}

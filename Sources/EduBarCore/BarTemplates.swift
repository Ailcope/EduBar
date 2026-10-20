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
    /// Veille ou jour d'un examen (`{jour}` : « demain 9h » ou « dans 25 min »).
    public var examSoon: String
    /// Jour en entreprise (alternance ; `{jour}` : retour à l'école, « Lun. 9h »).
    public var company: String
    /// Journée finie ou sans cours (`{jour}` : « Demain 9h45 »).
    public var dayOver: String
    /// Météo quand le prochain cours est loin (`{meteo}`, `{temp}`, `{ville}`, `{jour}`).
    public var weather: String
    /// En cours, plus rien après cette semaine : le week-end commence dans `{temps}`.
    public var lastOfWeek: String

    /// Modèles par défaut, dans la langue courante.
    public static var defaults: BarTemplates { defaults(for: L10n.current) }

    public static func defaults(for lang: Lang) -> BarTemplates {
        switch lang {
        case .fr:
            BarTemplates(
                roomChange: "⚠️ Salle {salle} · fin dans {temps}",
                beforeBreak: "📚 Pause dans {temps}",
                beforeLunch: "🍽️ Déjeuner dans {temps}",
                lastClass: "📚 Fin dans {temps}",
                onBreak: "☕ Cours dans {temps} · {salle}",
                onLunch: "📚 Cours dans {temps} · {salle}",
                beforeFirst: "Cours dans {temps} · {salle}",
                dayOver: "{jour}",
                examSoon: "📝 Examen {jour} · {salle}",
                company: "🏢 Entreprise · école {jour}",
                weather: "{meteo} {temp}",
                lastOfWeek: "🎉 Week-end dans {temps}"
            )
        case .en:
            BarTemplates(
                roomChange: "⚠️ Room {salle} · ends in {temps}",
                beforeBreak: "📚 Break in {temps}",
                beforeLunch: "🍽️ Lunch in {temps}",
                lastClass: "📚 Ends in {temps}",
                onBreak: "☕ Class in {temps} · {salle}",
                onLunch: "📚 Class in {temps} · {salle}",
                beforeFirst: "Class in {temps} · {salle}",
                dayOver: "{jour}",
                examSoon: "📝 Exam {jour} · {salle}",
                company: "🏢 Work · school {jour}",
                weather: "{meteo} {temp}",
                lastOfWeek: "🎉 Weekend in {temps}"
            )
        }
    }

    private static var fields: [WritableKeyPath<BarTemplates, String>] {
        [
            \.roomChange, \.beforeBreak, \.beforeLunch, \.lastClass, \.onBreak, \.onLunch,
            \.beforeFirst, \.dayOver, \.examSoon, \.company, \.weather, \.lastOfWeek,
        ]
    }

    /// Les champs encore au texte par défaut de l'autre langue passent à celui de `lang`
    /// (un texte personnalisé n'est jamais touché).
    public func localized(to lang: Lang) -> BarTemplates {
        let other = Self.defaults(for: lang == .fr ? .en : .fr), target = Self.defaults(for: lang)
        var copy = self
        for f in Self.fields where copy[keyPath: f] == other[keyPath: f] { copy[keyPath: f] = target[keyPath: f] }
        return copy
    }

    /// Aucun champ personnalisé (chaque champ est vide ou au texte par défaut, dans une langue ou l'autre).
    public var isDefault: Bool {
        let fr = Self.defaults(for: .fr), en = Self.defaults(for: .en)
        return Self.fields.allSatisfy {
            let t = self[keyPath: $0]
            return t.trimmingCharacters(in: .whitespaces).isEmpty || t == fr[keyPath: $0] || t == en[keyPath: $0]
        }
    }

    public init(
        roomChange: String, beforeBreak: String, beforeLunch: String, lastClass: String,
        onBreak: String, onLunch: String, beforeFirst: String, dayOver: String,
        examSoon: String, company: String, weather: String, lastOfWeek: String
    ) {
        self.roomChange = roomChange
        self.beforeBreak = beforeBreak
        self.beforeLunch = beforeLunch
        self.lastClass = lastClass
        self.onBreak = onBreak
        self.onLunch = onLunch
        self.beforeFirst = beforeFirst
        self.dayOver = dayOver
        self.examSoon = examSoon
        self.company = company
        self.weather = weather
        self.lastOfWeek = lastOfWeek
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
        examSoon = try c.decodeIfPresent(String.self, forKey: .examSoon) ?? d.examSoon
        company = try c.decodeIfPresent(String.self, forKey: .company) ?? d.company
        weather = try c.decodeIfPresent(String.self, forKey: .weather) ?? d.weather
        lastOfWeek = try c.decodeIfPresent(String.self, forKey: .lastOfWeek) ?? d.lastOfWeek
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

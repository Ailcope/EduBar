import Foundation

/// Choix de langue de l'utilisateur (Réglages > Application).
public enum AppLanguage: String, CaseIterable, Sendable {
    /// Langue du système : français si le français figure parmi les langues préférées (beaucoup
    /// d'étudiants ont un macOS en anglais), sinon anglais.
    case system
    case fr
    case en

    /// La langue réellement utilisée.
    public func resolved(preferred: [String] = Locale.preferredLanguages) -> Lang {
        switch self {
        case .fr: .fr
        case .en: .en
        case .system: preferred.contains { $0.lowercased().hasPrefix("fr") } ? .fr : .en
        }
    }
}

/// Langue d'affichage : les deux seules disponibles.
public enum Lang: String, Sendable {
    case fr, en

    /// Locale des dates, mois et nombres affichés.
    public var locale: Locale { Locale(identifier: self == .fr ? "fr_FR" : "en_US") }
}

/// Traduction maison : le français et l'anglais sont écrits côte à côte dans le code.
public enum L10n {
    private final class Box: @unchecked Sendable {
        let lock = NSLock()
        var value: Lang = .fr
    }
    private static let box = Box()

    /// Surcharge locale à une tâche (tests, rendu d'une capture) : n'affecte pas le reste du process.
    @TaskLocal private static var override: Lang?

    /// Langue courante. Le français tant que l'app n'a rien réglé.
    public static var current: Lang {
        if let o = override { return o }
        box.lock.lock()
        defer { box.lock.unlock() }
        return box.value
    }

    public static func set(_ lang: Lang) {
        box.lock.lock()
        box.value = lang
        box.lock.unlock()
    }

    /// Exécute `body` dans une langue donnée (sans toucher à la langue de l'app).
    public static func with<T>(_ lang: Lang, _ body: () throws -> T) rethrows -> T {
        try $override.withValue(lang, operation: body)
    }

    public static var locale: Locale { current.locale }

    /// Le texte dans la langue courante.
    public static func tr(_ fr: String, _ en: String) -> String {
        current == .fr ? fr : en
    }

    /// Texte à variables : `L10n.tr("\(n) cours", "\(n) classes")` suffit presque toujours ;
    /// ceci choisit entre singulier et pluriel pour les deux langues.
    public static func plural(_ n: Int, fr: (one: String, other: String), en: (one: String, other: String)) -> String {
        let pair = current == .fr ? fr : en
        let isOne = current == .fr ? (n == 0 || n == 1) : n == 1
        return isOne ? pair.one : pair.other
    }
}

import Foundation

/// Edusign retire les jours passés de son flux : on garde nous-mêmes les cours finis
/// (journées précédentes, heures faites des statistiques).
public enum History {
    /// Au-delà, les cours archivés sont oubliés (une année scolaire et de la marge).
    public static let retention: TimeInterval = 400 * 24 * 3600

    /// Le flux fait foi à partir d'aujourd'hui (annulations comprises) ; avant, un cours archivé
    /// absent du flux est gardé. Trié par début.
    public static func merge(archived: [Course], fresh: [Course], now: Date, calendar: Calendar) -> [Course] {
        let today = calendar.startOfDay(for: now)
        let known = Set(fresh.map(\.id))
        let kept = archived.filter {
            $0.start < today && !known.contains($0.id) && $0.start > now.addingTimeInterval(-retention)
        }
        return (kept + fresh).sorted { ($0.start, $0.id) < ($1.start, $1.id) }
    }

    /// Ce qui est archivé : tout jusqu'à ce soir. Aujourd'hui compris, car le flux peut perdre la
    /// journée dès minuit ; chaque rafraîchissement la réécrit d'après le flux (annulations comprises).
    public static func archivable(_ courses: [Course], now: Date, calendar: Calendar) -> [Course] {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        return courses.filter { $0.start < tomorrow }
    }
}

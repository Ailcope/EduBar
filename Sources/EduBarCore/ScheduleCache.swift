import Foundation

/// Mémorise un `Schedule` tant que la liste de cours source ne change pas. La clé est la liste
/// elle-même (comparée par valeur) : tout changement de cours, de filtre, d'amis ou de mode démo
/// la modifie, donc invalide.
public final class ScheduleCache {
    private var source: [Course]?
    private var schedule = Schedule(courses: [])

    public init() {}

    public func schedule(for courses: [Course]) -> Schedule {
        // `==` sur deux tableaux de même tampon est immédiat.
        if let source, source == courses {
            // Contenu égal mais nouveau tampon (après un rafraîchissement) : on garde le nouveau,
            // sinon chaque lecture suivante recomparerait tous les cours.
            self.source = courses
            return schedule
        }
        schedule = Schedule(courses: courses)
        source = courses
        return schedule
    }
}

import Foundation

/// Rythme d'alternance : quels jours de semaine se passent en entreprise.
/// Un jour avec des cours dans le flux est toujours un jour d'école.
public struct Alternance: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, CaseIterable, Sendable {
        /// Pas d'alternance.
        case off
        /// Un jour de semaine sans cours est un jour en entreprise.
        case auto
        /// Mêmes jours chaque semaine.
        case weekdays
        /// N semaines d'école puis M semaines en entreprise.
        case weeks
    }

    public var mode: Mode
    /// Jours en entreprise, numérotés comme `Calendar` (2 = lundi … 6 = vendredi).
    public var companyWeekdays: Set<Int>
    public var schoolWeeks: Int
    public var companyWeeks: Int
    /// Un jour de la première semaine d'une période d'école (mode `weeks`).
    public var schoolAnchor: Date?

    public static let defaults = Alternance(
        mode: .off, companyWeekdays: [4, 5, 6], schoolWeeks: 2, companyWeeks: 2, schoolAnchor: nil
    )

    public init(mode: Mode, companyWeekdays: Set<Int>, schoolWeeks: Int, companyWeeks: Int, schoolAnchor: Date?) {
        self.mode = mode
        self.companyWeekdays = companyWeekdays
        self.schoolWeeks = schoolWeeks
        self.companyWeeks = companyWeeks
        self.schoolAnchor = schoolAnchor
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self.defaults
        mode = try c.decodeIfPresent(Mode.self, forKey: .mode) ?? d.mode
        companyWeekdays = try c.decodeIfPresent(Set<Int>.self, forKey: .companyWeekdays) ?? d.companyWeekdays
        schoolWeeks = try c.decodeIfPresent(Int.self, forKey: .schoolWeeks) ?? d.schoolWeeks
        companyWeeks = try c.decodeIfPresent(Int.self, forKey: .companyWeeks) ?? d.companyWeeks
        schoolAnchor = try c.decodeIfPresent(Date.self, forKey: .schoolAnchor)
    }

    /// Jour en entreprise ? Jamais le week-end ni un jour avec des cours.
    public func isCompanyDay(_ day: Date, schedule: Schedule, calendar: Calendar) -> Bool {
        let weekday = calendar.component(.weekday, from: day)
        guard mode != .off, (2...6).contains(weekday), schedule.courses(on: day, calendar: calendar).isEmpty,
              Holidays.name(of: day, calendar: calendar) == nil
        else { return false }
        switch mode {
        case .off: return false
        case .auto: return true
        case .weekdays: return companyWeekdays.contains(weekday)
        case .weeks:
            let cycle = max(1, schoolWeeks) + max(0, companyWeeks)
            guard let anchor = schoolAnchor, companyWeeks > 0,
                  let a = calendar.dateInterval(of: .weekOfYear, for: anchor)?.start,
                  let d = calendar.dateInterval(of: .weekOfYear, for: day)?.start
            else { return false }
            let weeks = Int((d.timeIntervalSince(a) / (7 * 86_400)).rounded())
            let phase = ((weeks % cycle) + cycle) % cycle
            return phase >= max(1, schoolWeeks)
        }
    }
}

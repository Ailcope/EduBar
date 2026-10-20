import Foundation

/// Nombre lu de façon très tolérante : `null`, chaîne vide ou illisible donnent `nil`,
/// une chaîne « 12,5 » ou « 12.5 » donne 12.5, un objet `{"grade": 12}` ou `{"value": 12}` donne 12.
struct LenientNumber: Decodable {
    let value: Double?

    init(value: Double?) { self.value = value }

    init(from decoder: any Decoder) throws {
        if let c = try? decoder.singleValueContainer() {
            if c.decodeNil() { value = nil; return }
            if let d = try? c.decode(Double.self) { value = d; return }
            if let s = try? c.decode(String.self) {
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
                value = t.isEmpty ? nil : Double(t)
                return
            }
        }
        if let k = try? decoder.container(keyedBy: AnyKey.self) {
            for name in ["grade", "value", "note"] {
                if let key = AnyKey(stringValue: name), let n = try? k.decodeIfPresent(LenientNumber.self, forKey: key),
                   let v = n.value {
                    value = v
                    return
                }
            }
        }
        value = nil
    }
}

/// Chaîne lue de façon tolérante : un nombre est converti, `null` donne `nil`.
struct LenientString: Decodable {
    let value: String?

    init(from decoder: any Decoder) throws {
        guard let c = try? decoder.singleValueContainer(), !c.decodeNil() else { value = nil; return }
        if let s = try? c.decode(String.self) { value = s; return }
        if let i = try? c.decode(Int.self) { value = String(i); return }
        if let d = try? c.decode(Double.self) { value = String(format: "%g", d); return }
        value = nil
    }
}

struct AnyKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

extension KeyedDecodingContainer where K == AnyKey {
    func number(_ name: String) -> Double? {
        guard let key = AnyKey(stringValue: name) else { return nil }
        return (try? decodeIfPresent(LenientNumber.self, forKey: key))?.value
    }

    func string(_ name: String) -> String? {
        guard let key = AnyKey(stringValue: name) else { return nil }
        return (try? decodeIfPresent(LenientString.self, forKey: key))?.value
    }

    func numbers(_ name: String) -> [Double] {
        guard let key = AnyKey(stringValue: name),
              let list = try? decodeIfPresent([LenientNumber].self, forKey: key) else { return [] }
        return list.compactMap(\.value)
    }
}

/// Carnet de notes : une entrée par matière.
public struct GradeBook: Codable, Sendable, Equatable {
    public var subjects: [Subject]

    public init(subjects: [Subject]) { self.subjects = subjects }

    public struct Subject: Codable, Sendable, Equatable, Identifiable {
        /// Année + semestre + matière : deux semestres ou deux années de la même matière restent distincts.
        public let id: String
        public var course: String
        public var grades: [Double]
        public var exam: Double?
        public var average: Double?
        public var ccAverage: Double?
        public var coef: Double?
        public var ects: Double?
        public var teacher: String?
        public var trimester: Int?
        public var year: Int?
        public var trimesterName: String?
        public var letterMark: String?
        public var absences: Int?
        public var lates: Int?
        public var rcID: Int?

        public init(
            course: String, grades: [Double] = [], exam: Double? = nil, average: Double? = nil,
            ccAverage: Double? = nil, coef: Double? = nil, ects: Double? = nil,
            teacher: String? = nil, trimester: Int? = nil, year: Int? = nil,
            trimesterName: String? = nil, letterMark: String? = nil,
            absences: Int? = nil, lates: Int? = nil, rcID: Int? = nil
        ) {
            self.id = Self.makeID(course: course, trimester: trimester, year: year)
            self.course = course
            self.grades = grades
            self.exam = exam
            self.average = average
            self.ccAverage = ccAverage
            self.coef = coef
            self.ects = ects
            self.teacher = teacher
            self.trimester = trimester
            self.year = year
            self.trimesterName = trimesterName
            self.letterMark = letterMark
            self.absences = absences
            self.lates = lates
            self.rcID = rcID
        }

        /// Les carnets archivés par une ancienne version n'ont pas les nouveaux champs,
        /// et leur `id` n'inclut pas l'année : on le recalcule.
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let course = try c.decode(String.self, forKey: .course)
            let trimester = try c.decodeIfPresent(Int.self, forKey: .trimester)
            let year = try c.decodeIfPresent(Int.self, forKey: .year)
            self.init(
                course: course, grades: try c.decodeIfPresent([Double].self, forKey: .grades) ?? [],
                exam: try c.decodeIfPresent(Double.self, forKey: .exam),
                average: try c.decodeIfPresent(Double.self, forKey: .average),
                ccAverage: try c.decodeIfPresent(Double.self, forKey: .ccAverage),
                coef: try c.decodeIfPresent(Double.self, forKey: .coef),
                ects: try c.decodeIfPresent(Double.self, forKey: .ects),
                teacher: try c.decodeIfPresent(String.self, forKey: .teacher),
                trimester: trimester, year: year,
                trimesterName: try c.decodeIfPresent(String.self, forKey: .trimesterName),
                letterMark: try c.decodeIfPresent(String.self, forKey: .letterMark),
                absences: try c.decodeIfPresent(Int.self, forKey: .absences),
                lates: try c.decodeIfPresent(Int.self, forKey: .lates),
                rcID: try c.decodeIfPresent(Int.self, forKey: .rcID)
            )
        }

        static func makeID(course: String, trimester: Int?, year: Int?) -> String {
            "\(year ?? 0)#\(trimester ?? 0)#\(course)"
        }

        /// Matière sans le préfixe de période (« T1 - », « S1 - »).
        public var shortCourse: String {
            guard let range = course.range(of: #"^[TS]\d+\s*-\s*"#, options: .regularExpression) else { return course }
            return String(course[range.upperBound...])
        }

        /// La période de la matière, ou `nil` si l'année ou le semestre manque.
        public var period: Period? {
            guard let year, let trimester else { return nil }
            return Period(year: year, trimester: trimester, name: trimesterName ?? L10n.tr("Semestre", "Semester"))
        }
    }

    /// Une période de notes : année scolaire (année de début) + semestre.
    public struct Period: Hashable, Sendable, Codable, Identifiable {
        public let year: Int
        public let trimester: Int
        public let name: String

        public init(year: Int, trimester: Int, name: String) {
            self.year = year
            self.trimester = trimester
            self.name = name
        }

        public var id: String { "\(year)#\(trimester)" }

        /// « 2026-2027 · Semestre 1 ».
        public var title: String { "\(year)-\(year + 1) · \(name)" }

        /// « S1 2026-27 » si le nom commence par « Semestre N », sinon le nom.
        public var shortTitle: String {
            guard let m = name.firstMatch(of: /^Semestre\s+(\d+)/) else { return name }
            return "S\(m.1) \(year)-\(String(format: "%02d", (year + 1) % 100))"
        }
    }

    /// Périodes uniques, de la plus récente à la plus ancienne.
    public var periods: [Period] {
        var seen = Set<String>()
        let all = subjects.compactMap(\.period).filter { seen.insert($0.id).inserted }
        return all.sorted {
            if $0.year != $1.year { return $0.year > $1.year }
            if $0.trimester != $1.trimester { return $0.trimester > $1.trimester }
            return $0.name < $1.name
        }
    }

    /// Matières d'une période, triées par nom court (sans tenir compte de la casse).
    public func subjects(in period: Period) -> [Subject] {
        subjects.filter { $0.year == period.year && $0.trimester == period.trimester }
            .sorted { $0.shortCourse.localizedCaseInsensitiveCompare($1.shortCourse) == .orderedAscending }
    }

    /// Union par id ; en cas de doublon, l'autre carnet l'emporte (la position d'origine est conservée).
    public func merging(_ other: GradeBook) -> GradeBook {
        var result = subjects
        var index = Dictionary(result.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        for s in other.subjects {
            if let i = index[s.id] {
                result[i] = s
            } else {
                index[s.id] = result.count
                result.append(s)
            }
        }
        return GradeBook(subjects: result)
    }

    /// Moyenne pondérée des matières de la période : Σ(moyenne × coef) / Σ coef, coef > 0 et moyenne connues.
    public func weightedAverage(in period: Period) -> Double? {
        var sum = 0.0, weight = 0.0
        for s in subjects(in: period) {
            guard let a = s.average, let c = s.coef, c > 0 else { continue }
            sum += a * c
            weight += c
        }
        return weight > 0 ? sum / weight : nil
    }

    /// Nombre maximal de notes de CC dans la période (colonnes CC1…CCn).
    public func maxCCCount(in period: Period) -> Int {
        subjects(in: period).map(\.grades.count).max() ?? 0
    }

    /// Toutes les notes saisies dans la période (CC puis examen, matière par matière).
    public func marks(in period: Period) -> [Double] {
        subjects(in: period).flatMap { $0.grades + ($0.exam.map { [$0] } ?? []) }
    }

    /// Vrai si au moins une note est saisie dans la période.
    public func hasMarks(in period: Period) -> Bool { !marks(in: period).isEmpty }

    /// Statistiques du semestre, comme le panneau de MyPrettyGradES.
    public struct Stats: Equatable, Sendable {
        /// Moyenne pondérée des matières (coef), nil sans moyenne de matière.
        public let weighted: Double?
        /// Moyenne simple de toutes les notes saisies.
        public let simple: Double?
        public let min: Double?
        public let max: Double?
        /// Écart-type (population) des notes saisies ; nil avec moins de deux notes.
        public let standardDeviation: Double?
        public let markCount: Int
        public let subjectCount: Int
        /// Matières avec au moins une note.
        public let gradedSubjectCount: Int
        public let absences: Int
        public let lates: Int
    }

    public func stats(in period: Period) -> Stats {
        let list = subjects(in: period)
        let marks = marks(in: period)
        let simple = marks.isEmpty ? nil : marks.reduce(0, +) / Double(marks.count)
        var sd: Double?
        if marks.count >= 2, let m = simple {
            sd = (marks.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(marks.count)).squareRoot()
        }
        return Stats(
            weighted: weightedAverage(in: period), simple: simple, min: marks.min(), max: marks.max(),
            standardDeviation: sd, markCount: marks.count, subjectCount: list.count,
            gradedSubjectCount: list.filter { !$0.grades.isEmpty || $0.exam != nil }.count,
            absences: list.compactMap(\.absences).reduce(0, +), lates: list.compactMap(\.lates).reduce(0, +)
        )
    }
}

/// Couleur d'une note, comme MyPrettyGradES : vert au-dessus de 10, jaune à 10, rouge en dessous.
public enum MarkTone: Sendable, Equatable {
    case good, neutral, bad

    public init(_ value: Double) {
        self = value > 10 ? .good : value < 10 ? .bad : .neutral
    }
}

/// Choix de la période affichée par défaut.
public enum PeriodPicker {
    /// Période du cours le plus proche de `now` (en cours, sinon prochain, sinon dernier passé)
    /// dont le `periodID` existe dans le carnet ; sinon la période la plus récente.
    public static func current(book: GradeBook, courses: [Course], now: Date) -> GradeBook.Period? {
        let periods = book.periods
        let known = courses.filter { c in c.periodID.map { id in periods.contains { $0.trimester == id } } ?? false }
        let candidate = known.filter { $0.start <= now && now < $0.end }.min { $0.start < $1.start }
            ?? known.filter { $0.start > now }.min { $0.start < $1.start }
            ?? known.filter { $0.end <= now }.max { $0.end < $1.end }
        if let id = candidate?.periodID {
            // Plusieurs années peuvent partager un id de semestre : on prend la plus récente.
            if let p = periods.first(where: { $0.trimester == id }) { return p }
        }
        return fallback(periods: periods, now: now)
    }

    /// Comme MyPrettyGradES : si la période courante n'a encore aucune note, la période la plus
    /// récente qui en a (sinon la courante). `current` : résultat de `current(book:courses:now:)`.
    public static func withMarks(book: GradeBook, current: GradeBook.Period?) -> GradeBook.Period? {
        guard let current else { return nil }
        if book.hasMarks(in: current) { return current }
        return book.periods.first { book.hasMarks(in: $0) } ?? current
    }

    /// Sans agenda exploitable : dans l'année la plus récente, le semestre que la date suggère
    /// (septembre à janvier : « Semestre 1 », février à août : « Semestre 2 »), sinon la période
    /// la plus récente.
    static func fallback(periods: [GradeBook.Period], now: Date, calendar: Calendar = .current) -> GradeBook.Period? {
        guard let latest = periods.first else { return nil }
        let month = calendar.component(.month, from: now)
        let wanted = (month >= 9 || month == 1) ? "1" : "2"
        let sameYear = periods.filter { $0.year == latest.year }
        return sameYear.first { $0.name.range(of: #"\b\#(wanted)\b"#, options: .regularExpression) != nil } ?? latest
    }
}

/// Une note apparue depuis le dernier chargement.
public struct NewGrade: Sendable, Equatable {
    public let course: String
    /// « CC1 », « CC2 »…, « Examen » ou « Moyenne ».
    public let label: String
    public let value: Double
    /// Période de la matière, pour surligner dans le bon onglet.
    public let period: GradeBook.Period?

    /// `label` (clé stable, sert aux identifiants) dans la langue d'affichage.
    public var displayLabel: String {
        switch label {
        case "Examen": L10n.tr("Examen", "Exam")
        case "Moyenne": L10n.tr("Moyenne", "Average")
        default: label
        }
    }

    public init(course: String, label: String, value: Double, period: GradeBook.Period? = nil) {
        self.course = course
        self.label = label
        self.value = value
        self.period = period
    }

    var shortCourse: String {
        GradeBook.Subject(course: course).shortCourse
    }
}

public enum GESGrades {
    private struct Envelope: Decodable { let result: [RawSubject]? }

    private struct RawSubject: Decodable {
        let subject: GradeBook.Subject?

        init(from decoder: any Decoder) throws {
            guard let c = try? decoder.container(keyedBy: AnyKey.self),
                  let course = c.string("course")?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !course.isEmpty else { subject = nil; return }
            let name = [c.string("teacher_civility"), c.string("teacher_first_name"), c.string("teacher_last_name")]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            // 0 dans ccaverage veut dire « pas de note » (Bot-Myges).
            let cc = c.number("ccaverage").flatMap { $0 == 0 ? nil : $0 }
            subject = GradeBook.Subject(
                course: course, grades: c.numbers("grades"), exam: c.number("exam"),
                average: c.number("average"), ccAverage: cc, coef: c.number("coef"), ects: c.number("ects"),
                teacher: name.isEmpty ? nil : name,
                trimester: c.number("trimester").map { Int($0) }, year: c.number("year").map { Int($0) },
                trimesterName: c.string("trimester_name")?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                letterMark: c.string("letter_mark")?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                absences: c.number("absences").map { Int($0) }, lates: c.number("lates").map { Int($0) },
                rcID: c.number("rc_id").map { Int($0) }
            )
        }
    }

    /// Accepte l'enveloppe `{"result": [...]}` ou un tableau nu.
    public static func gradeBook(from data: Data) throws -> GradeBook {
        let decoder = JSONDecoder()
        let raw: [RawSubject]
        if let env = try? decoder.decode(Envelope.self, from: data), let list = env.result {
            raw = list
        } else {
            raw = try decoder.decode([RawSubject].self, from: data)
        }
        return GradeBook(subjects: raw.compactMap(\.subject))
    }
}

public enum GradeDiff {
    /// Notes apparues entre deux chargements. Premier chargement (`old == nil`) : rien, pour ne pas notifier.
    public static func newGrades(old: GradeBook?, new: GradeBook) -> [NewGrade] {
        guard let old else { return [] }
        let known = Dictionary(old.subjects.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var result: [NewGrade] = []
        for s in new.subjects {
            if let before = known[s.id] {
                for (i, g) in s.grades.enumerated() where i >= before.grades.count {
                    result.append(NewGrade(course: s.course, label: "CC\(i + 1)", value: g, period: s.period))
                }
                if before.exam == nil, let e = s.exam { result.append(NewGrade(course: s.course, label: "Examen", value: e, period: s.period)) }
                if before.average == nil, let a = s.average { result.append(NewGrade(course: s.course, label: "Moyenne", value: a, period: s.period)) }
            } else {
                for (i, g) in s.grades.enumerated() {
                    result.append(NewGrade(course: s.course, label: "CC\(i + 1)", value: g, period: s.period))
                }
                if let e = s.exam { result.append(NewGrade(course: s.course, label: "Examen", value: e, period: s.period)) }
            }
        }
        return result
    }

    /// Une notification par note, ou une seule groupée au-delà de 4.
    public static func notifications(_ grades: [NewGrade]) -> [PendingNotification] {
        if grades.count > 4 {
            var seen = Set<String>()
            let courses = grades.map(\.shortCourse).filter { seen.insert($0).inserted }
            let key = grades.map { "\($0.course)-\($0.label)-\(format($0.value))" }.joined(separator: "|")
            return [PendingNotification(
                id: "grades-\(key)", title: L10n.tr("\(grades.count) nouvelles notes", "\(grades.count) new grades"),
                body: courses.joined(separator: ", "), url: nil
            )]
        }
        return grades.map {
            PendingNotification(
                id: "grade-\($0.course)-\($0.label)-\(format($0.value))",
                title: L10n.tr("Nouvelle note : \($0.shortCourse)", "New grade: \($0.shortCourse)"),
                body: L10n.tr("\($0.displayLabel) : \(format($0.value))/20", "\($0.displayLabel): \(format($0.value))/20"),
                url: nil
            )
        }
    }

    private static func format(_ v: Double) -> String { String(format: "%g", v) }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

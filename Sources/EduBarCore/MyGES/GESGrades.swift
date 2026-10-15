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
        /// Matière + trimestre : deux trimestres de la même matière restent distincts.
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

        public init(
            course: String, grades: [Double] = [], exam: Double? = nil, average: Double? = nil,
            ccAverage: Double? = nil, coef: Double? = nil, ects: Double? = nil,
            teacher: String? = nil, trimester: Int? = nil, year: Int? = nil
        ) {
            self.id = Self.makeID(course: course, trimester: trimester)
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
        }

        static func makeID(course: String, trimester: Int?) -> String {
            course + "#" + (trimester.map(String.init) ?? "")
        }

        /// Matière sans le préfixe de période (« T1 - »), comme `Course.shortTitle`.
        public var shortCourse: String {
            guard let range = course.range(of: #"^T\d+\s*-\s*"#, options: .regularExpression) else { return course }
            return String(course[range.upperBound...])
        }
    }
}

/// Une note apparue depuis le dernier chargement.
public struct NewGrade: Sendable, Equatable {
    public let course: String
    /// « CC1 », « CC2 »…, « Examen » ou « Moyenne ».
    public let label: String
    public let value: Double

    public init(course: String, label: String, value: Double) {
        self.course = course
        self.label = label
        self.value = value
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
                trimester: c.number("trimester").map { Int($0) }, year: c.number("year").map { Int($0) }
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
                    result.append(NewGrade(course: s.course, label: "CC\(i + 1)", value: g))
                }
                if before.exam == nil, let e = s.exam { result.append(NewGrade(course: s.course, label: "Examen", value: e)) }
                if before.average == nil, let a = s.average { result.append(NewGrade(course: s.course, label: "Moyenne", value: a)) }
            } else {
                for (i, g) in s.grades.enumerated() {
                    result.append(NewGrade(course: s.course, label: "CC\(i + 1)", value: g))
                }
                if let e = s.exam { result.append(NewGrade(course: s.course, label: "Examen", value: e)) }
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
                id: "grades-\(key)", title: "\(grades.count) nouvelles notes",
                body: courses.joined(separator: ", "), url: nil
            )]
        }
        return grades.map {
            PendingNotification(
                id: "grade-\($0.course)-\($0.label)-\(format($0.value))",
                title: "Nouvelle note : \($0.shortCourse)",
                body: "\($0.label) : \(format($0.value))/20", url: nil
            )
        }
    }

    private static func format(_ v: Double) -> String { String(format: "%g", v) }
}
